/* Moona — Admin: login + CRUD panel for categories, units, products, users */

function AdminLogin({ ctx }) {
  const { t, adminSignIn, backToLogin } = ctx;
  const [u, setU] = React.useState('');
  const [p, setP] = React.useState('');
  const [err, setErr] = React.useState('');
  const go = () => { if (!adminSignIn(u.trim(), p)) setErr(t.adminWrong); };
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px' }}>
      <div style={{ paddingTop: 8 }}>
        <IconButton name="back" onClick={backToLogin} dim />
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 22, paddingBottom: 50 }}>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
          <div style={{ width: 80, height: 80, borderRadius: 24, background: 'var(--surf-ch)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="shield" size={40} color="var(--primary)" />
          </div>
          <h1 style={{ margin: 0, fontSize: 23, fontWeight: 900, color: 'var(--on-surf)' }}>{t.admin}</h1>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <Field label={t.adminUser} value={u} onChange={v => { setU(v); setErr(''); }} placeholder="admin" dir="ltr" autoFocus />
          <Field label={t.adminPass} value={p} onChange={v => { setP(v); setErr(''); }} type="password" placeholder="••••" dir="ltr" error={err || undefined} />
          <Button full onClick={go} style={{ marginTop: 4 }}>{t.signIn}</Button>
          <p style={{ margin: 0, fontSize: 12.5, color: 'var(--on-surf-var)', textAlign: 'center', opacity: 0.8 }}>admin / admin</p>
        </div>
      </div>
    </div>
  );
}

function AdminPanel({ ctx }) {
  const { t, lang, data, commit, toast, exitAdmin } = ctx;
  const [tab, setTab] = React.useState('categories');
  const [editor, setEditor] = React.useState(null); // {kind, item|null}
  const [confirm, setConfirm] = React.useState(null);

  const tabs = [
    { k: 'categories', l: t.categories, icon: 'tag' },
    { k: 'units', l: t.units, icon: 'list' },
    { k: 'products', l: t.products, icon: 'store' },
    { k: 'users', l: t.users, icon: 'person' },
  ];

  const addLabel = { categories: t.addCategory, units: t.addUnit, products: t.addProduct }[tab];

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '6px 12px 6px 16px' }}>
        <Icon name="shield" size={22} color="var(--primary)" />
        <h1 style={{ flex: 1, margin: 0, fontSize: 22, fontWeight: 900, color: 'var(--on-surf)' }}>{t.admin}</h1>
        <Button variant="text" icon="logout" onClick={exitAdmin}>{t.exitAdmin}</Button>
      </div>

      {/* tabs */}
      <div style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '4px 16px 12px', scrollbarWidth: 'none' }}>
        {tabs.map(tb => (
          <button key={tb.k} onClick={() => setTab(tb.k)} style={{
            display: 'inline-flex', alignItems: 'center', gap: 7, height: 40, padding: '0 15px', borderRadius: 100,
            border: 'none', cursor: 'pointer', fontFamily: 'inherit', fontSize: 14.5, fontWeight: 800, flexShrink: 0,
            background: tab === tb.k ? 'var(--primary)' : 'var(--surf-c)', color: tab === tb.k ? 'var(--on-primary)' : 'var(--on-surf)',
          }}>
            <Icon name={tb.icon} size={17} />{tb.l}
          </button>
        ))}
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '0 16px 24px', minHeight: 0 }}>
        {addLabel && (
          <Button variant="tonal" full icon="plus" onClick={() => setEditor({ kind: tab, item: null })} style={{ marginBottom: 12 }}>{addLabel}</Button>
        )}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
          {tab === 'categories' && data.CATEGORIES.map(c => (
            <AdminRow key={c.id} leading={<span style={{ fontSize: 24 }}>{c.emoji}</span>}
              title={c[lang]} sub={`${c.ar} · ${c.en}`}
              onEdit={() => setEditor({ kind: 'categories', item: c })}
              onDelete={() => setConfirm(() => () => { data.CATEGORIES.splice(data.CATEGORIES.indexOf(c), 1); commit(); })} />
          ))}
          {tab === 'units' && data.UNITS.map(u => (
            <AdminRow key={u.id} leading={<Mono>{u.id}</Mono>} title={u[lang]} sub={`${u.ar} · ${u.en}`}
              onEdit={() => setEditor({ kind: 'units', item: u })}
              onDelete={() => setConfirm(() => () => { data.UNITS.splice(data.UNITS.indexOf(u), 1); commit(); })} />
          ))}
          {tab === 'products' && data.PRODUCTS.map(p => (
            <AdminRow key={p.id} leading={<Mono>{p.id}</Mono>} title={p[lang]} sub={`${p.ar} · ${p.en}`}
              onEdit={() => setEditor({ kind: 'products', item: p })}
              onDelete={() => setConfirm(() => () => { data.PRODUCTS.splice(data.PRODUCTS.indexOf(p), 1); commit(); })} />
          ))}
          {tab === 'users' && data.USERS.map(u => {
            const count = (data.LISTS[u.id] || []).length;
            const rel = u.sharedWith ? `→ @${u.sharedWith}` : u.receivingFrom ? `← @${u.receivingFrom}` : '—';
            return (
              <AdminRow key={u.id} leading={<Avatar name={u.name} />} title={u.name}
                sub={`@${u.id} · ${count} ${t.items} · ${rel}`}
                onEdit={() => setEditor({ kind: 'users', item: u })}
                onDelete={() => setConfirm(() => () => {
                  data.USERS.forEach(o => { if (o.sharedWith === u.id) o.sharedWith = null; if (o.receivingFrom === u.id) o.receivingFrom = null; });
                  delete data.LISTS[u.id]; data.USERS.splice(data.USERS.indexOf(u), 1); commit();
                })} />
            );
          })}
        </div>
      </div>

      {/* editor sheet */}
      <Sheet open={!!editor} onClose={() => setEditor(null)} title={editorTitle(editor, t)}>
        {editor && <AdminEditor ctx={ctx} editor={editor} onDone={() => { setEditor(null); commit(); }} />}
      </Sheet>

      {/* confirm */}
      <Dialog open={!!confirm} onClose={() => setConfirm(null)}>
        <h2 style={{ margin: '0 0 18px', fontSize: 20, fontWeight: 900, color: 'var(--on-surf)' }}>{t.confirmDelete}</h2>
        <div style={{ display: 'flex', gap: 12, justifyContent: 'flex-end' }}>
          <Button variant="text" onClick={() => setConfirm(null)}>{t.cancel}</Button>
          <Button danger icon="trash" onClick={() => { confirm(); setConfirm(null); toast(t.removed); }}>{t.delete}</Button>
        </div>
      </Dialog>
    </div>
  );
}

