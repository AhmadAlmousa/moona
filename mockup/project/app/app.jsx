/* Moona — root app: state, session, list logic, sharing, scratch-to-delete, tweaks */
const { useState, useRef, useEffect } = React;
const D = window.MoonaData;

function Stage({ children }) {
  const [scale, setScale] = useState(1);
  useEffect(() => {
    const fit = () => {
      const s = Math.min((window.innerHeight - 28) / 838, (window.innerWidth - 28) / 390, 1.15);
      setScale(s);
    };
    fit();
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, []);
  return (
    <div style={{ position: 'fixed', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: 'radial-gradient(circle at 50% 0%, #2f2b24, #15130f)', overflow: 'hidden' }}>
      <div style={{ transform: `scale(${scale})`, transformOrigin: 'center' }}>{children}</div>
    </div>
  );
}

const DEMO = window.__MOONA_DEMO || ''; // production

function App() {
  const [tw, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const dark = !!tw.dark;
  const density = tw.density || 'regular';

  const [, force] = useState(0);
  const commit = () => force(n => n + 1);

  const [screen, setScreen] = useState(DEMO === 'admin' ? 'admin' : DEMO ? 'main' : 'login');
  const [uid, setUid] = useState(DEMO && DEMO !== 'admin' ? 'noor' : null);
  const [lang, setLang] = useState(DEMO.includes('en') ? 'en' : 'ar');
  const [filter, setFilter] = useState('all');
  const [addOpen, setAddOpen] = useState(DEMO === 'add');
  const [editing, setEditing] = useState(DEMO === 'edit' ? D.LISTS.noor[1] : null);
  const [settingsOpen, setSettingsOpen] = useState(DEMO === 'settings');
  const [completedOpen, setCompletedOpen] = useState(DEMO === 'completed');
  const [pickerOpen, setPickerOpen] = useState(DEMO === 'contacts');
  const [permOpen, setPermOpen] = useState(DEMO === 'perm');
  const [contactsGranted, setContactsGranted] = useState(DEMO === 'contacts');
  const [scratched, setScratched] = useState({});
  const [toastObj, setToastObj] = useState(null);

  const timers = useRef({});
  const toastTimer = useRef(null);
  const t = window.MoonaStrings[lang];
  const dir = lang === 'ar' ? 'rtl' : 'ltr';

  useEffect(() => { if (DEMO.includes('dark')) setTweak('dark', true); }, []);

  const toast = (msg) => {
    setToastObj({ msg, key: Date.now() });
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToastObj(null), 2300);
  };

  // ── lookups ──
  const curUser = () => D.USERS.find(u => u.id === uid);
  const ownerId = () => { const u = curUser(); return u ? (u.receivingFrom || u.id) : null; };
  const rawItems = () => (D.LISTS[ownerId()] || []);
  const productName = (pid) => { const p = D.PRODUCTS.find(x => x.id === pid); return p ? p[lang] : '—'; };
  const catById = (id) => D.CATEGORIES.find(c => c.id === id);
  const unitById = (id) => D.UNITS.find(u => u.id === id);

  const searchProducts = (q) => {
    const ql = q.toLowerCase();
    return D.PRODUCTS.filter(p => p[lang].toLowerCase().includes(ql) || p.ar.includes(q) || p.en.toLowerCase().includes(ql)).slice(0, 20);
  };

  // ── auth ──
  const signIn = (phone, pass) => {
    let u = D.USERS.find(x => x.phone === phone);
    if (!u) {
      const id = 'u' + phone;
      u = { id, name: phone, phone, lang: 'ar', theme: 'light', sharedWith: null, receivingFrom: null };
      D.USERS.push(u); D.LISTS[id] = []; D.COMPLETED[id] = [];
    }
    setUid(u.id); setLang(u.lang); setTweak('dark', u.theme === 'dark');
    setScreen('main'); setFilter('all'); setScratched({});
    return 'ok';
  };
  const logout = () => {
    Object.values(timers.current).forEach(clearTimeout); timers.current = {};
    setScratched({}); setSettingsOpen(false); setUid(null); setScreen('login');
  };

  // ── preferences ──
  const toggleLang = () => { const nl = lang === 'ar' ? 'en' : 'ar'; setLang(nl); const u = curUser(); if (u) u.lang = nl; };
  const toggleTheme = () => { const nd = !dark; setTweak('dark', nd); const u = curUser(); if (u) u.theme = nd ? 'dark' : 'light'; };

  // ── items ──
  const resolveProduct = (name) => {
    const exist = D.PRODUCTS.find(p => p.ar === name || p.en.toLowerCase() === name.toLowerCase() || p[lang].toLowerCase() === name.toLowerCase());
    if (exist) return exist.id;
    const np = { id: 'p' + Date.now(), ar: name, en: name };
    D.PRODUCTS.push(np); return np.id;
  };
  const addItem = (form) => {
    const productId = resolveProduct(form.name);
    const list = D.LISTS[ownerId()];
    if (list.some(i => i.productId === productId)) { toast(t.duplicate); return; }
    list.push({ id: D.nextItemId(), productId, count: form.count, unitId: form.unitId, brand: form.brand,
      seller: form.seller, categoryId: form.categoryId, image: form.image, important: form.important, note: form.note, pending: true });
    setAddOpen(false); toast(t.itemAdded); commit();
  };
  const updateItem = (form) => {
    const it = rawItems().find(i => i.id === editing.id);
    if (it) { it.productId = resolveProduct(form.name); it.count = form.count; it.unitId = form.unitId;
      it.categoryId = form.categoryId; it.brand = form.brand; it.seller = form.seller; it.image = form.image;
      it.important = form.important; it.note = form.note; }
    setEditing(null); toast(t.itemUpdated); commit();
  };
  const deleteItem = (id) => {
    const list = D.LISTS[ownerId()]; const idx = list.findIndex(i => i.id === id);
    if (idx >= 0) list.splice(idx, 1); commit();
  };
  const completeItem = (id) => {
    const list = D.LISTS[ownerId()]; const idx = list.findIndex(i => i.id === id);
    if (idx >= 0) {
      const [it] = list.splice(idx, 1);
      it.completedAt = Date.now(); it.pending = false;
      if (!D.COMPLETED[ownerId()]) D.COMPLETED[ownerId()] = [];
      D.COMPLETED[ownerId()].push(it);
    }
    commit();
  };
  const restoreItem = (id) => {
    const arr = D.COMPLETED[ownerId()] || []; const idx = arr.findIndex(i => i.id === id);
    if (idx >= 0) {
      const [it] = arr.splice(idx, 1);
      delete it.completedAt; it.pending = true;
      D.LISTS[ownerId()].push(it);
    }
    toast(t.restore); commit();
  };
  const clearCompleted = () => { D.COMPLETED[ownerId()] = []; commit(); };

  const toggleScratch = (id) => {
    setScratched(prev => {
      const next = { ...prev };
      if (next[id]) { clearTimeout(timers.current[id]); delete timers.current[id]; delete next[id]; }
      else {
        next[id] = { key: Date.now() };
        timers.current[id] = setTimeout(() => {
          completeItem(id);
          setScratched(p => { const n = { ...p }; delete n[id]; return n; });
          delete timers.current[id];
          toast(t.completed);
        }, 5000);
      }
      return next;
    });
  };

  // ── contacts ──
  const userByPhone = (phone) => D.USERS.find(u => u.phone === phone);
  const startShare = () => { if (contactsGranted) setPickerOpen(true); else setPermOpen(true); };
  const grantContacts = () => { setContactsGranted(true); setPermOpen(false); setPickerOpen(true); };
  const shareContact = (contact) => {
    const tu = userByPhone(contact.phone);
    if (!tu) { toast(t.invited); return; }
    if (tu.id === uid) { toast(t.shareSelf); return; }
    const u2 = curUser(); u2.sharedWith = tu.id; tu.receivingFrom = uid;
    setPickerOpen(false); toast(t.shared); commit();
  };

  // ── sharing ──
  const doShare = (target) => {
    if (target === uid) return 'self';
    const tu = D.USERS.find(u => u.id === target);
    if (!tu) return 'notfound';
    const u = curUser(); u.sharedWith = target; tu.receivingFrom = uid;
    toast(t.shared); commit(); return 'ok';
  };
  const doUnlink = () => {
    const u = curUser();
    if (u.sharedWith) { const o = D.USERS.find(x => x.id === u.sharedWith); if (o) o.receivingFrom = null; u.sharedWith = null; }
    if (u.receivingFrom) { const o = D.USERS.find(x => x.id === u.receivingFrom); if (o) o.sharedWith = null; u.receivingFrom = null; setFilter('all'); }
    toast(t.unlinked); commit();
  };

  // ── admin ──
  const adminSignIn = (u, p) => { if (u === D.ADMIN.user && p === D.ADMIN.pass) { setScreen('admin'); return true; } return false; };

  // ── computed ──
  const rawList = rawItems();
  // important pinned to top, otherwise preserve insertion order
  const items = rawList.map((it, i) => ({ it, i }))
    .sort((a, b) => (b.it.important ? 1 : 0) - (a.it.important ? 1 : 0) || a.i - b.i)
    .map(x => x.it);
  const catCounts = {};
  items.forEach(i => { if (i.categoryId) catCounts[i.categoryId] = (catCounts[i.categoryId] || 0) + 1; });
  const cats = {
    allCount: items.length,
    list: D.CATEGORIES.filter(c => catCounts[c.id]).map(c => ({ ...c, count: catCounts[c.id] })),
  };
  const completedItems = (D.COMPLETED[ownerId()] || []).slice().sort((a, b) => b.completedAt - a.completedAt);
  // keep filter valid
  useEffect(() => { if (filter !== 'all' && !catCounts[filter] && screen === 'main') setFilter('all'); });

  const u = curUser();
  const isShared = !!(u && u.receivingFrom);
  const sharingWith = u && u.sharedWith;
  const ownerName = isShared ? (D.USERS.find(x => x.id === u.receivingFrom) || {}).name : '';
  const receiverName = sharingWith ? (D.USERS.find(x => x.id === u.sharedWith) || {}).name : '';

  const ctx = {
    t, lang, dir, dark, density, relTime: window.relTime,
    // data
    units: D.UNITS, cats, items, contacts: D.CONTACTS, userByPhone,
    productName, catById, unitById, searchProducts,
    // auth/pref
    signIn, logout, toggleLang, toggleTheme,
    openAdmin: () => setScreen('adminlogin'),
    backToLogin: () => setScreen('login'),
    adminSignIn, exitAdmin: () => setScreen('login'),
    data: D, commit, toast, allCats: D.CATEGORIES,
    // list
    filter, setFilter, scratched, toggleScratch,
    openAdd: () => setAddOpen(true), openEdit: (it) => setEditing(it),
    openSettings: () => setSettingsOpen(true), close: () => setSettingsOpen(false),
    // completed
    completedItems, completedCount: completedItems.length,
    openCompleted: () => setCompletedOpen(true), restoreItem, clearCompleted,
    // sharing
    user: u, isShared, sharingWith, ownerName, receiverName, doShare, doUnlink,
    startShare, shareContact,
  };

  const S = window.MoonaScreens, F = window.MoonaForms, A = window.MoonaAdmin;

  let body;
  if (screen === 'login') body = <S.LoginScreen ctx={ctx} />;
  else if (screen === 'adminlogin') body = <A.AdminLogin ctx={ctx} />;
  else if (screen === 'admin') body = <A.AdminPanel ctx={ctx} />;
  else body = <S.MainScreen ctx={ctx} />;

  const sheetOpen = addOpen || !!editing;

  return (
    <Stage>
      <PhoneFrame dark={dark} dir={dir}>
        {body}

        {/* Add / Edit */}
        {screen === 'main' && (
          <Sheet open={sheetOpen} onClose={() => { setAddOpen(false); setEditing(null); }}
            title={editing ? t.editTitle : t.addTitle}>
            {sheetOpen && (
              <F.ItemForm ctx={ctx} editing={editing}
                onSubmit={editing ? updateItem : addItem}
                onDelete={() => { deleteItem(editing.id); setEditing(null); toast(t.removed); }} />
            )}
          </Sheet>
        )}

        {/* Settings */}
        {screen === 'main' && (
          <Sheet open={settingsOpen} onClose={() => setSettingsOpen(false)} title={t.settings}>
            {settingsOpen && <F.SettingsScreen ctx={ctx} />}
          </Sheet>
        )}

        {/* Completed items */}
        {screen === 'main' && (
          <Sheet open={completedOpen} onClose={() => setCompletedOpen(false)} title={t.completedTitle}>
            {completedOpen && <F.CompletedList ctx={ctx} />}
          </Sheet>
        )}

        {/* Contact picker */}
        {screen === 'main' && (
          <Sheet open={pickerOpen} onClose={() => setPickerOpen(false)} title={t.selectContact}>
            {pickerOpen && <F.ContactPicker ctx={ctx} />}
          </Sheet>
        )}

        {/* Contacts permission */}
        {screen === 'main' && (
          <Dialog open={permOpen} onClose={() => setPermOpen(false)}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 14 }}>
              <div style={{ width: 64, height: 64, borderRadius: 20, background: 'var(--primary-c)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="person" size={32} color="var(--on-primary-c)" />
              </div>
              <h2 style={{ margin: 0, fontSize: 19, fontWeight: 900, color: 'var(--on-surf)' }}>{t.contactsPermTitle}</h2>
              <p style={{ margin: 0, fontSize: 14, color: 'var(--on-surf-var)', lineHeight: 1.5 }}>{t.contactsPermBody}</p>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, width: '100%', marginTop: 6 }}>
                <Button full onClick={grantContacts}>{t.allow}</Button>
                <Button variant="text" full onClick={() => setPermOpen(false)}>{t.dontAllow}</Button>
              </div>
            </div>
          </Dialog>
        )}

        <Toast toast={toastObj} />
      </PhoneFrame>

      <TweaksPanel>
        <TweakSection label={t === window.MoonaStrings.ar ? 'المظهر' : 'Appearance'} />
        <TweakToggle label="Dark mode" value={dark} onChange={v => { setTweak('dark', v); const cu = curUser(); if (cu) cu.theme = v ? 'dark' : 'light'; }} />
        <TweakRadio label="Card density" value={density} options={['compact', 'regular', 'comfy']} onChange={v => setTweak('density', v)} />
      </TweaksPanel>
    </Stage>
  );
}

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "dark": false,
  "density": "regular"
}/*EDITMODE-END*/;

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
