import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../../core/util/phone.dart';
import '../models/models.dart';
import 'moona_repository.dart';

/// In-memory repository mirroring the mockup `store.js` seed data.
///
/// Lets tests or deliberate local overrides run without Appwrite Cloud. It is
/// a single-client simulation, so [realtimeChanges] is an empty stream.
class FakeMoonaRepository implements MoonaRepository {
  FakeMoonaRepository() {
    _seed();
  }

  final List<ShopCategory> _categories = const [
    ShopCategory(
      id: 'grocery',
      nameAr: 'بقالة',
      nameEn: 'Grocery',
      emoji: '🛒',
    ),
    ShopCategory(
      id: 'produce',
      nameAr: 'خضار وفواكه',
      nameEn: 'Produce',
      emoji: '🥬',
    ),
    ShopCategory(id: 'meats', nameAr: 'لحوم', nameEn: 'Meats', emoji: '🥩'),
    ShopCategory(id: 'fish', nameAr: 'أسماك', nameEn: 'Fish', emoji: '🐟'),
    ShopCategory(id: 'tools', nameAr: 'أدوات', nameEn: 'Tools', emoji: '🧰'),
  ];

  final List<Unit> _units = const [
    Unit(id: 'piece', nameAr: 'قطعة', nameEn: 'Piece'),
    Unit(id: 'kg', nameAr: 'كيلو', nameEn: 'Kg'),
    Unit(id: 'g', nameAr: 'جرام', nameEn: 'Gram'),
    Unit(id: 'l', nameAr: 'لتر', nameEn: 'Liter'),
    Unit(id: 'ml', nameAr: 'مل', nameEn: 'ml'),
    Unit(id: 'box', nameAr: 'علبة', nameEn: 'Box'),
    Unit(id: 'bag', nameAr: 'كيس', nameEn: 'Bag'),
    Unit(id: 'bottle', nameAr: 'زجاجة', nameEn: 'Bottle'),
    Unit(id: 'can', nameAr: 'علبة معدنية', nameEn: 'Can'),
    Unit(id: 'pack', nameAr: 'باكيت', nameEn: 'Pack'),
    Unit(id: 'dozen', nameAr: 'دزينة', nameEn: 'Dozen'),
  ];

  final List<Product> _products = [];
  final Map<String, _FakeUser> _users = {};
  final Map<String, List<ListItem>> _active = {};
  final Map<String, List<ListItem>> _trash = {};
  final List<Share> _shares = [];

  String? _currentUserId;
  int _itemSeq = 100;
  int _shareSeq = 0;

  static const List<List<String>> _productSeed = [
    ['خبز', 'Bread'],
    ['حليب', 'Milk'],
    ['بيض', 'Eggs'],
    ['أرز', 'Rice'],
    ['دجاج', 'Chicken'],
    ['لحم بقري', 'Beef'],
    ['طماطم', 'Tomatoes'],
    ['خيار', 'Cucumber'],
    ['بصل', 'Onions'],
    ['ثوم', 'Garlic'],
    ['بطاطس', 'Potatoes'],
    ['زيت زيتون', 'Olive oil'],
    ['زبدة', 'Butter'],
    ['جبنة', 'Cheese'],
    ['لبن', 'Yogurt'],
    ['تمر', 'Dates'],
    ['زعتر', 'Zaatar'],
    ['حمص', 'Chickpeas'],
    ['عدس', 'Lentils'],
    ['طحينة', 'Tahini'],
    ['فول', 'Fava beans'],
    ['شاي', 'Tea'],
    ['قهوة', 'Coffee'],
    ['سكر', 'Sugar'],
    ['ملح', 'Salt'],
    ['فلفل أسود', 'Black pepper'],
    ['كمون', 'Cumin'],
    ['نعناع', 'Mint'],
    ['بقدونس', 'Parsley'],
    ['ليمون', 'Lemon'],
    ['برتقال', 'Oranges'],
    ['تفاح', 'Apples'],
    ['موز', 'Bananas'],
    ['عنب', 'Grapes'],
    ['بطيخ', 'Watermelon'],
    ['سلمون', 'Salmon'],
    ['جمبري', 'Shrimp'],
    ['خس', 'Lettuce'],
    ['جزر', 'Carrots'],
    ['فلفل أخضر', 'Green pepper'],
    ['باذنجان', 'Eggplant'],
    ['كوسا', 'Zucchini'],
    ['مكرونة', 'Pasta'],
    ['دقيق', 'Flour'],
    ['عسل', 'Honey'],
    ['مربى', 'Jam'],
    ['كاتشب', 'Ketchup'],
    ['مناديل', 'Tissues'],
    ['صابون', 'Soap'],
    ['كزبرة', 'Coriander'],
  ];

  String _pid(String en) => _products.firstWhere((p) => p.nameEn == en).id;