function editorTitle(editor, t) {
  if (!editor) return '';
  const map = { categories: t.categories, units: t.units, products: t.products, users: t.users };
  return (editor.item ? t.edit : '+ ') + ' ' + map[editor.kind];
}

function AdminEditor({ ctx, editor, onDone }) {
  const { t, data, toast } = ctx;
  const { kind, item } = editor;
  const [ar, setAr] = React.useState(item ? item.ar || '' : '');
  const [en, setEn] = React.useState(item ? item.en || '' : '');
  const [emoji, setEmoji] = React.useState(item ? item.emoji || '' : '');
  const [name, setName] = React.useState(item ? item.name || '' : '');

  const save = () => {
    if (kind === 'categories') {
      if (item) { item.ar = ar; item.en = en; item.emoji = emoji || '📦'; }
      else data.CATEGORIES.push({ id: 'c' + Date.now(), ar, en, emoji: emoji || '📦' });
    } else if (kind === 'units') {
      if (item) { item.ar = ar; item.en = en; }
      else data.UNITS.push({ id: 'u' + Date.now(), ar, en });
    } else if (kind === 'products') {
      if (item) { item.ar = ar; item.en = en; }
      else data.PRODUCTS.push({ id: 'p' + Date.now(), ar, en });
    } else if (kind === 'users') {
      if (item) item.name = name;
    }
    onDone();
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {kind === 'users' ? (
        <>
          <Field label={t.nameEn} value={name} onChange={setName} />
          <Button variant="outlined" full icon="undo" onClick={() => toast(t.done)}>{t.resetPass}</Button>
        </>
      ) : (
        <>
          {kind === 'categories' && <Field label={t.emoji} value={emoji} onChange={setEmoji} placeholder="📦" />}
          <Field label={t.nameAr} value={ar} onChange={setAr} dir="rtl" />
          <Field label={t.nameEn} value={en} onChange={setEn} dir="ltr" />
        </>
      )}
      <Button full onClick={save}>{t.save}</Button>
    </div>
  );
}

function AdminRow({ leading, title, sub, onEdit, onDelete }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '10px 12px', background: 'var(--surf-c)', borderRadius: 15 }}>
      <div style={{ width: 40, display: 'flex', justifyContent: 'center', flexShrink: 0 }}>{leading}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 15.5, fontWeight: 800, color: 'var(--on-surf)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
        <div style={{ fontSize: 12.5, fontWeight: 700, color: 'var(--on-surf-var)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{sub}</div>
      </div>
      <IconButton name="edit" size={19} onClick={onEdit} dim />
      <IconButton name="trash" size={19} onClick={onDelete} color="var(--error)" />
    </div>
  );
}
function Mono({ children }) {
  return <span style={{ fontFamily: 'ui-monospace,monospace', fontSize: 12, fontWeight: 800, color: 'var(--on-surf-var)', background: 'var(--surf-chh)', padding: '3px 7px', borderRadius: 7 }}>{children}</span>;
}

window.MoonaAdmin = { AdminLogin, AdminPanel };
