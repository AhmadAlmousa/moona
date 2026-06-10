import 'dart:io';

import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/enums.dart';
import 'package:moona_backend/moona_backend.dart';

final _dotenv = <String, String>{};

Future<void> main() async {
  loadDotEnv();

  final client = Client()
      .setEndpoint(requireEnvValue('APPWRITE_ENDPOINT'))
      .setProject(requireEnvValue('APPWRITE_PROJECT_ID'))
      .setKey(requireEnvValue('APPWRITE_API_KEY'));

  final tablesDB = TablesDB(client);
  final storage = Storage(client);
  final functions = Functions(client);

  await provision(tablesDB, storage, functions);
  stdout.writeln('Moona Appwrite backend provisioning complete.');
}

Future<void> provision(
  TablesDB tablesDB,
  Storage storage,
  Functions functions,
) async {
  await ensureDatabase(tablesDB);

  for (final table in appwriteSchema.tables) {
    await ensureTable(tablesDB, table);
    await ensureAttributes(tablesDB, table);
    await Future<void>.delayed(
      Duration(milliseconds: intFromEnv('MOONA_PROVISION_WAIT_MS', 750)),
    );
    await ensureIndexes(tablesDB, table);
  }

  await ensureBucket(storage);
  await seedCatalogs(tablesDB);
  await ensureFunctions(functions);
}

Future<void> ensureDatabase(TablesDB tablesDB) async {
  try {
    await ignoreConflict(
      () => tablesDB.create(
        databaseId: appwriteSchema.databaseId,
        name: appwriteSchema.databaseName,
      ),
    );
  } catch (error) {
    if (!isAdditionalResourceLimit(error)) rethrow;

    final existing = await tablesDB.get(databaseId: appwriteSchema.databaseId);
    if (existing.$id != appwriteSchema.databaseId) rethrow;
  }
}

Future<void> ensureTable(TablesDB tablesDB, TableSpec table) async {
  await ignoreConflict(
    () => tablesDB.createTable(
      databaseId: databaseId,
      tableId: table.id,
      name: table.name,
      permissions: table.rowSecurity ? [] : [Permission.read(Role.users())],
      rowSecurity: table.rowSecurity,
      enabled: true,
    ),
  );
}

Future<void> ensureAttributes(TablesDB tablesDB, TableSpec table) async {
  for (final attribute in table.attributes) {
    await ignoreConflict(() => createAttribute(tablesDB, table.id, attribute));
  }
}

Future<dynamic> createAttribute(
  TablesDB tablesDB,
  String tableId,
  AttributeSpec attribute,
) {
  switch (attribute.type) {
    case 'string':
      return tablesDB.createVarcharColumn(
        databaseId: databaseId,
        tableId: tableId,
        key: attribute.key,
        size: attribute.size!,
        xrequired: attribute.required,
        xdefault: attribute.defaultValue as String?,
        array: attribute.array,
      );
    case 'integer':
      return tablesDB.createIntegerColumn(
        databaseId: databaseId,
        tableId: tableId,
        key: attribute.key,
        xrequired: attribute.required,
        min: attribute.min?.toInt(),
        max: attribute.max?.toInt(),
        xdefault: attribute.defaultValue as int?,
        array: attribute.array,
      );
    case 'float':
      return tablesDB.createFloatColumn(
        databaseId: databaseId,
        tableId: tableId,
        key: attribute.key,
        xrequired: attribute.required,
        min: attribute.min?.toDouble(),
        max: attribute.max?.toDouble(),
        xdefault: attribute.defaultValue as double?,
        array: attribute.array,
      );
    case 'boolean':
      return tablesDB.createBooleanColumn(
        databaseId: databaseId,
        tableId: tableId,
        key: attribute.key,
        xrequired: attribute.required,
        xdefault: attribute.defaultValue as bool?,
        array: attribute.array,
      );
    case 'datetime':
      return tablesDB.createDatetimeColumn(
        databaseId: databaseId,
        tableId: tableId,
        key: attribute.key,
        xrequired: attribute.required,
        xdefault: attribute.defaultValue as String?,
        array: attribute.array,
      );
    case 'enum':
      return tablesDB.createEnumColumn(
        databaseId: databaseId,
        tableId: tableId,
        key: attribute.key,
        elements: attribute.elements,
        xrequired: attribute.required,
        xdefault: attribute.defaultValue as String?,
        array: attribute.array,
      );
  }

  throw StateError('Unsupported attribute type ${attribute.type}');
}

