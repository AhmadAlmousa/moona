/* Moona — data, theme tokens, and bilingual strings.
   Plain JS attached to window. Mutable demo state lives in MoonaData. */

// ───────────────────────── Theme tokens (Material 3, warm + green) ─────────────────────────
const THEME = {
  light: {
    '--surface': '#FFFBF6',
    '--surf-low': '#FBF5EE',
    '--surf-c': '#F4EFE7',
    '--surf-ch': '#EEE8DE',
    '--surf-chh': '#E8E2D8',
    '--on-surf': '#1D1B18',
    '--on-surf-var': '#524D45',
    '--primary': '#1F8A5B',
    '--on-primary': '#FFFFFF',
    '--primary-c': '#B7F2CE',
    '--on-primary-c': '#00210F',
    '--outline': '#857F75',
    '--outline-var': '#D6CFC3',
    '--error': '#BA1A1A',
    '--error-c': '#FFDAD6',
    '--on-error-c': '#410002',
    '--scrim': 'rgba(40,34,24,0.42)',
    '--shadow': 'rgba(60,50,30,0.16)',
    '--field': '#FFFFFF',
  },
  dark: {
    '--surface': '#14130F',
    '--surf-low': '#1C1B16',
    '--surf-c': '#211F1A',
    '--surf-ch': '#2B2924',
    '--surf-chh': '#36332E',
    '--on-surf': '#ECE7DD',
    '--on-surf-var': '#CFC8BC',
    '--primary': '#6EDDA1',
    '--on-primary': '#003820',
    '--primary-c': '#00522F',
    '--on-primary-c': '#8BFABB',
    '--outline': '#9A9286',
    '--outline-var': '#4C4740',
    '--error': '#FFB4AB',
    '--error-c': '#93000A',
    '--on-error-c': '#FFDAD6',
    '--scrim': 'rgba(0,0,0,0.55)',
    '--shadow': 'rgba(0,0,0,0.5)',
    '--field': '#211F1A',
  },
};

// ───────────────────────── Categories ─────────────────────────
const CATEGORIES = [
  { id: 'grocery', ar: 'بقالة',        en: 'Grocery', emoji: '🛒' },
  { id: 'produce', ar: 'خضار وفواكه',  en: 'Produce', emoji: '🥬' },
  { id: 'meats',   ar: 'لحوم',          en: 'Meats',   emoji: '🥩' },
  { id: 'fish',    ar: 'أسماك',         en: 'Fish',    emoji: '🐟' },
  { id: 'tools',   ar: 'أدوات',         en: 'Tools',   emoji: '🧰' },
];

// ───────────────────────── Units ─────────────────────────
const UNITS = [
  { id: 'piece',  ar: 'قطعة',        en: 'Piece' },
  { id: 'kg',     ar: 'كيلو',         en: 'Kg' },
  { id: 'g',      ar: 'جرام',         en: 'Gram' },
  { id: 'l',      ar: 'لتر',          en: 'Liter' },
  { id: 'ml',     ar: 'مل',           en: 'ml' },
  { id: 'box',    ar: 'علبة',         en: 'Box' },
  { id: 'bag',    ar: 'كيس',          en: 'Bag' },
  { id: 'bottle', ar: 'زجاجة',        en: 'Bottle' },
  { id: 'can',    ar: 'علبة معدنية',  en: 'Can' },
  { id: 'pack',   ar: 'باكيت',        en: 'Pack' },
  { id: 'dozen',  ar: 'دزينة',        en: 'Dozen' },
];

// ───────────────────────── Universal products ─────────────────────────
// {ar, en} — active-language string is treated as "the name".
const PRODUCTS = [
  ['خبز','Bread'],['حليب','Milk'],['بيض','Eggs'],['أرز','Rice'],['دجاج','Chicken'],
  ['لحم بقري','Beef'],['طماطم','Tomatoes'],['خيار','Cucumber'],['بصل','Onions'],['ثوم','Garlic'],
  ['بطاطس','Potatoes'],['زيت زيتون','Olive oil'],['زبدة','Butter'],['جبنة','Cheese'],['لبن','Yogurt'],
  ['تمر','Dates'],['زعتر','Zaatar'],['حمص','Chickpeas'],['عدس','Lentils'],['طحينة','Tahini'],
  ['فول','Fava beans'],['شاي','Tea'],['قهوة','Coffee'],['سكر','Sugar'],['ملح','Salt'],
  ['فلفل أسود','Black pepper'],['كمون','Cumin'],['نعناع','Mint'],['بقدونس','Parsley'],['ليمون','Lemon'],
  ['برتقال','Oranges'],['تفاح','Apples'],['موز','Bananas'],['عنب','Grapes'],['بطيخ','Watermelon'],
  ['سلمون','Salmon'],['جمبري','Shrimp'],['خس','Lettuce'],['جزر','Carrots'],['فلفل أخضر','Green pepper'],
  ['باذنجان','Eggplant'],['كوسا','Zucchini'],['مكرونة','Pasta'],['دقيق','Flour'],['عسل','Honey'],
  ['مربى','Jam'],['كاتشب','Ketchup'],['مناديل','Tissues'],['صابون','Soap'],['كزبرة','Coriander'],
].map((p, i) => ({ id: 'p' + (i + 1), ar: p[0], en: p[1] }));

