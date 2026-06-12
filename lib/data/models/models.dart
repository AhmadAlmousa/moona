/// Moona domain models.
///
/// Parsing is hand-rolled and defensive on purpose: backend documents carry
/// Appwrite `$`-prefixed keys and a few response fields are still being
/// confirmed (see `front_to_backend.md`), so every `fromJson` tolerates missing
/// or alternately-named keys.
library;

import 'package:flutter/foundation.dart';

String _string(Map<String, dynamic> m, String key, [String fallback = '']) {
  final v = m[key];
  return v == null ? fallback : v.toString();
}

String? _stringOrNull(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

bool _bool(Map<String, dynamic> m, String key, [bool fallback = false]) {
  final v = m[key];
  if (v is bool) return v;
  if (v == null) return fallback;
  return v.toString() == 'true';
}

double _double(Map<String, dynamic> m, String key, [double fallback = 1]) {
  final v = m[key];
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? fallback;
}

int _int(Map<String, dynamic> m, String key, [int fallback = 0]) {
  final v = m[key];
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

DateTime? _date(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

String _docId(Map<String, dynamic> m) =>
    (m[r'$id'] ?? m['id'] ?? m['userId'] ?? '').toString();

@immutable
class Profile {
  const Profile({
    required this.id,
    required this.phone,
    required this.displayName,
    required this.language,
    required this.theme,
    this.activeReceivedOwnerId,
    this.isAdmin = false,
  });

  final String id;
  final String phone;
  final String displayName;
  final String language;
  final String theme;
  final String? activeReceivedOwnerId;

  /// Whether the backend reports this account as an admin (in-app promotion or
  /// the `MOONA_ADMIN_USER_IDS` seed). Absent on older profiles ⇒ false.
  final bool isAdmin;

  bool get isDark => theme == 'dark';

  factory Profile.fromJson(Map<String, dynamic> m) => Profile(
    id: (m['userId'] ?? m[r'$id'] ?? m['id'] ?? '').toString(),
    phone: _string(m, 'phone'),
    displayName: _string(m, 'displayName'),
    language: _string(m, 'language', 'ar'),
    theme: _string(m, 'theme', 'light'),
    activeReceivedOwnerId: _stringOrNull(m, 'activeReceivedOwnerId'),
    isAdmin: m['isAdmin'] == true,
  );

  Profile copyWith({String? language, String? theme, String? displayName}) =>
      Profile(
        id: id,
        phone: phone,
        displayName: displayName ?? this.displayName,
        language: language ?? this.language,
        theme: theme ?? this.theme,
        activeReceivedOwnerId: activeReceivedOwnerId,
        isAdmin: isAdmin,
      );
}

/// A universal autocomplete term — a brand or a store name. Admin-curated;
/// surfaced read-only to clients via bootstrap `catalogs.brands/stores`.
@immutable
class CatalogTerm {
  const CatalogTerm({
    required this.id,
    required this.name,
    this.active = true,
  });

  final String id;
  final String name;
  final bool active;

  factory CatalogTerm.fromJson(Map<String, dynamic> m) => CatalogTerm(
    id: (m[r'$id'] ?? m['id'] ?? m['stableId'] ?? '').toString(),
    name: _string(m, 'name'),
    active: m['active'] != false,
  );
}

@immutable
class ShopCategory {
  const ShopCategory({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.emoji,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final String emoji;

  String label(String lang) => lang == 'ar' ? nameAr : nameEn;

  factory ShopCategory.fromJson(Map<String, dynamic> m) => ShopCategory(
    id: (m['stableId'] ?? m[r'$id'] ?? m['id'] ?? '').toString(),
    nameAr: _string(m, 'nameAr'),
    nameEn: _string(m, 'nameEn'),
    emoji: _string(m, 'emoji', '📦'),
  );
}

@immutable
class Unit {
  const Unit({required this.id, required this.nameAr, required this.nameEn});

  final String id;
  final String nameAr;
  final String nameEn;

  String label(String lang) => lang == 'ar' ? nameAr : nameEn;

  factory Unit.fromJson(Map<String, dynamic> m) => Unit(
    id: (m['stableId'] ?? m[r'$id'] ?? m['id'] ?? '').toString(),
    nameAr: _string(m, 'nameAr'),
    nameEn: _string(m, 'nameEn'),
  );
}

@immutable
class Product {
  const Product({
    required this.id,
    required this.displayName,
    this.nameAr,
    this.nameEn,
  });

  final String id;
  final String displayName;
  final String? nameAr;
  final String? nameEn;

  /// Name in the active language, falling back to [displayName].
  String label(String lang) {
    final localized = lang == 'ar' ? nameAr : nameEn;
    return (localized != null && localized.isNotEmpty)
        ? localized
        : displayName;
  }

  factory Product.fromJson(Map<String, dynamic> m) => Product(
    id: _docId(m),
    displayName: _string(m, 'displayName'),
    nameAr: _stringOrNull(m, 'nameAr'),
    nameEn: _stringOrNull(m, 'nameEn'),
  );
}

enum ItemStatus { active, trash }

@immutable
class ListItem {
  const ListItem({
    required this.id,
    required this.ownerId,
    required this.productId,
    required this.count,
    required this.important,
    required this.status,
    this.unitId,
    this.brand = '',
    this.seller = '',
    this.categoryId,
    this.imageFileId,
    this.note = '',
    this.trashedAt,
    this.trashedByUserId,
    this.trashedByDisplayName,
    this.trashReason,
    this.createdByUserId,
    this.createdByDisplayName,
    this.updatedByUserId,
    this.updatedByDisplayName,
    this.scratchedAt,
    this.scratchExpiresAt,
    this.scratchedByUserId,
  });

  final String id;
  final String ownerId;
  final String productId;
  final double count;
  final bool important;
  final ItemStatus status;
  final String? unitId;
  final String brand;
  final String seller;
  final String? categoryId;
  final String? imageFileId;
  final String note;
  final DateTime? trashedAt;
  final String? trashedByUserId;
  final String? trashedByDisplayName;
  final String? trashReason;

  /// Attribution (shared lists). The ids exist on the backend schema; the
  /// display names are enriched into `getBootstrapData` (Phase A) — both stay
  /// null until that deploy lands, so the UI simply shows nothing meanwhile.
  final String? createdByUserId;
  final String? createdByDisplayName;
  final String? updatedByUserId;
  final String? updatedByDisplayName;

  /// Backend-owned scratch state (Phase 3). While [scratchExpiresAt] is set the
  /// item is struck-through with a running countdown; the backend keeps
  /// `status: active` until the window lapses, then finalizes it to trash. The
  /// state lives on the row (not a client timer) so it survives restarts,
  /// propagates to other viewers via realtime, and the widget can commit it even
  /// if the app process is killed.
  final DateTime? scratchedAt;
  final DateTime? scratchExpiresAt;
  final String? scratchedByUserId;

  /// Whether this item is currently scratched (pending finalization). True only
  /// when [scratchExpiresAt] is set AND still in the future — items whose
  /// scratch window has already passed are treated as non-scratched on the
  /// client, preventing stale server fields from showing a spurious strike-through
  /// after a restore or a Buy-Again re-add.
  bool get isScratched => scratchExpiresAt?.isAfter(DateTime.now()) ?? false;

  factory ListItem.fromJson(Map<String, dynamic> m) => ListItem(
    id: _docId(m),
    ownerId: _string(m, 'ownerId'),
    productId: _string(m, 'productId'),
    count: _double(m, 'count'),
    important: _bool(m, 'important'),
    status: _string(m, 'status', 'active') == 'trash'
        ? ItemStatus.trash
        : ItemStatus.active,
    unitId: _stringOrNull(m, 'unitId'),
    brand: _string(m, 'brand'),
    seller: _string(m, 'seller'),
    categoryId: _stringOrNull(m, 'categoryId'),
    imageFileId: _stringOrNull(m, 'imageFileId'),
    note: _string(m, 'note'),
    trashedAt: _date(m, 'trashedAt'),
    trashedByUserId: _stringOrNull(m, 'trashedByUserId'),
    trashedByDisplayName: _stringOrNull(m, 'trashedByDisplayName'),
    trashReason: _stringOrNull(m, 'trashReason'),
    createdByUserId: _stringOrNull(m, 'createdByUserId'),
    createdByDisplayName: _stringOrNull(m, 'createdByDisplayName'),
    updatedByUserId: _stringOrNull(m, 'updatedByUserId'),
    updatedByDisplayName: _stringOrNull(m, 'updatedByDisplayName'),
    scratchedAt: _date(m, 'scratchedAt'),
    scratchExpiresAt: _date(m, 'scratchExpiresAt'),
    scratchedByUserId: _stringOrNull(m, 'scratchedByUserId'),
  );

  /// Copies the item, optionally changing [status] and the scratch fields. The
  /// scratch fields use a sentinel so they can be both set and cleared (passing
  /// `null` clears them; omitting them keeps the current value).
  ListItem copyWith({
    ItemStatus? status,
    Object? scratchedAt = _unset,
    Object? scratchExpiresAt = _unset,
    Object? scratchedByUserId = _unset,
  }) => ListItem(
    id: id,
    ownerId: ownerId,
    productId: productId,
    count: count,
    important: important,
    status: status ?? this.status,
    unitId: unitId,
    brand: brand,
    seller: seller,
    categoryId: categoryId,
    imageFileId: imageFileId,
    note: note,
    trashedAt: trashedAt,
    trashedByUserId: trashedByUserId,
    trashedByDisplayName: trashedByDisplayName,
    trashReason: trashReason,
    createdByUserId: createdByUserId,
    createdByDisplayName: createdByDisplayName,
    updatedByUserId: updatedByUserId,
    updatedByDisplayName: updatedByDisplayName,
    scratchedAt: scratchedAt == _unset
        ? this.scratchedAt
        : scratchedAt as DateTime?,
    scratchExpiresAt: scratchExpiresAt == _unset
        ? this.scratchExpiresAt
        : scratchExpiresAt as DateTime?,
    scratchedByUserId: scratchedByUserId == _unset
        ? this.scratchedByUserId
        : scratchedByUserId as String?,
  );
}

/// Sentinel for [ListItem.copyWith] so nullable scratch fields can be cleared.
const Object _unset = Object();

enum ShareStatus { pending, accepted, declined, revoked }

ShareStatus _shareStatus(String raw) => switch (raw) {
  'accepted' => ShareStatus.accepted,
  'declined' => ShareStatus.declined,
  'revoked' => ShareStatus.revoked,
  _ => ShareStatus.pending,
};

@immutable
class Share {
  const Share({
    required this.id,
    required this.ownerId,
    required this.viewerId,
    required this.status,
    this.counterpartyName,
    this.counterpartyPhone,
  });

  final String id;
  final String ownerId;
  final String viewerId;
  final ShareStatus status;

  /// Resolved display name / phone of the other party (pending backend
  /// support — see `front_to_backend.md` item 3). May be filled by the fake
  /// repo or a profiles lookup map.
  final String? counterpartyName;
  final String? counterpartyPhone;

  factory Share.fromJson(Map<String, dynamic> m) => Share(
    id: _docId(m),
    ownerId: _string(m, 'ownerId'),
    viewerId: _string(m, 'viewerId'),
    status: _shareStatus(_string(m, 'status', 'pending')),
    counterpartyName: _stringOrNull(m, 'counterpartyName'),
    counterpartyPhone: _stringOrNull(m, 'counterpartyPhone'),
  );

  Share withCounterparty(String? name, String? phone) => Share(
    id: id,
    ownerId: ownerId,
    viewerId: viewerId,
    status: status,
    counterpartyName: name ?? counterpartyName,
    counterpartyPhone: phone ?? counterpartyPhone,
  );
}

@immutable
class SharingStatus {
  const SharingStatus({
    required this.activeReceivedOwnerId,
    required this.outgoing,
    required this.incoming,
  });

  final String activeReceivedOwnerId;
  final List<Share> outgoing;
  final List<Share> incoming;

  static const empty = SharingStatus(
    activeReceivedOwnerId: '',
    outgoing: [],
    incoming: [],
  );

  /// The active accepted outgoing share (the viewer currently receiving my
  /// list), if any.
  Share? get acceptedOutgoing {
    for (final share in outgoing) {
      if (share.status == ShareStatus.accepted) return share;
    }
    return null;
  }

  /// Pending incoming requests awaiting my accept/decline.
  List<Share> get pendingIncoming =>
      incoming.where((s) => s.status == ShareStatus.pending).toList();

  factory SharingStatus.fromJson(Map<String, dynamic> m) => SharingStatus(
    activeReceivedOwnerId: _string(m, 'activeReceivedOwnerId'),
    outgoing: _shareList(m['outgoing']),
    incoming: _shareList(m['incoming']),
  );
}

List<Share> _shareList(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Share.fromJson(e.cast<String, dynamic>()))
      .toList();
}

/// One phone number's registration status from `lookupContacts`. Local contact
/// names are never sent to the backend — the picker rejoins them by
/// [phoneDigits].
@immutable
class ContactLookupEntry {
  const ContactLookupEntry({
    required this.phone,
    required this.phoneDigits,
    required this.registered,
    this.userId,
    this.displayName,
    this.isSelf = false,
  });

  final String phone;
  final String phoneDigits;
  final bool registered;
  final String? userId;

  /// Registered user's profile name (not the on-device contact name).
  final String? displayName;

  /// True when the number resolves to the signed-in user, so the picker can
  /// disable sharing with yourself before `requestShare` returns `share_self`.
  final bool isSelf;

  factory ContactLookupEntry.fromJson(Map<String, dynamic> m) =>
      ContactLookupEntry(
        phone: _string(m, 'phone'),
        phoneDigits: _string(m, 'phoneDigits'),
        registered: _bool(m, 'registered'),
        userId: _stringOrNull(m, 'userId'),
        displayName: _stringOrNull(m, 'displayName'),
        isSelf: _bool(m, 'isSelf'),
      );

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'phoneDigits': phoneDigits,
        'registered': registered,
        if (userId != null) 'userId': userId,
        if (displayName != null) 'displayName': displayName,
        'isSelf': isSelf,
      };
}

/// Result of `lookupContacts`: registered users first, with split convenience
/// getters for sectioned UI.
@immutable
class ContactLookupResult {
  const ContactLookupResult({this.contacts = const [], this.invalid = const []});

  final List<ContactLookupEntry> contacts;
  final List<String> invalid;

  List<ContactLookupEntry> get registered =>
      contacts.where((e) => e.registered).toList();
  List<ContactLookupEntry> get unregistered =>
      contacts.where((e) => !e.registered).toList();

  factory ContactLookupResult.fromJson(Map<String, dynamic> m) {
    final raw = m['contacts'];
    final contacts = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => ContactLookupEntry.fromJson(e.cast<String, dynamic>()))
              .toList()
        : <ContactLookupEntry>[];
    final invalidRaw = m['invalid'];
    final invalid = invalidRaw is List
        ? invalidRaw
              .map(
                (e) => e is Map
                    ? _string(e.cast<String, dynamic>(), 'phone')
                    : e.toString(),
              )
              .where((s) => s.isNotEmpty)
              .toList()
        : <String>[];
    return ContactLookupResult(contacts: contacts, invalid: invalid);
  }

  Map<String, dynamic> toJson() => {
        'contacts': [for (final e in contacts) e.toJson()],
        'invalid': invalid,
      };
}

/// A live "someone is shopping now" row from `shopping_presence` (Phase 3).
/// Keyed by [actorId] for the visible owner list; the client treats a heartbeat
/// older than [_staleAfter] as gone (the writer refreshes ~every 30s).
@immutable
class ShoppingPresence {
  const ShoppingPresence({
    required this.ownerId,
    required this.actorId,
    this.actorDisplayName,
    this.activeAt,
  });

  final String ownerId;
  final String actorId;
  final String? actorDisplayName;
  final DateTime? activeAt;

  static const Duration _staleAfter = Duration(seconds: 60);

  /// Whether the heartbeat is recent enough to still show as "shopping now".
  bool get isFresh {
    final at = activeAt;
    if (at == null) return false;
    return DateTime.now().difference(at).abs() < _staleAfter;
  }

  factory ShoppingPresence.fromJson(Map<String, dynamic> m) => ShoppingPresence(
    ownerId: _string(m, 'ownerId'),
    actorId: _string(m, 'actorId'),
    actorDisplayName:
        _stringOrNull(m, 'actorDisplayName') ?? _stringOrNull(m, 'displayName'),
    activeAt:
        _date(m, 'activeAt') ?? _date(m, 'updatedAt') ?? _date(m, r'$updatedAt'),
  );
}

@immutable
class VisibleList {
  const VisibleList({
    required this.ownerId,
    required this.isShared,
    required this.items,
    required this.trash,
  });

  final String ownerId;
  final bool isShared;
  final List<ListItem> items;
  final List<ListItem> trash;

  factory VisibleList.fromJson(Map<String, dynamic> m) => VisibleList(
    ownerId: _string(m, 'ownerId'),
    isShared: _bool(m, 'isShared'),
    items: _itemList(m['items']),
    trash: _itemList(m['trash']),
  );
}

List<ListItem> _itemList(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => ListItem.fromJson(e.cast<String, dynamic>()))
      .toList();
}

@immutable
class BootstrapData {
  const BootstrapData({
    required this.profile,
    required this.visibleList,
    required this.categories,
    required this.units,
    required this.products,
    required this.sharing,
    this.brands = const [],
    this.stores = const [],
    this.profileNames = const {},
    this.suggestions = const [],
    this.shoppingPresence = const [],
  });

  final Profile profile;
  final VisibleList visibleList;
  final List<ShopCategory> categories;
  final List<Unit> units;
  final List<Product> products;
  final SharingStatus sharing;

  /// Universal brand/store autocomplete lists (admin-curated). Empty until the
  /// backend deploy that ships them lands.
  final List<CatalogTerm> brands;
  final List<CatalogTerm> stores;

  /// Optional userId → display name lookup (backend item 3/4). Empty until the
  /// backend includes it.
  final Map<String, String> profileNames;

  /// Compact "Buy again" suggestions embedded in bootstrap (`suggestions.items`)
  /// so the row renders on cached/offline launch. The full/refreshed list comes
  /// from `suggestItems`. Empty until the backend deploy lands.
  final List<PurchaseSuggestion> suggestions;

  /// Live shopping-presence rows for the visible owner list (Phase 3). Empty
  /// until the backend deploy lands / nobody is shopping.
  final List<ShoppingPresence> shoppingPresence;

  factory BootstrapData.fromJson(Map<String, dynamic> m) {
    final catalogs = (m['catalogs'] as Map?)?.cast<String, dynamic>() ?? {};
    return BootstrapData(
      profile: Profile.fromJson((m['profile'] as Map).cast<String, dynamic>()),
      visibleList: VisibleList.fromJson(
        (m['visibleList'] as Map).cast<String, dynamic>(),
      ),
      categories: _mapList(catalogs['categories'], ShopCategory.fromJson),
      units: _mapList(catalogs['units'], Unit.fromJson),
      products: _mapList(catalogs['products'], Product.fromJson),
      brands: _mapList(catalogs['brands'], CatalogTerm.fromJson),
      stores: _mapList(catalogs['stores'], CatalogTerm.fromJson),
      sharing: m['sharing'] is Map
          ? SharingStatus.fromJson(
              (m['sharing'] as Map).cast<String, dynamic>(),
            )
          : SharingStatus.empty,
      profileNames: _names(m['profiles']),
      suggestions: _bootstrapSuggestions(m['suggestions']),
      shoppingPresence: _mapList(
        m['shoppingPresence'],
        ShoppingPresence.fromJson,
      ),
    );
  }
}

/// Parses the compact `suggestions.items` block bootstrap embeds. Tolerant of a
/// missing key (returns empty) so older deployments degrade to no Buy-Again row.
List<PurchaseSuggestion> _bootstrapSuggestions(dynamic raw) {
  if (raw is! Map) return const [];
  final items = raw['items'];
  if (items is! List) return const [];
  return items
      .whereType<Map>()
      .map((e) => PurchaseSuggestion.fromJson(e.cast<String, dynamic>()))
      .toList();
}

Map<String, String> _names(dynamic raw) {
  if (raw is! Map) return const {};
  return raw.map((k, v) {
    final name = v is Map ? (v['displayName']?.toString() ?? '') : v.toString();
    return MapEntry(k.toString(), name);
  });
}

List<T> _mapList<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => fromJson(e.cast<String, dynamic>()))
      .toList();
}