Future<void> ensureIndexes(TablesDB tablesDB, TableSpec table) async {
  for (final index in table.indexes) {
    await ignoreConflict(
      () => tablesDB.createIndex(
        databaseId: databaseId,
        tableId: table.id,
        key: index.key,
        type: indexType(index.type),
        columns: index.attributes,
        orders:
            index.orders.isEmpty ? null : index.orders.map(orderBy).toList(),
      ),
    );
  }
}

Future<void> ensureBucket(Storage storage) async {
  final bucket = appwriteSchema.bucket;
  try {
    await ignoreConflict(
      () => storage.createBucket(
        bucketId: bucket.id,
        name: bucket.name,
        permissions: [],
        fileSecurity: bucket.fileSecurity,
        enabled: bucket.enabled,
        maximumFileSize: bucket.maximumFileSize,
        allowedFileExtensions: bucket.allowedFileExtensions,
      ),
    );
  } catch (error) {
    if (!isAdditionalResourceLimit(error)) rethrow;

    final existing = await storage.getBucket(bucketId: bucket.id);
    if (existing.$id != bucket.id) rethrow;
  }
}

Future<void> seedCatalogs(TablesDB tablesDB) async {
  for (final category in defaultCategories) {
    await upsertRow(
        tablesDB, CollectionIds.categories, category['id'] as String, {
      'stableId': category['id'],
      'nameAr': category['nameAr'],
      'nameEn': category['nameEn'],
      'emoji': category['emoji'],
      'sortOrder': category['sortOrder'],
      'active': category['active'],
      'createdAt': nowIso(),
      'updatedAt': nowIso(),
    });
  }

  for (final unit in defaultUnits) {
    await upsertRow(tablesDB, CollectionIds.units, unit['id'] as String, {
      'stableId': unit['id'],
      'nameAr': unit['nameAr'],
      'nameEn': unit['nameEn'],
      'sortOrder': unit['sortOrder'],
      'active': unit['active'],
      'createdAt': nowIso(),
      'updatedAt': nowIso(),
    });
  }

  for (final product in defaultProducts) {
    final document = buildProductDocument(product, product['id'] as String);
    await upsertRow(
      tablesDB,
      CollectionIds.products,
      product['id'] as String,
      removeId(document),
    );
  }
}

Future<void> upsertRow(
  TablesDB tablesDB,
  String tableId,
  String rowId,
  Map<String, dynamic> data,
) async {
  await ignoreConflict(
    () => tablesDB.createRow(
      databaseId: databaseId,
      tableId: tableId,
      rowId: rowId,
      data: data,
      permissions: [Permission.read(Role.users())],
    ),
    update: () => tablesDB.updateRow(
      databaseId: databaseId,
      tableId: tableId,
      rowId: rowId,
      data: {...withoutCreatedAt(data), 'updatedAt': nowIso()},
    ),
  );
}

Future<void> ensureFunctions(Functions functions) async {
  for (final spec in appwriteSchema.functions) {
    await ignoreConflict(
      () => functions.create(
        functionId: spec.functionId,
        name: spec.name,
        runtime: runtimeFrom(spec.runtime),
        execute: spec.execute,
        events: [],
        schedule: '',
        timeout: spec.timeout,
        enabled: true,
        logging: true,
        entrypoint: spec.entrypoint,
        commands: spec.commands,
        scopes: functionScopes,
      ),
      update: () => functions.update(
        functionId: spec.functionId,
        name: spec.name,
        runtime: runtimeFrom(spec.runtime),
        execute: spec.execute,
        events: [],
        schedule: '',
        timeout: spec.timeout,
        enabled: true,
        logging: true,
        entrypoint: spec.entrypoint,
        commands: spec.commands,
        scopes: functionScopes,
      ),
    );
    await ensureFunctionVariables(functions, spec);
  }
}