function pid(en) { return PRODUCTS.find(p => p.en === en).id; }

// ───────────────────────── Demo users + seed list ─────────────────────────
const USERS = [
  { id: 'noor',  name: 'Noor',  phone: '0501112233', lang: 'ar', theme: 'light', sharedWith: 'omar', receivingFrom: null },
  { id: 'omar',  name: 'Omar',  phone: '0507654321', lang: 'ar', theme: 'dark',  sharedWith: null,   receivingFrom: 'noor' },
  { id: 'layla', name: 'Layla', phone: '0552221133', lang: 'en', theme: 'light', sharedWith: null,   receivingFrom: null },
  { id: 'sami',  name: 'Sami',  phone: '0539987766', lang: 'ar', theme: 'dark',  sharedWith: null,   receivingFrom: null },
];

// Mock device contacts (name + phone). Some map to Moona users by phone.
const CONTACTS = [
  { name: 'عمر',   phone: '0507654321' },
  { name: 'ليلى',  phone: '0552221133' },
  { name: 'سامي',  phone: '0539987766' },
  { name: 'هدى',   phone: '0561234567' },
  { name: 'خالد',  phone: '0544556677' },
  { name: 'مريم',  phone: '0509988776' },
  { name: 'يوسف',  phone: '0533219988' },
  { name: 'فاطمة', phone: '0555512345' },
];

let _iid = 100;
const nextItemId = () => 'i' + (++_iid);

// owner id -> array of pending list items
const LISTS = {
  noor: [
    { id: 'i1', productId: pid('Tomatoes'),   count: 2,   unitId: 'kg',     brand: '',         seller: 'كارفور', categoryId: 'produce', image: null, important: false, note: '', pending: true },
    { id: 'i2', productId: pid('Milk'),        count: 1,   unitId: 'bottle', brand: 'المراعي',  seller: '',       categoryId: 'grocery', image: null, important: false, note: '', pending: true },
    { id: 'i3', productId: pid('Chicken'),     count: 1.5, unitId: 'kg',     brand: 'الوطنية',  seller: '',       categoryId: 'meats',   image: null, important: true,  note: 'طازج وليس مجمّد', pending: true },
    { id: 'i4', productId: pid('Bread'),       count: 3,   unitId: 'bag',    brand: '',         seller: '',       categoryId: 'grocery', image: null, important: false, note: '', pending: true },
    { id: 'i5', productId: pid('Salmon'),      count: 1,   unitId: 'piece',  brand: '',         seller: 'سمك اليوم', categoryId: 'fish',  image: null, important: false, note: '', pending: true },
    { id: 'i6', productId: pid('Olive oil'),   count: 1,   unitId: 'bottle', brand: 'عافية',    seller: '',       categoryId: 'grocery', image: null, important: false, note: '', pending: true },
    { id: 'i7', productId: pid('Bananas'),     count: 1,   unitId: 'kg',     brand: '',         seller: '',       categoryId: 'produce', image: null, important: false, note: '', pending: true },
  ],
  omar: [],
  layla: [
    { id: 'i20', productId: pid('Coffee'),  count: 2, unitId: 'pack', brand: 'Lavazza', seller: '', categoryId: 'grocery', image: null, important: false, note: '', pending: true },
    { id: 'i21', productId: pid('Eggs'),    count: 1, unitId: 'dozen', brand: '',       seller: '', categoryId: 'grocery', image: null, important: false, note: '', pending: true },
  ],
  sami: [],
};

const MIN = 60 * 1000, HOUR = 60 * MIN, DAY = 24 * HOUR;
const now = Date.now();
// owner id -> array of completed (marked-off) items, each with completedAt timestamp
const COMPLETED = {
  noor: [
    { id: 'c1', productId: pid('Eggs'),    count: 1, unitId: 'dozen',  brand: '',        seller: '',       categoryId: 'grocery', image: null, important: false, note: '', completedAt: now - 4 * MIN },
    { id: 'c2', productId: pid('Yogurt'),  count: 4, unitId: 'piece',  brand: 'المراعي', seller: '',       categoryId: 'grocery', image: null, important: false, note: '', completedAt: now - 2 * HOUR - 12 * MIN },
    { id: 'c3', productId: pid('Apples'),  count: 1, unitId: 'kg',     brand: '',        seller: 'الدانوب', categoryId: 'produce', image: null, important: false, note: '', completedAt: now - 26 * HOUR },
    { id: 'c4', productId: pid('Salt'),    count: 1, unitId: 'pack',   brand: '',        seller: '',       categoryId: 'grocery', image: null, important: false, note: '', completedAt: now - 3 * DAY },
  ],
  omar: [], layla: [], sami: [],
};

const ADMIN = { user: 'admin', pass: 'admin' };

window.MoonaData = {
  THEME, CATEGORIES, UNITS, PRODUCTS, USERS, CONTACTS, LISTS, COMPLETED, ADMIN, nextItemId,
};