/// A "Buy again" suggestion aggregated by the backend from finalized scratch
/// (purchase) history (`suggestItems`, and a compact top-N embedded in
/// bootstrap). Carries enough to prefill a `createItem`, plus cadence signals
/// used to surface "due" staples client-side.
@immutable
class PurchaseSuggestion {
  const PurchaseSuggestion({
    required this.productId,
    required this.productName,
    this.productNameAr,
    this.productNameEn,
    this.unitId,
    this.categoryId,
    this.brand = '',
    this.seller = '',
    this.purchaseCount = 0,
    this.lastPurchasedAt,
    this.avgIntervalDays = 0,
    this.dueScore = 0,
  });

  final String productId;
  final String productName;
  final String? productNameAr;
  final String? productNameEn;
  final String? unitId;
  final String? categoryId;
  final String brand;
  final String seller;
  final int purchaseCount;
  final DateTime? lastPurchasedAt;

  /// Estimated days between purchases (0 when unknown / too few data points).
  final double avgIntervalDays;

  /// Backend "due" score; >= 1 roughly means "you'd usually have re-bought by
  /// now". The client also derives [isDue] from the interval as a fallback.
  final double dueScore;

  /// Name in the active language, falling back to [productName].
  String label(String lang) {
    final localized = lang == 'ar' ? productNameAr : productNameEn;
    return (localized != null && localized.isNotEmpty)
        ? localized
        : productName;
  }