Future<void> ensureFunctionVariables(
  Functions functions,
  FunctionSpec spec,
) async {
  final variables = await functions.listVariables(functionId: spec.functionId);
  final existingByKey = <String, dynamic>{
    for (final variable in variables.variables) variable.key: variable,
  };

  for (final entry in functionVariables(spec).entries) {
    final existing = existingByKey[entry.key];
    if (existing == null) {
      await functions.createVariable(
        functionId: spec.functionId,
        variableId: entry.key,
        key: entry.key,
        value: entry.value,
        secret: false,
      );
    } else {
      await functions.updateVariable(
        functionId: spec.functionId,
        variableId: existing.$id.toString(),
        key: entry.key,
        value: entry.value,
        secret: false,
      );
    }
  }
}

Map<String, String> functionVariables(FunctionSpec spec) => {
      ...spec.environment,
      'APPWRITE_ENDPOINT': requireEnvValue('APPWRITE_ENDPOINT'),
      'APPWRITE_PROJECT_ID': requireEnvValue('APPWRITE_PROJECT_ID'),
      'MOONA_ADMIN_USER_IDS': envValue('MOONA_ADMIN_USER_IDS') ?? '',
      'MOONA_DEFAULT_LANGUAGE': envValue('MOONA_DEFAULT_LANGUAGE') ?? 'ar',
      'MOONA_DEFAULT_THEME': envValue('MOONA_DEFAULT_THEME') ?? 'light',
    };

Future<dynamic> ignoreConflict(
  Future<dynamic> Function() create, {
  Future<dynamic> Function()? update,
}) async {
  try {
    return await create();
  } catch (error) {
    if (isConflict(error)) {
      if (update != null) return update();
      return null;
    }
    rethrow;
  }
}

bool isConflict(Object error) {
  if (error is AppwriteException) {
    return error.code == 409 || (error.type ?? '').contains('already');
  }
  return false;
}

bool isAdditionalResourceLimit(Object error) {
  if (error is AppwriteException) {
    return error.code == 403 &&
        (error.type ?? '') == 'additional_resource_not_allowed';
  }
  return false;
}

Map<String, dynamic> removeId(Map<String, dynamic> document) {
  final copy = {...document};
  copy.remove('id');
  return copy;
}

Map<String, dynamic> withoutCreatedAt(Map<String, dynamic> document) {
  final copy = {...document};
  copy.remove('createdAt');
  return copy;
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
  final value = envValue(key);
  if (value == null || value.isEmpty) {
    throw StateError('Missing required environment variable $key');
  }
  return value;
}

String? envValue(String key) => _dotenv[key] ?? Platform.environment[key];

int intFromEnv(String key, int fallback) =>
    int.tryParse(envValue(key) ?? '') ?? fallback;

Runtime runtimeFrom(String runtime) {
  if (runtime == 'dart-3.1') return Runtime.dart31;
  if (runtime == 'dart-3.5') return Runtime.dart35;
  if (runtime == 'dart-3.8') return Runtime.dart38;
  if (runtime == 'dart-3.9') return Runtime.dart39;
  if (runtime == 'dart-3.10') return Runtime.dart310;
  if (runtime == 'dart-3.11') return Runtime.dart311;
  throw StateError('Unsupported function runtime $runtime');
}

TablesDBIndexType indexType(String type) {
  if (type == 'key') return TablesDBIndexType.key;
  if (type == 'unique') return TablesDBIndexType.unique;
  if (type == 'fulltext') return TablesDBIndexType.fulltext;
  throw StateError('Unsupported index type $type');
}

OrderBy orderBy(String order) {
  if (order == 'asc') return OrderBy.asc;
  if (order == 'desc') return OrderBy.desc;
  throw StateError('Unsupported index order $order');
}

const functionScopes = [
  ProjectKeyScopes.databasesRead,
  ProjectKeyScopes.tablesRead,
  ProjectKeyScopes.rowsRead,
  ProjectKeyScopes.rowsWrite,
  ProjectKeyScopes.usersRead,
  ProjectKeyScopes.usersWrite,
  ProjectKeyScopes.bucketsRead,
  ProjectKeyScopes.filesRead,
  ProjectKeyScopes.filesWrite,
  ProjectKeyScopes.tokensWrite,
  ProjectKeyScopes.messagesWrite,
];