  void _seed() {
    for (var i = 0; i < _productSeed.length; i++) {
      final p = _productSeed[i];
      _products.add(
        Product(id: 'p${i + 1}', displayName: p[1], nameAr: p[0], nameEn: p[1]),
      );
    }

    _users['noor'] = _FakeUser('noor', 'Noor', '966501112233', 'ar', 'light');
    _users['omar'] = _FakeUser('omar', 'Omar', '966507654321', 'ar', 'dark');
    _users['layla'] = _FakeUser(
      'layla',
      'Layla',
      '966552221133',
      'en',
      'light',
    );
    _users['sami'] = _FakeUser('sami', 'Sami', '966539987766', 'ar', 'dark');

    for (final id in _users.keys) {
      _active[id] = [];
      _trash[id] = [];
    }

    _active['noor'] = [
      _item('i1', 'noor', 'Tomatoes', 2, 'kg', '', 'كارفور', 'produce'),
      _item('i2', 'noor', 'Milk', 1, 'bottle', 'المراعي', '', 'grocery'),
      _item(
        'i3',
        'noor',
        'Chicken',
        1.5,
        'kg',
        'الوطنية',
        '',
        'meats',
        important: true,
        note: 'طازج وليس مجمّد',
      ),
      _item('i4', 'noor', 'Bread', 3, 'bag', '', '', 'grocery'),
      _item('i5', 'noor', 'Salmon', 1, 'piece', '', 'سمك اليوم', 'fish'),
      _item('i6', 'noor', 'Olive oil', 1, 'bottle', 'عافية', '', 'grocery'),
      _item('i7', 'noor', 'Bananas', 1, 'kg', '', '', 'produce'),
    ];
    _active['layla'] = [
      _item('i20', 'layla', 'Coffee', 2, 'pack', 'Lavazza', '', 'grocery'),
      _item('i21', 'layla', 'Eggs', 1, 'dozen', '', '', 'grocery'),
    ];

    final now = DateTime.now();
    _trash['noor'] = [
      _trashed(
        'c1',
        'noor',
        'Eggs',
        1,
        'dozen',
        '',
        'grocery',
        now.subtract(const Duration(minutes: 4)),
      ),
      _trashed(
        'c2',
        'noor',
        'Yogurt',
        4,
        'piece',
        'المراعي',
        'grocery',
        now.subtract(const Duration(hours: 2, minutes: 12)),
      ),
      _trashed(
        'c3',
        'noor',
        'Apples',
        1,
        'kg',
        '',
        'produce',
        now.subtract(const Duration(hours: 26)),
      ),
      _trashed(
        'c4',
        'noor',
        'Salt',
        1,
        'pack',
        '',
        'grocery',
        now.subtract(const Duration(days: 3)),
      ),
    ];

    // Noor shares with Omar (accepted): demonstrates both sides.
    _shares.add(
      Share(
        id: 's1',
        ownerId: 'noor',
        viewerId: 'omar',
        status: ShareStatus.accepted,
      ),
    );
    _users['omar']!.activeReceivedOwnerId = 'noor';
  }

  ListItem _item(
    String id,
    String owner,
    String productEn,
    double count,
    String? unitId,
    String brand,
    String seller,
    String categoryId, {
    bool important = false,
    String note = '',
  }) => ListItem(
    id: id,
    ownerId: owner,
    productId: _pid(productEn),
    count: count,
    unitId: unitId,
    brand: brand,
    seller: seller,
    categoryId: categoryId,
    important: important,
    note: note,
    status: ItemStatus.active,
  );

  ListItem _trashed(
    String id,
    String owner,
    String productEn,
    double count,
    String? unitId,
    String brand,
    String categoryId,
    DateTime trashedAt,
  ) => ListItem(
    id: id,
    ownerId: owner,
    productId: _pid(productEn),
    count: count,
    unitId: unitId,
    brand: brand,
    categoryId: categoryId,
    important: false,
    status: ItemStatus.trash,
    trashedAt: trashedAt,
    trashedByUserId: owner,
    trashedByDisplayName: _users[owner]?.name,
    trashReason: 'scratch_timer',
  );

  _FakeUser get _me => _users[_currentUserId]!;
  String get _ownerId => _me.activeReceivedOwnerId ?? _me.id;

  Map<String, String> get _profileNames => {
    for (final u in _users.values) u.id: u.name,
  };

  @override
  Future<Profile> signIn({
    required String phone,
    required String password,
  }) async {
    await _delay();
    final digits = normalizePhone(phone).digits;
    var user = _users.values.where((u) => u.phone == digits).firstOrNull;
    if (user == null) {
      final id = 'u$digits';
      user = _FakeUser(id, digits, digits, 'ar', 'light');
      _users[id] = user;
      _active[id] = [];
      _trash[id] = [];
    }
    _currentUserId = user.id;
    return user.profile;
  }