  /// Whether this staple is likely due for a re-buy: the backend `dueScore`
  /// crossing 1, or (fallback) the time since the last purchase reaching the
  /// estimated cadence.
  bool get isDue {
    if (dueScore >= 1) return true;
    final last = lastPurchasedAt;
    if (avgIntervalDays <= 0 || last == null) return false;
    return DateTime.now().difference(last).inHours / 24 >= avgIntervalDays;
  }

  factory PurchaseSuggestion.fromJson(Map<String, dynamic> m) =>
      PurchaseSuggestion(
        productId: _string(m, 'productId'),
        productName: _string(m, 'productName'),
        productNameAr: _stringOrNull(m, 'productNameAr'),
        productNameEn: _stringOrNull(m, 'productNameEn'),
        unitId: _stringOrNull(m, 'unitId'),
        categoryId: _stringOrNull(m, 'categoryId'),
        brand: _string(m, 'brand'),
        seller: _string(m, 'seller'),
        purchaseCount: _int(m, 'purchaseCount'),
        lastPurchasedAt: _date(m, 'lastPurchasedAt'),
        avgIntervalDays: _double(m, 'avgIntervalDays', 0),
        dueScore: _double(m, 'dueScore', 0),
      );
}

/// Kinds of list activity (`list_events.type`). [other] guards forward
/// compatibility if the backend adds a type the client doesn't know yet.
enum ActivityType {
  added,
  edited,
  scratched,
  deleted,
  restored,
  cleared,
  shareAccepted,
  shareRevoked,
  other,
}

