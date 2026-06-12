// One-time migration for the Multiple Named Lists feature.
//
// Existing `list_items` and `shares` predate the `listId` column, so after the
// schema is provisioned their `listId` is null. Bootstrap now reads items with a
// strict `Query.equal('listId', <defaultListId>)`, which would hide every legacy
// item until it carries a listId. This script back-fills them:
//
//   1. For each owner (profile), ensure a default `user_lists` row exists.
//   2. Set `listId` on every `list_items` row with an empty/null listId to that
//      owner's default list id.
//   3. Same for `shares` (a legacy share targeted the owner's whole account, i.e.
//      their default list).
//
// Idempotent: only touches rows whose listId is still empty, so re-running is a
// no-op. Defaults to a DRY RUN (reports counts only); pass `--apply` to write.
//
// Run AFTER `provision` (which adds the column + collection) and BEFORE deploying
// the new function code, so there is never a window where items appear missing.
//
//   dart run bin/backfill_lists.dart          # dry run
//   dart run bin/backfill_lists.dart --apply  # perform the migration

import 'dart:io';

import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart' as models;
import 'package:moona_backend/moona_backend.dart';

final _dotenv = <String, String>{};

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');
  loadDotEnv();

  final client = Client()
      .setEndpoint(requireEnvValue('APPWRITE_ENDPOINT'))
      .setProject(requireEnvValue('APPWRITE_PROJECT_ID'))
      .setKey(requireEnvValue('APPWRITE_API_KEY'));
  final tablesDB = TablesDB(client);

  stdout.writeln(apply
      ? '== Back-filling list ids (APPLY) =='
      : '== Back-filling list ids (DRY RUN — pass --apply to write) ==');

  final profiles = await _allRows(tablesDB, CollectionIds.profiles);
  stdout.writeln('Owners (profiles): ${profiles.length}');

  var listsCreated = 0;
  var itemsUpdated = 0;
  var sharesUpdated = 0;

  for (final profile in profiles) {
    final ownerId = profile.$id;

    final defaultListId =
        await _ensureDefaultList(tablesDB, ownerId, apply: apply, onCreate: () {
      listsCreated++;
    });
    if (defaultListId == null) {
      stdout.writeln('  ! $ownerId: no default list (dry run) — would create one '
          'and assign items to it');
    }

    itemsUpdated += await _backfillColumn(
      tablesDB,
      tableId: CollectionIds.listItems,
      ownerId: ownerId,
      defaultListId: defaultListId,
      apply: apply,
    );
    sharesUpdated += await _backfillColumn(
      tablesDB,
      tableId: CollectionIds.shares,
      ownerId: ownerId,
      defaultListId: defaultListId,
      apply: apply,
    );
  }

  stdout.writeln('---');
  stdout.writeln('Default lists ${apply ? 'created' : 'to create'}: $listsCreated');
  stdout.writeln('list_items ${apply ? 'updated' : 'to update'}: $itemsUpdated');
  stdout.writeln('shares ${apply ? 'updated' : 'to update'}: $sharesUpdated');
  stdout.writeln(apply
      ? 'Migration complete.'
      : 'Dry run complete — re-run with --apply to perform the migration.');
}

/// Returns the owner's default list id, creating one when missing. In a dry run
/// with no existing list, returns null (nothing is written) but still invokes
/// [onCreate] so the summary can count it.
Future<String?> _ensureDefaultList(
  TablesDB tablesDB,
  String ownerId, {
  required bool apply,
  required void Function() onCreate,
}) async {
  final lists = await _allRows(
    tablesDB,
    CollectionIds.userLists,
    [Query.equal('ownerId', ownerId)],
  );
  if (lists.isNotEmpty) {
    final byDefault = lists.where((l) => l.data['isDefault'] == true).firstOrNull;
    return (byDefault ?? lists.first).$id;
  }

  onCreate();
  if (!apply) return null;

  final created = await tablesDB.createRow(
    databaseId: databaseId,
    tableId: CollectionIds.userLists,
    rowId: ID.unique(),
    data: buildUserListDocument(
      ownerId: ownerId,
      name: 'My List',
      isDefault: true,
    ),
    permissions: [
      Permission.read(Role.user(ownerId)),
      Permission.update(Role.user(ownerId)),
      Permission.delete(Role.user(ownerId)),
    ],
  );
  return created.$id;
}

/// Sets `listId` on every row of [tableId] owned by [ownerId] whose listId is
/// still empty/null. Returns the count of rows that needed updating.
Future<int> _backfillColumn(
  TablesDB tablesDB, {
  required String tableId,
  required String ownerId,
  required String? defaultListId,
  required bool apply,
}) async {
  final rows = await _allRows(
    tablesDB,
    tableId,
    [Query.equal('ownerId', ownerId)],
  );
  final orphans =
      rows.where((r) => (r.data['listId'] ?? '').toString().isEmpty).toList();
  if (orphans.isEmpty) return 0;

  if (!apply || defaultListId == null) return orphans.length;

  for (final row in orphans) {
    await tablesDB.updateRow(
      databaseId: databaseId,
      tableId: tableId,
      rowId: row.$id,
      data: {'listId': defaultListId, 'updatedAt': nowIso()},
    );
  }
  return orphans.length;
}

/// Pages through every row of a table (admin key, no permission filtering).
Future<List<models.Row>> _allRows(
  TablesDB tablesDB,
  String tableId, [
  List<String> extraQueries = const [],
]) async {
  const pageSize = 100;
  final all = <models.Row>[];
  var offset = 0;
  while (true) {
    final page = await tablesDB.listRows(
      databaseId: databaseId,
      tableId: tableId,
      queries: [...extraQueries, Query.limit(pageSize), Query.offset(offset)],
    );
    all.addAll(page.rows);
    if (page.rows.length < pageSize) break;
    offset += pageSize;
  }
  return all;
}

void loadDotEnv() {
  final file = File('.env');
  if (!file.existsSync()) return;
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = trimmed.indexOf('=');
    if (separator <= 0) continue;
    final key = trimmed.substring(0, separator).trim();
    var value = trimmed.substring(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    _dotenv[key] = value;
  }
}

String requireEnvValue(String key) {
  final value = _dotenv[key] ?? Platform.environment[key];
  if (value == null || value.isEmpty) {
    throw StateError('Missing required environment variable $key');
  }
  return value;
}