  @override
  Future<bool> restoreSession() async {
    return _currentUserId != null;
  }

  @override
  Future<void> signOut() async {
    _currentUserId = null;
  }

  @override
  Future<BootstrapData> bootstrap() async {
    await _delay();
    final owner = _ownerId;
    return BootstrapData(
      profile: _me.profile,
      visibleList: VisibleList(
        ownerId: owner,
        isShared: owner != _me.id,
        items: List.of(_active[owner] ?? const []),
        trash: List.of(_trash[owner] ?? const []),
      ),
      categories: _categories,
      units: _units,
      products: List.of(_products),
      sharing: _sharingStatus(),
      profileNames: _profileNames,
    );
  }

  @override
  Future<BootstrapData?> cachedBootstrap() async => null;

  @override
  Future<void> clearCache() async {}

  @override
  Future<Profile> updatePreferences({
    String? language,
    String? theme,
    String? displayName,
  }) async {
    if (language != null) _me.language = language;
    if (theme != null) _me.theme = theme;
    if (displayName != null) _me.name = displayName;
    return _me.profile;
  }

  @override
  Future<List<Product>> searchProducts(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    return _products
        .where(
          (p) =>
              p.label('en').toLowerCase().contains(q) ||
              (p.nameAr?.contains(query.trim()) ?? false),
        )
        .take(20)
        .toList();
  }

  @override
  Future<ContactLookupResult> lookupContacts(List<String> phones) async {
    await _delay();
    final seen = <String>{};
    final entries = <ContactLookupEntry>[];
    for (final phone in phones) {
      final String digits;
      try {
        digits = normalizePhone(phone).digits;
      } catch (_) {
        continue; // Invalid numbers are reported in `invalid` by the live backend.
      }
      if (!seen.add(digits)) continue;
      final user = _users.values.where((u) => u.phone == digits).firstOrNull;
      entries.add(
        ContactLookupEntry(
          phone: '+$digits',
          phoneDigits: digits,
          registered: user != null,
          userId: user?.id,
          displayName: user?.name,
          isSelf: user != null && user.id == _currentUserId,
        ),
      );
    }
    // Registered first, mirroring the live backend ordering.
    entries.sort(
      (a, b) => a.registered == b.registered ? 0 : (a.registered ? -1 : 1),
    );
    return ContactLookupResult(contacts: entries);
  }

  Product _resolveProduct(String name) {
    final trimmed = name.trim();
    final existing = _products.where(
      (p) =>
          p.nameAr == trimmed ||
          p.label('en').toLowerCase() == trimmed.toLowerCase(),
    );
    if (existing.isNotEmpty) return existing.first;
    final product = Product(
      id: 'p${DateTime.now().millisecondsSinceEpoch}',
      displayName: trimmed,
      nameAr: trimmed,
      nameEn: trimmed,
    );
    _products.add(product);
    return product;
  }

  @override
  Future<ListItem> addItem(ItemFormData form) async {
    await _delay();
    final owner = _ownerId;
    final product = _resolveProduct(form.productName);
    final list = _active[owner]!;
    if (list.any((i) => i.productId == product.id)) {
      throw const MoonaException(MoonaException.duplicateItem);
    }
    final item = ListItem(
      id: 'i${++_itemSeq}',
      ownerId: owner,
      productId: product.id,
      count: form.count,
      unitId: form.unitId,
      brand: form.brand,
      seller: form.seller,
      categoryId: form.categoryId,
      imageFileId: form.imageFileId,
      important: form.important,
      note: form.note,
      status: ItemStatus.active,
    );
    list.add(item);
    return item;
  }

  @override
  Future<ListItem> updateItem(String itemId, ItemFormData form) async {
    await _delay();
    final owner = _ownerId;
    final list = _active[owner]!;
    final index = list.indexWhere((i) => i.id == itemId);
    if (index < 0) throw const MoonaException(MoonaException.notFound);
    final product = _resolveProduct(form.productName);
    if (list.any((i) => i.productId == product.id && i.id != itemId)) {
      throw const MoonaException(MoonaException.duplicateItem);
    }
    final updated = ListItem(
      id: itemId,
      ownerId: owner,
      productId: product.id,
      count: form.count,
      unitId: form.unitId,
      brand: form.brand,
      seller: form.seller,
      categoryId: form.categoryId,
      imageFileId: form.imageFileId,
      important: form.important,
      note: form.note,
      status: ItemStatus.active,
    );
    list[index] = updated;
    return updated;
  }