ActivityType _activityType(String raw) => switch (raw) {
  'added' => ActivityType.added,
  'edited' => ActivityType.edited,
  'scratched' => ActivityType.scratched,
  'deleted' => ActivityType.deleted,
  'restored' => ActivityType.restored,
  'cleared' => ActivityType.cleared,
  'share_accepted' => ActivityType.shareAccepted,
  'share_revoked' => ActivityType.shareRevoked,
  _ => ActivityType.other,
};

/// One row of the activity feed (`getActivity`). Product labels are snapshots
/// taken at event time so a later catalog rename/merge doesn't rewrite history.
@immutable
class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.ownerId,
    required this.actorId,
    required this.type,
    required this.createdAt,
    this.actorDisplayName,
    this.itemId,
    this.productId,
    this.productName = '',
    this.productNameAr,
    this.productNameEn,
    this.count = 0,
    this.categoryId,
    this.clearedCount = 0,
  });

  final String id;
  final String ownerId;
  final String actorId;
  final ActivityType type;
  final DateTime? createdAt;
  final String? actorDisplayName;
  final String? itemId;
  final String? productId;
  final String productName;
  final String? productNameAr;
  final String? productNameEn;
  final double count;
  final String? categoryId;
  final int clearedCount;

  /// Product label in the active language, falling back to the snapshot name.
  String label(String lang) {
    final localized = lang == 'ar' ? productNameAr : productNameEn;
    return (localized != null && localized.isNotEmpty)
        ? localized
        : productName;
  }

  factory ActivityEvent.fromJson(Map<String, dynamic> m) => ActivityEvent(
    id: _docId(m),
    ownerId: _string(m, 'ownerId'),
    actorId: _string(m, 'actorId'),
    type: _activityType(_string(m, 'type')),
    createdAt: _date(m, 'createdAt') ?? _date(m, r'$createdAt'),
    actorDisplayName: _stringOrNull(m, 'actorDisplayName'),
    itemId: _stringOrNull(m, 'itemId'),
    productId: _stringOrNull(m, 'productId'),
    productName: _string(m, 'productName'),
    productNameAr: _stringOrNull(m, 'productNameAr'),
    productNameEn: _stringOrNull(m, 'productNameEn'),
    count: _double(m, 'count', 0),
    categoryId: _stringOrNull(m, 'categoryId'),
    clearedCount: _int(m, 'clearedCount'),
  );
}

