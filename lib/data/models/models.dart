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
  });

  final String id;
  final String phone;
  final String displayName;
  final String language;
  final String theme;
  final String? activeReceivedOwnerId;

  bool get isDark => theme == 'dark';

  factory Profile.fromJson(Map<String, dynamic> m) => Profile(
    id: (m['userId'] ?? m[r'$id'] ?? m['id'] ?? '').toString(),
    phone: _string(m, 'phone'),
    displayName: _string(m, 'displayName'),
    language: _string(m, 'language', 'ar'),
    theme: _string(m, 'theme', 'light'),
    activeReceivedOwnerId: _stringOrNull(m, 'activeReceivedOwnerId'),
  );

  Profile copyWith({String? language, String? theme, String? displayName}) =>
      Profile(
        id: id,
        phone: phone,
        displayName: displayName ?? this.displayName,
        language: language ?? this.language,
        theme: theme ?? this.theme,
        activeReceivedOwnerId: activeReceivedOwnerId,
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
  );

  ListItem copyWith({ItemStatus? status}) => ListItem(
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
  );
}

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
    this.profileNames = const {},
  });

  final Profile profile;
  final VisibleList visibleList;
  final List<ShopCategory> categories;
  final List<Unit> units;
  final List<Product> products;
  final SharingStatus sharing;

  /// Optional userId → display name lookup (backend item 3/4). Empty until the
  /// backend includes it.
  final Map<String, String> profileNames;

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
      sharing: m['sharing'] is Map
          ? SharingStatus.fromJson(
              (m['sharing'] as Map).cast<String, dynamic>(),
            )
          : SharingStatus.empty,
      profileNames: _names(m['profiles']),
    );
  }
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
