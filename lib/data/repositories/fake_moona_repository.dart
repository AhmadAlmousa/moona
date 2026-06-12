import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../../core/config.dart';
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

  // Mutable (non-const list, const elements) so the admin screens can edit the
  // catalog offline; the live repo persists through the backend instead.
  final List<ShopCategory> _categories = [
    const ShopCategory(
      id: 'grocery',
      nameAr: 'بقالة',
      nameEn: 'Grocery',
      emoji: '🛒',
    ),
    const ShopCategory(
      id: 'produce',
      nameAr: 'خضار وفواكه',
      nameEn: 'Produce',
      emoji: '🥬',
    ),
    const ShopCategory(id: 'meats', nameAr: 'لحوم', nameEn: 'Meats', emoji: '🥩'),
    const ShopCategory(id: 'fish', nameAr: 'أسماك', nameEn: 'Fish', emoji: '🐟'),
    const ShopCategory(id: 'tools', nameAr: 'أدوات', nameEn: 'Tools', emoji: '🧰'),
  ];

  final List<Unit> _units = [
    const Unit(id: 'piece', nameAr: 'قطعة', nameEn: 'Piece'),
    const Unit(id: 'kg', nameAr: 'كيلو', nameEn: 'Kg'),
    const Unit(id: 'g', nameAr: 'جرام', nameEn: 'Gram'),
    const Unit(id: 'l', nameAr: 'لتر', nameEn: 'Liter'),
    const Unit(id: 'ml', nameAr: 'مل', nameEn: 'ml'),
    const Unit(id: 'box', nameAr: 'علبة', nameEn: 'Box'),
    const Unit(id: 'bag', nameAr: 'كيس', nameEn: 'Bag'),
    const Unit(id: 'bottle', nameAr: 'زجاجة', nameEn: 'Bottle'),
    const Unit(id: 'can', nameAr: 'علبة معدنية', nameEn: 'Can'),
    const Unit(id: 'pack', nameAr: 'باكيت', nameEn: 'Pack'),
    const Unit(id: 'dozen', nameAr: 'دزينة', nameEn: 'Dozen'),
  ];

  // Universal brand/store autocomplete terms. Production starts empty; the fake
  // seeds a few so the item-form autocomplete is demonstrable offline.
  final List<CatalogTerm> _brands = [
    const CatalogTerm(id: 'b1', name: 'المراعي'),
    const CatalogTerm(id: 'b2', name: 'نادك'),
    const CatalogTerm(id: 'b3', name: 'الوطنية'),
    const CatalogTerm(id: 'b4', name: 'Nestlé'),
  ];
  final List<CatalogTerm> _stores = [
    const CatalogTerm(id: 's1', name: 'كارفور'),
    const CatalogTerm(id: 's2', name: 'بنده'),
    const CatalogTerm(id: 's3', name: 'الدانوب'),
    const CatalogTerm(id: 's4', name: 'لولو'),
  ];

  final List<Product> _products = [];
  final Map<String, _FakeUser> _users = {};
  final Map<String, List<ListItem>> _active = {};
  final Map<String, List<ListItem>> _trash = {};
  final List<Share> _shares = [];
  final Map<String, List<UserList>> _userLists = {};
  final List<BarcodeSubmission> _barcodeSubmissions = [];

  String? _currentUserId;
  int _itemSeq = 100;
  int _shareSeq = 0;
  int _listSeq = 0;
  int _barcodeSeq = 0;

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
    _users['noor']!.isAdmin = true; // Demo admin for the offline build.

    for (final id in _users.keys) {
      _active[id] = [];
      _trash[id] = [];
      _userLists[id] = [
        UserList(
          id: 'list_${id}_default',
          ownerId: id,
          name: 'My List',
          emoji: '🛒',
          isDefault: true,
        ),
      ];
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
  Future<BootstrapData> bootstrap({String? listId}) async {
    await _delay();
    final owner = _ownerId;
    final myLists = _userLists[_me.id] ?? [];
    final activeList = listId != null
        ? myLists.where((l) => l.id == listId).firstOrNull
        : myLists.where((l) => l.isDefault).firstOrNull ?? myLists.firstOrNull;
    return BootstrapData(
      profile: _me.profile,
      visibleList: VisibleList(
        ownerId: owner,
        isShared: owner != _me.id,
        items: List.of(_active[owner] ?? const []),
        trash: List.of(_trash[owner] ?? const []),
        listId: activeList?.id,
      ),
      categories: List.of(_categories),
      units: List.of(_units),
      products: List.of(_products),
      brands: List.of(_brands),
      stores: List.of(_stores),
      sharing: _sharingStatus(),
      lists: List.of(myLists),
      profileNames: _profileNames,
      suggestions: _suggestionsFor(owner),
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
  Future<ContactLookupResult> lookupContacts(
    List<String> phones, {
    String defaultCountryCode = '966',
  }) async {
    await _delay();
    final seen = <String>{};
    final entries = <ContactLookupEntry>[];
    for (final phone in phones) {
      final String digits;
      try {
        digits = normalizePhone(phone, defaultCountryCode: defaultCountryCode)
            .digits;
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
  Future<void> scratchItem(String itemId, {int? windowSeconds}) async {
    final list = _active[_ownerId]!;
    final index = list.indexWhere((i) => i.id == itemId);
    if (index < 0) return;
    final now = DateTime.now();
    list[index] = list[index].copyWith(
      scratchedAt: now,
      scratchExpiresAt: now.add(
        Duration(seconds: windowSeconds ?? MoonaConfig.scratchWindow.inSeconds),
      ),
      scratchedByUserId: _me.id,
    );
  }

  @override
  Future<void> undoScratchItem(String itemId) async {
    final list = _active[_ownerId]!;
    final index = list.indexWhere((i) => i.id == itemId);
    if (index < 0) return;
    list[index] = list[index].copyWith(
      scratchedAt: null,
      scratchExpiresAt: null,
      scratchedByUserId: null,
    );
  }

  @override
  Future<void> finalizeScratch(String itemId, {bool force = false}) =>
      trashItem(itemId, reason: 'scratch_timer');

  @override
  Future<void> restoreTrashItem(String itemId) async {
    final owner = _ownerId;
    final trash = _trash[owner]!;
    final index = trash.indexWhere((i) => i.id == itemId);
    if (index < 0) return;
    final item = trash.removeAt(index);
    _active[owner]!.add(item.copyWith(
      status: ItemStatus.active,
      scratchedAt: null,
      scratchExpiresAt: null,
      scratchedByUserId: null,
    ));
  }

  @override
  Future<void> clearTrash({String? listId}) async {
    _trash[_ownerId]!.clear();
  }

  // --- Named lists -----------------------------------------------------------

  @override
  Future<List<UserList>> getLists() async {
    return List.of(_userLists[_me.id] ?? []);
  }

  @override
  Future<UserList> createList(String name, {String? emoji}) async {
    await _delay();
    final id = 'list_${_me.id}_${++_listSeq}';
    final list = UserList(
      id: id,
      ownerId: _me.id,
      name: name,
      emoji: emoji,
      sortOrder: (_userLists[_me.id]?.length ?? 0),
      isDefault: (_userLists[_me.id]?.isEmpty ?? true),
    );
    (_userLists[_me.id] ??= []).add(list);
    return list;
  }

  @override
  Future<UserList> updateList(
    String listId, {
    String? name,
    String? emoji,
    int? sortOrder,
  }) async {
    await _delay();
    final lists = _userLists[_me.id] ?? [];
    final i = lists.indexWhere((l) => l.id == listId);
    if (i < 0) throw const MoonaException(MoonaException.notFound);
    final old = lists[i];
    final updated = UserList(
      id: old.id,
      ownerId: old.ownerId,
      name: name ?? old.name,
      emoji: emoji ?? old.emoji,
      sortOrder: sortOrder ?? old.sortOrder,
      isDefault: old.isDefault,
    );
    lists[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteList(String listId, {String? migrateToListId}) async {
    await _delay();
    final lists = _userLists[_me.id] ?? [];
    final i = lists.indexWhere((l) => l.id == listId);
    if (i < 0) return;
    if (lists[i].isDefault) {
      throw const MoonaException(MoonaException.invalidInput);
    }
    lists.removeAt(i);
    final active = _active[_me.id] ?? [];
    final trash = _trash[_me.id] ?? [];
    if (migrateToListId != null) {
      for (var j = 0; j < active.length; j++) {
        if (active[j].listId == listId) {
          active[j] = ListItem(
            id: active[j].id,
            ownerId: active[j].ownerId,
            productId: active[j].productId,
            count: active[j].count,
            important: active[j].important,
            status: active[j].status,
            listId: migrateToListId,
            unitId: active[j].unitId,
            brand: active[j].brand,
            seller: active[j].seller,
            categoryId: active[j].categoryId,
            imageFileId: active[j].imageFileId,
            note: active[j].note,
          );
        }
      }
      for (var j = 0; j < trash.length; j++) {
        if (trash[j].listId == listId) {
          trash[j] = ListItem(
            id: trash[j].id,
            ownerId: trash[j].ownerId,
            productId: trash[j].productId,
            count: trash[j].count,
            important: trash[j].important,
            status: trash[j].status,
            listId: migrateToListId,
            unitId: trash[j].unitId,
            brand: trash[j].brand,
            seller: trash[j].seller,
            categoryId: trash[j].categoryId,
            trashedAt: trash[j].trashedAt,
            trashedByUserId: trash[j].trashedByUserId,
            trashedByDisplayName: trash[j].trashedByDisplayName,
            trashReason: trash[j].trashReason,
          );
        }
      }
    } else {
      active.removeWhere((item) => item.listId == listId);
      trash.removeWhere((item) => item.listId == listId);
    }
  }

  // --- Barcode ---------------------------------------------------------------

  @override
  Future<Product?> lookupBarcode(String barcode) async {
    await _delay();
    final normalized = barcode.trim().toUpperCase();
    final match = _products.where(
      (p) => (p.barcode?.toUpperCase() ?? '') == normalized,
    ).firstOrNull;
    if (match == null && normalized.isNotEmpty) {
      final existing = _barcodeSubmissions.where(
        (s) => s.barcode == normalized,
      ).firstOrNull;
      if (existing != null) {
        final i = _barcodeSubmissions.indexOf(existing);
        _barcodeSubmissions[i] = BarcodeSubmission(
          id: existing.id,
          barcode: existing.barcode,
          submittedByUserId: existing.submittedByUserId,
          count: existing.count + 1,
        );
      } else {
        _barcodeSubmissions.add(BarcodeSubmission(
          id: 'bs${++_barcodeSeq}',
          barcode: normalized,
          submittedByUserId: _me.id,
          count: 1,
        ));
      }
    }
    return match;
  }

  @override
  Future<List<BarcodeSubmission>> adminGetBarcodeQueue() async {
    await _delay();
    final unresolved = _barcodeSubmissions
        .where((s) => !s.isResolved)
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return unresolved;
  }

  @override
  Future<void> adminResolveBarcode(String submissionId, String productId) async {
    await _delay();
    final i = _barcodeSubmissions.indexWhere((s) => s.id == submissionId);
    if (i < 0) return;
    final sub = _barcodeSubmissions[i];
    _barcodeSubmissions[i] = BarcodeSubmission(
      id: sub.id,
      barcode: sub.barcode,
      submittedByUserId: sub.submittedByUserId,
      count: sub.count,
      resolvedProductId: productId,
    );
    // Set barcode on the product.
    final pi = _products.indexWhere((p) => p.id == productId);
    if (pi >= 0) {
      final p = _products[pi];
      _products[pi] = Product(
        id: p.id,
        displayName: p.displayName,
        nameAr: p.nameAr,
        nameEn: p.nameEn,
        barcode: sub.barcode,
        defaultUnitId: p.defaultUnitId,
        defaultBrand: p.defaultBrand,
      );
    }
  }

  @override
  Future<ShareRequestResult> requestShare(String phone, {String? listId}) async {
    await _delay();
    final digits = normalizePhone(phone).digits;
    final target = _users.values.where((u) => u.phone == digits).firstOrNull;
    if (target == null) {
      return const ShareRequestResult(targetExists: false);
    }
    if (target.id == _me.id) {
      throw const MoonaException(MoonaException.shareSelf);
    }
    final activeListId = listId ??
        _userLists[_me.id]?.where((l) => l.isDefault).firstOrNull?.id;
    final share = Share(
      id: 's${++_shareSeq + 1}',
      ownerId: _me.id,
      viewerId: target.id,
      status: ShareStatus.pending,
      listId: activeListId,
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

  Product? _productById(String id) =>
      _products.where((p) => p.id == id).firstOrNull;

  /// Finalized scratch history (the purchase signal) for [owner].
  List<ListItem> _scratchHistory(String owner) => (_trash[owner] ?? const [])
      .where((i) => i.trashReason == 'scratch_timer')
      .toList();

  @override
  Future<ActivityFeedPage> getActivity({int limit = 50, String? cursor}) async {
    await _delay();
    final owner = _ownerId;
    final trash = List.of(_trash[owner] ?? const <ListItem>[])
      ..sort((a, b) {
        final at = a.trashedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.trashedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    final events = <ActivityEvent>[];
    for (final item in trash.take(limit)) {
      final product = _productById(item.productId);
      events.add(
        ActivityEvent(
          id: 'ev-${item.id}',
          ownerId: owner,
          actorId: item.trashedByUserId ?? owner,
          actorDisplayName: item.trashedByDisplayName,
          type: item.trashReason == 'scratch_timer'
              ? ActivityType.scratched
              : ActivityType.deleted,
          createdAt: item.trashedAt,
          itemId: item.id,
          productId: item.productId,
          productName: product?.displayName ?? '',
          productNameAr: product?.nameAr,
          productNameEn: product?.nameEn,
          count: item.count,
          categoryId: item.categoryId,
        ),
      );
    }
    return ActivityFeedPage(events: events, profileNames: _profileNames);
  }

  @override
  Future<List<PurchaseSuggestion>> suggestItems({int limit = 20}) async {
    await _delay();
    return _suggestionsFor(_ownerId).take(limit).toList();
  }

  /// Aggregates scratch history into Buy-Again suggestions, excluding products
  /// already on the active list (mirrors the live backend's exclusion).
  List<PurchaseSuggestion> _suggestionsFor(String owner) {
    final active = {for (final i in _active[owner] ?? const []) i.productId};
    final byProduct = <String, List<ListItem>>{};
    for (final h in _scratchHistory(owner)) {
      if (active.contains(h.productId)) continue;
      byProduct.putIfAbsent(h.productId, () => []).add(h);
    }
    final suggestions = <PurchaseSuggestion>[];
    byProduct.forEach((productId, rows) {
      final product = _productById(productId);
      if (product == null) return;
      final times = rows
          .map((r) => r.trashedAt)
          .whereType<DateTime>()
          .toList()
        ..sort();
      final last = times.isEmpty ? null : times.last;
      final avgInterval = times.length >= 2
          ? times.last.difference(times.first).inHours /
                24 /
                (times.length - 1)
          : 0.0;
      final recent = rows.last;
      suggestions.add(
        PurchaseSuggestion(
          productId: productId,
          productName: product.displayName,
          productNameAr: product.nameAr,
          productNameEn: product.nameEn,
          unitId: recent.unitId,
          categoryId: recent.categoryId,
          brand: recent.brand,
          seller: recent.seller,
          purchaseCount: rows.length,
          lastPurchasedAt: last,
          avgIntervalDays: avgInterval,
        ),
      );
    });
    suggestions.sort((a, b) {
      final byCount = b.purchaseCount.compareTo(a.purchaseCount);
      if (byCount != 0) return byCount;
      final at = a.lastPurchasedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.lastPurchasedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return suggestions;
  }

  @override
  Future<Insights> getInsights({int rangeDays = 90}) async {
    await _delay();
    final history = _scratchHistory(_ownerId);
    final byProduct = <String, int>{};
    final byCategory = <String, int>{};
    final byDay = <int>[0, 0, 0, 0, 0, 0, 0];
    for (final h in history) {
      byProduct[h.productId] = (byProduct[h.productId] ?? 0) + 1;
      final cat = h.categoryId;
      if (cat != null) byCategory[cat] = (byCategory[cat] ?? 0) + 1;
      final at = h.trashedAt;
      if (at != null) byDay[at.weekday % 7]++; // DateTime: Sun==7 → index 0.
    }
    final topProducts =
        byProduct.entries.map((e) {
          final product = _productById(e.key);
          return InsightProduct(
            productId: e.key,
            productName: product?.displayName ?? '',
            productNameAr: product?.nameAr,
            productNameEn: product?.nameEn,
            count: e.value,
          );
        }).toList()..sort((a, b) => b.count.compareTo(a.count));
    final categories =
        byCategory.entries
            .map((e) => InsightCategory(categoryId: e.key, count: e.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    return Insights(
      rangeDays: rangeDays,
      totalChecked: history.length,
      distinctProducts: byProduct.length,
      topProducts: topProducts,
      byCategory: categories,
      byDayOfWeek: byDay,
    );
  }

  @override
  Future<void> setShoppingPresence({required bool active}) async {
    // Single-client simulation: no peers ever appear, so presence is a no-op.
  }

  @override
  Future<String?> registerPushTarget(String token) async => null;

  @override
  Future<void> removePushTarget() async {}

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

  // --- Admin ----------------------------------------------------------------

  List<CatalogTerm> _termsFor(String kind) =>
      kind == 'brands' ? _brands : _stores;

  @override
  Future<List<Map<String, dynamic>>> adminList(String kind) async {
    await _delay();
    switch (kind) {
      case 'categories':
        return _categories
            .map((c) => {
                  'stableId': c.id,
                  'nameAr': c.nameAr,
                  'nameEn': c.nameEn,
                  'emoji': c.emoji,
                  'active': true,
                })
            .toList();
      case 'units':
        return _units
            .map((u) => {
                  'stableId': u.id,
                  'nameAr': u.nameAr,
                  'nameEn': u.nameEn,
                  'active': true,
                })
            .toList();
      case 'products':
        return _products
            .map((p) => {
                  r'$id': p.id,
                  'displayName': p.displayName,
                  'nameAr': p.nameAr,
                  'nameEn': p.nameEn,
                  if (p.barcode != null) 'barcode': p.barcode,
                  if (p.defaultUnitId != null) 'defaultUnitId': p.defaultUnitId,
                  if (p.defaultBrand != null) 'defaultBrand': p.defaultBrand,
                  'active': true,
                })
            .toList();
      case 'users':
        return _users.values
            .map((u) => {
                  'userId': u.id,
                  'displayName': u.name,
                  'phone': '+${u.phone}',
                  'isAdmin': u.isAdmin,
                })
            .toList();
      case 'brands':
      case 'stores':
        return _termsFor(kind)
            .map((t) => {r'$id': t.id, 'name': t.name, 'active': t.active})
            .toList();
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> adminCreate(
    String kind,
    Map<String, dynamic> data,
  ) async {
    await _delay();
    final id = (data['id'] ?? 'x${DateTime.now().millisecondsSinceEpoch}')
        .toString();
    switch (kind) {
      case 'categories':
        _categories.add(ShopCategory(
          id: id,
          nameAr: (data['nameAr'] ?? '').toString(),
          nameEn: (data['nameEn'] ?? '').toString(),
          emoji: (data['emoji'] ?? '📦').toString(),
        ));
        return {'id': id};
      case 'units':
        _units.add(Unit(
          id: id,
          nameAr: (data['nameAr'] ?? '').toString(),
          nameEn: (data['nameEn'] ?? '').toString(),
        ));
        return {'id': id};
      case 'products':
        final name = (data['displayName'] ?? data['nameEn'] ?? '').toString();
        _products.add(Product(
          id: id,
          displayName: name,
          nameAr: data['nameAr']?.toString(),
          nameEn: data['nameEn']?.toString() ?? name,
          barcode: data['barcode']?.toString(),
          defaultUnitId: data['defaultUnitId']?.toString(),
          defaultBrand: data['defaultBrand']?.toString(),
        ));
        return {r'$id': id};
      case 'brands':
      case 'stores':
        final term = CatalogTerm(id: id, name: (data['name'] ?? '').toString());
        _termsFor(kind).add(term);
        return {r'$id': id, 'name': term.name, 'active': true};
    }
    throw const MoonaException(MoonaException.invalidInput);
  }

  @override
  Future<Map<String, dynamic>> adminUpdate(
    String kind,
    String id,
    Map<String, dynamic> data,
  ) async {
    await _delay();
    switch (kind) {
      case 'categories':
        final i = _categories.indexWhere((c) => c.id == id);
        if (i >= 0) {
          final c = _categories[i];
          _categories[i] = ShopCategory(
            id: id,
            nameAr: (data['nameAr'] ?? c.nameAr).toString(),
            nameEn: (data['nameEn'] ?? c.nameEn).toString(),
            emoji: (data['emoji'] ?? c.emoji).toString(),
          );
        }
      case 'units':
        final i = _units.indexWhere((u) => u.id == id);
        if (i >= 0) {
          final u = _units[i];
          _units[i] = Unit(
            id: id,
            nameAr: (data['nameAr'] ?? u.nameAr).toString(),
            nameEn: (data['nameEn'] ?? u.nameEn).toString(),
          );
        }
      case 'products':
        final i = _products.indexWhere((p) => p.id == id);
        if (i >= 0) {
          final p = _products[i];
          _products[i] = Product(
            id: id,
            displayName: (data['displayName'] ?? p.displayName).toString(),
            nameAr: data['nameAr']?.toString() ?? p.nameAr,
            nameEn: data['nameEn']?.toString() ?? p.nameEn,
            barcode: data.containsKey('barcode')
                ? data['barcode']?.toString()
                : p.barcode,
            defaultUnitId: data.containsKey('defaultUnitId')
                ? data['defaultUnitId']?.toString()
                : p.defaultUnitId,
            defaultBrand: data.containsKey('defaultBrand')
                ? data['defaultBrand']?.toString()
                : p.defaultBrand,
          );
        }
      case 'users':
        final user = _users[id];
        if (user != null) {
          if (data.containsKey('isAdmin')) user.isAdmin = data['isAdmin'] == true;
          if ((data['displayName'] ?? '').toString().trim().isNotEmpty) {
            user.name = data['displayName'].toString().trim();
          }
        }
      case 'brands':
      case 'stores':
        final list = _termsFor(kind);
        final i = list.indexWhere((t) => t.id == id);
        if (i >= 0) {
          list[i] = CatalogTerm(
            id: id,
            name: (data['name'] ?? list[i].name).toString(),
            active: data['active'] != false,
          );
        }
    }
    return {'id': id};
  }

  @override
  Future<void> adminDelete(String kind, String id) async {
    await _delay();
    switch (kind) {
      case 'categories':
        _categories.removeWhere((c) => c.id == id);
      case 'units':
        _units.removeWhere((u) => u.id == id);
      case 'products':
        _products.removeWhere((p) => p.id == id);
      case 'brands':
      case 'stores':
        _termsFor(kind).removeWhere((t) => t.id == id);
      case 'users':
        await adminResetUser(id);
        _users.remove(id);
    }
  }

  @override
  Future<Map<String, dynamic>> adminResetUser(String userId) async {
    await _delay();
    final items = (_active[userId]?.length ?? 0) + (_trash[userId]?.length ?? 0);
    _active[userId]?.clear();
    _trash[userId]?.clear();
    final lists = _userLists[userId]?.length ?? 0;
    _userLists[userId]?.clear();
    final shares = _shares
        .where((s) => s.ownerId == userId || s.viewerId == userId)
        .length;
    _shares.removeWhere((s) => s.ownerId == userId || s.viewerId == userId);
    for (final user in _users.values) {
      if (user.activeReceivedOwnerId == userId) user.activeReceivedOwnerId = null;
    }
    _users[userId]?.activeReceivedOwnerId = null;
    return {'items': items, 'events': items, 'shares': shares, 'files': 0, 'lists': lists};
  }

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
  bool isAdmin = false;

  Profile get profile => Profile(
    id: id,
    phone: phone,
    displayName: name,
    language: language,
    theme: theme,
    activeReceivedOwnerId: activeReceivedOwnerId,
    isAdmin: isAdmin,
  );
}