/// A page of [ActivityEvent]s plus the cursor for the next page and an actor
/// `userId → display name` lookup for names not embedded on the events.
@immutable
class ActivityFeedPage {
  const ActivityFeedPage({
    this.events = const [],
    this.nextCursor = '',
    this.profileNames = const {},
  });

  final List<ActivityEvent> events;
  final String nextCursor;
  final Map<String, String> profileNames;

  bool get hasMore => nextCursor.isNotEmpty;

  factory ActivityFeedPage.fromJson(Map<String, dynamic> m) {
    final raw = m['events'];
    return ActivityFeedPage(
      events: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => ActivityEvent.fromJson(e.cast<String, dynamic>()))
                .toList()
          : const [],
      nextCursor: _string(m, 'nextCursor'),
      profileNames: _names(m['profiles']),
    );
  }
}

/// A product entry inside [Insights.topProducts] (snapshot-labelled).
@immutable
class InsightProduct {
  const InsightProduct({
    required this.productId,
    required this.productName,
    this.productNameAr,
    this.productNameEn,
    this.count = 0,
  });

  final String productId;
  final String productName;
  final String? productNameAr;
  final String? productNameEn;
  final int count;

  String label(String lang) {
    final localized = lang == 'ar' ? productNameAr : productNameEn;
    return (localized != null && localized.isNotEmpty)
        ? localized
        : productName;
  }

