const defaultCategories = [
  {
    'id': 'grocery',
    'nameAr': 'بقالة',
    'nameEn': 'Grocery',
    'emoji': '🛒',
    'sortOrder': 10,
    'active': true,
  },
  {
    'id': 'produce',
    'nameAr': 'خضار وفواكه',
    'nameEn': 'Produce',
    'emoji': '🥬',
    'sortOrder': 20,
    'active': true,
  },
  {
    'id': 'meats',
    'nameAr': 'لحوم',
    'nameEn': 'Meats',
    'emoji': '🥩',
    'sortOrder': 30,
    'active': true,
  },
  {
    'id': 'fish',
    'nameAr': 'أسماك',
    'nameEn': 'Fish',
    'emoji': '🐟',
    'sortOrder': 40,
    'active': true,
  },
  {
    'id': 'tools',
    'nameAr': 'أدوات',
    'nameEn': 'Tools',
    'emoji': '🧰',
    'sortOrder': 50,
    'active': true,
  },
];

const defaultUnits = [
  {
    'id': 'item',
    'nameAr': 'غرض',
    'nameEn': 'Item',
    'sortOrder': 0,
    'active': true
  },
  {
    'id': 'piece',
    'nameAr': 'قطعة',
    'nameEn': 'Piece',
    'sortOrder': 10,
    'active': true
  },
  {
    'id': 'kg',
    'nameAr': 'كيلو',
    'nameEn': 'Kilogram',
    'sortOrder': 20,
    'active': true
  },
  {
    'id': 'g',
    'nameAr': 'جرام',
    'nameEn': 'Gram',
    'sortOrder': 30,
    'active': true
  },
  {
    'id': 'l',
    'nameAr': 'لتر',
    'nameEn': 'Liter',
    'sortOrder': 40,
    'active': true
  },
  {
    'id': 'ml',
    'nameAr': 'مل',
    'nameEn': 'Milliliter',
    'sortOrder': 50,
    'active': true
  },
  {
    'id': 'box',
    'nameAr': 'علبة',
    'nameEn': 'Box',
    'sortOrder': 60,
    'active': true
  },
  {
    'id': 'bag',
    'nameAr': 'كيس',
    'nameEn': 'Bag',
    'sortOrder': 70,
    'active': true
  },
  {
    'id': 'bottle',
    'nameAr': 'زجاجة',
    'nameEn': 'Bottle',
    'sortOrder': 80,
    'active': true
  },
  {
    'id': 'can',
    'nameAr': 'علبة معدنية',
    'nameEn': 'Can',
    'sortOrder': 90,
    'active': true
  },
  {
    'id': 'pack',
    'nameAr': 'باكيت',
    'nameEn': 'Pack',
    'sortOrder': 100,
    'active': true
  },
  {
    'id': 'dozen',
    'nameAr': 'دزينة',
    'nameEn': 'Dozen',
    'sortOrder': 110,
    'active': true
  },
];

const _productPairs = [
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

final defaultProducts = [
  for (var index = 0; index < _productPairs.length; index += 1)
    {
      'id': 'p${index + 1}',
      'nameAr': _productPairs[index][0],
      'nameEn': _productPairs[index][1],
      'displayName': _productPairs[index][1],
      'aliases': [_productPairs[index][0], _productPairs[index][1]],
      'active': true,
    },
];