  @override
  Future<void> trashItem(
    String itemId, {
    String reason = 'scratch_timer',
  }) async {
    final owner = _ownerId;
    final list = _active[owner]!;
    final index = list.indexWhere((i) => i.id == itemId);
    if (index < 0) return;
    final item = list.removeAt(index);
    _trash[owner]!.add(
      ListItem(
        id: item.id,
        ownerId: item.ownerId,
        productId: item.productId,
        count: item.count,
        unitId: item.unitId,
        brand: item.brand,
        seller: item.seller,
        categoryId: item.categoryId,
        imageFileId: item.imageFileId,
        important: item.important,
        note: item.note,
        status: ItemStatus.trash,
        trashedAt: DateTime.now(),
        trashedByUserId: _me.id,
        trashedByDisplayName: _me.name,
        trashReason: reason,
      ),
    );
  }

  @override
  Future<void> restoreTrashItem(String itemId) async {
    final owner = _ownerId;
    final trash = _trash[owner]!;
    final index = trash.indexWhere((i) => i.id == itemId);
    if (index < 0) return;
    final item = trash.removeAt(index);
    _active[owner]!.add(item.copyWith(status: ItemStatus.active));
  }

  @override
  Future<void> clearTrash() async {
    _trash[_ownerId]!.clear();
  }

  @override
  Future<ShareRequestResult> requestShare(String phone) async {
    await _delay();
    final digits = normalizePhone(phone).digits;
    final target = _users.values.where((u) => u.phone == digits).firstOrNull;
    if (target == null) {
      return const ShareRequestResult(targetExists: false);
    }
    if (target.id == _me.id) {
      throw const MoonaException(MoonaException.shareSelf);
    }
    final share = Share(
      id: 's${++_shareSeq + 1}',
      ownerId: _me.id,
      viewerId: target.id,
      status: ShareStatus.pending,
    );
    _shares.add(share);
    return ShareRequestResult(targetExists: true, share: share);
  }

  @override
  Future<void> respondShare(String shareId, {required bool accepted}) async {
    final index = _shares.indexWhere((s) => s.id == shareId);
    if (index < 0) return;
    final share = _shares[index];
    _shares[index] = Share(
      id: share.id,
      ownerId: share.ownerId,
      viewerId: share.viewerId,
      status: accepted ? ShareStatus.accepted : ShareStatus.declined,
    );
    if (accepted) _users[share.viewerId]?.activeReceivedOwnerId = share.ownerId;
  }

  @override
  Future<void> unlinkShare({
    String? shareId,
    String? viewerId,
    String? ownerId,
  }) async {
    Share? share;
    if (shareId != null) {
      share = _shares.where((s) => s.id == shareId).firstOrNull;
    } else if (viewerId != null) {
      share = _shares
          .where((s) => s.ownerId == _me.id && s.viewerId == viewerId)
          .firstOrNull;
    } else if (ownerId != null) {
      share = _shares
          .where((s) => s.ownerId == ownerId && s.viewerId == _me.id)
          .firstOrNull;
    } else {
      share = _shares
          .where(
            (s) =>
                (s.ownerId == _me.id || s.viewerId == _me.id) &&
                s.status == ShareStatus.accepted,
          )
          .firstOrNull;
    }
    if (share == null) return;
    _shares.remove(share);
    final viewer = _users[share.viewerId];
    if (viewer?.activeReceivedOwnerId == share.ownerId) {
      viewer?.activeReceivedOwnerId = null;
    }
  }

  @override
  Future<SharingStatus> getSharingStatus() async => _sharingStatus();

  SharingStatus _sharingStatus() {
    final outgoing = _shares
        .where((s) => s.ownerId == _me.id && s.status != ShareStatus.revoked)
        .map(
          (s) => s.withCounterparty(
            _users[s.viewerId]?.name,
            _users[s.viewerId]?.phone,
          ),
        )
        .toList();
    final incoming = _shares
        .where((s) => s.viewerId == _me.id && s.status != ShareStatus.revoked)
        .map(
          (s) => s.withCounterparty(
            _users[s.ownerId]?.name,
            _users[s.ownerId]?.phone,
          ),
        )
        .toList();
    return SharingStatus(
      activeReceivedOwnerId: _me.activeReceivedOwnerId ?? '',
      outgoing: outgoing,
      incoming: incoming,
    );
  }

  @override
  Future<String?> uploadImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    await _delay();
    return 'fake-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<String?> imageViewUrl({
    required String itemId,
    required String fileId,
  }) async => null;

  @override
  Stream<RealtimeChange> realtimeChanges() => const Stream.empty();

  @override
  void dispose() {}

  Future<void> _delay() =>
      Future<void>.delayed(const Duration(milliseconds: 220));
}

class _FakeUser {
  _FakeUser(this.id, this.name, this.phone, this.language, this.theme);

  final String id;
  String name;
  final String phone;
  String language;
  String theme;
  String? activeReceivedOwnerId;

  Profile get profile => Profile(
    id: id,
    phone: phone,
    displayName: name,
    language: language,
    theme: theme,
    activeReceivedOwnerId: activeReceivedOwnerId,
  );
}