  factory InsightProduct.fromJson(Map<String, dynamic> m) => InsightProduct(
    productId: _string(m, 'productId'),
    productName: _string(m, 'productName'),
    productNameAr: _stringOrNull(m, 'productNameAr'),
    productNameEn: _stringOrNull(m, 'productNameEn'),
    count: _int(m, 'count'),
  );
}

/// A `categoryId → count` entry inside [Insights.byCategory].
@immutable
class InsightCategory {
  const InsightCategory({required this.categoryId, this.count = 0});

  final String categoryId;
  final int count;

  factory InsightCategory.fromJson(Map<String, dynamic> m) => InsightCategory(
    categoryId: _string(m, 'categoryId'),
    count: _int(m, 'count'),
  );
}

/// Aggregated buying stats over finalized scratch history (`getInsights`).
@immutable
class Insights {
  const Insights({
    this.rangeDays = 0,
    this.totalChecked = 0,
    this.distinctProducts = 0,
    this.topProducts = const [],
    this.byCategory = const [],
    this.byDayOfWeek = const [0, 0, 0, 0, 0, 0, 0],
  });

  final int rangeDays;
  final int totalChecked;
  final int distinctProducts;
  final List<InsightProduct> topProducts;
  final List<InsightCategory> byCategory;

  /// Counts indexed by weekday, Sunday-first (length 7).
  final List<int> byDayOfWeek;

  bool get isEmpty => totalChecked == 0;

  static const empty = Insights();

  factory Insights.fromJson(Map<String, dynamic> m) {
    final dow = m['byDayOfWeek'];
    final week = <int>[
      for (var i = 0; i < 7; i++)
        (dow is List && i < dow.length && dow[i] is num)
            ? (dow[i] as num).toInt()
            : 0,
    ];
    return Insights(
      rangeDays: _int(m, 'rangeDays'),
      totalChecked: _int(m, 'totalChecked'),
      distinctProducts: _int(m, 'distinctProducts'),
      topProducts: _mapList(m['topProducts'], InsightProduct.fromJson),
      byCategory: _mapList(m['byCategory'], InsightCategory.fromJson),
      byDayOfWeek: week,
    );
  }
}

/// Add/edit form payload sent to the repository.
@immutable
class ItemFormData {
  const ItemFormData({
    required this.productName,
    this.count = 1,
    this.unitId,
    this.brand = '',
    this.seller = '',
    this.categoryId,
    this.imageFileId,
    this.important = false,
    this.note = '',
  });

  final String productName;
  final double count;
  final String? unitId;
  final String brand;
  final String seller;
  final String? categoryId;
  final String? imageFileId;
  final bool important;
  final String note;

  Map<String, dynamic> toPayload() => {
    'productName': productName,
    'count': count,
    'unitId': ?unitId,
    'brand': brand,
    'seller': seller,
    'categoryId': ?categoryId,
    'imageFileId': ?imageFileId,
    'important': important,
    'note': note,
  };
}
