/* Moona — Add/Edit sheet, Settings/Sharing, Admin panel */

// ════════════════════════ ADD / EDIT ════════════════════════
function ItemForm({ ctx, editing, onSubmit, onDelete }) {
  const { t, lang, dir, units, allCats, searchProducts } = ctx;
  const seed = editing || {};
  const [name, setName] = React.useState(editing ? ctx.productName(editing.productId) : '');
  const [count, setCount] = React.useState(seed.count || 1);
  const [unitId, setUnitId] = React.useState(seed.unitId || null);
  const [catId, setCatId] = React.useState(seed.categoryId || null);
  const [brand, setBrand] = React.useState(seed.brand || '');
  const [seller, setSeller] = React.useState(seed.seller || '');
  const [image, setImage] = React.useState(seed.image || null);
  const [important, setImportant] = React.useState(seed.important || false);
  const [note, setNote] = React.useState(seed.note || '');
  const [err, setErr] = React.useState('');
  const [sugg, setSugg] = React.useState([]);
  const [showSugg, setShowSugg] = React.useState(false);
  const [expanded, setExpanded] = React.useState(
    !!(editing && ((seed.count || 1) > 1 || seed.unitId || seed.brand || seed.seller || seed.note)));

  const onName = v => {
    setName(v); setErr('');
    if (v.trim().length >= 2) { setSugg(searchProducts(v.trim())); setShowSugg(true); }
    else { setSugg([]); setShowSugg(false); }
  };

  const submit = () => {
    if (!name.trim()) { setErr(t.nameRequired); return; }
    onSubmit({ name: name.trim(), count: Number(count) || 1, unitId, categoryId: catId,
      brand: brand.trim(), seller: seller.trim(), image, important, note: note.trim() });
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
      {/* product name + autocomplete */}
      <div style={{ position: 'relative' }}>
        <Field label={t.productName} value={name} onChange={onName} placeholder={t.productHint} error={err || undefined}
          autoFocus={!editing}
          onFocus={() => { if (name.trim().length >= 2) setShowSugg(true); }}
          trailing={<Icon name="search" size={20} color="var(--on-surf-var)" />} />
        {showSugg && sugg.length > 0 && (
          <div style={{ position: 'absolute', top: 80, left: 0, right: 0, zIndex: 5, background: 'var(--surf-ch)',
            borderRadius: 14, boxShadow: '0 12px 30px var(--shadow)', maxHeight: 210, overflowY: 'auto', padding: 6 }}>
            {sugg.map(p => (
              <button key={p.id} onClick={() => { setName(p[lang]); setShowSugg(false); }} style={{
                display: 'block', width: '100%', textAlign: dir === 'rtl' ? 'right' : 'left', border: 'none',
                background: 'transparent', padding: '11px 12px', borderRadius: 10, cursor: 'pointer',
                fontFamily: 'inherit', fontSize: 15.5, fontWeight: 700, color: 'var(--on-surf)' }}
                onMouseEnter={e => e.currentTarget.style.background = 'var(--surf-chh)'}
                onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                {p[lang]}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* important toggle */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 14px', borderRadius: 16,
        background: important ? 'color-mix(in srgb, var(--error) 12%, var(--field))' : 'var(--field)',
        boxShadow: `inset 0 0 0 1.3px ${important ? 'color-mix(in srgb, var(--error) 38%, transparent)' : 'var(--outline-var)'}`, transition: 'background .15s' }}>
        <div style={{ width: 38, height: 38, borderRadius: 11, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: important ? 'var(--error)' : 'var(--surf-chh)' }}>
          <Icon name="tag" size={20} color={important ? '#fff' : 'var(--on-surf-var)'} />
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 15.5, fontWeight: 900, color: 'var(--on-surf)' }}>{t.important}</div>
          <div style={{ fontSize: 12.5, fontWeight: 700, color: 'var(--on-surf-var)' }}>{t.importantDesc}</div>
        </div>
        <Switch on={important} onChange={setImportant} />
      </div>

      {/* collapsible: more details */}
      <div style={{ borderTop: '1.3px solid var(--outline-var)', paddingTop: 14 }}>
        <button onClick={() => setExpanded(e => !e)} style={{ display: 'flex', alignItems: 'center', gap: 9, width: '100%',
          border: 'none', background: 'transparent', cursor: 'pointer', fontFamily: 'inherit', padding: '2px 0',
          color: 'var(--on-surf)', fontSize: 15.5, fontWeight: 900 }}>
          <Icon name="chevron" size={18} color="var(--on-surf-var)"
            style={{ transition: 'transform .2s', transform: expanded ? 'rotate(90deg)' : (dir === 'rtl' ? 'rotate(180deg)' : 'rotate(0deg)') }} />
          {t.moreDetails}
        </button>
        {expanded && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 18, marginTop: 16 }}>
            {/* count stepper + unit */}
            <div style={{ display: 'flex', gap: 14 }}>
              <div style={{ flex: '0 0 auto' }}>
                <label style={{ fontSize: 13, fontWeight: 800, color: 'var(--on-surf-var)', display: 'block', marginBottom: 6 }}>{t.count}</label>
                <div style={{ display: 'flex', alignItems: 'center', gap: 4, background: 'var(--field)', borderRadius: 14,
                  boxShadow: 'inset 0 0 0 1.3px var(--outline-var)', height: 52, padding: '0 6px' }}>
                  <IconButton name="close" size={16} onClick={() => setCount(c => Math.max(1, +(Number(c) - (Number(c) > 1 && Number(c) <= 2 ? 0.5 : 1)).toFixed(2)))} dim />
                  <span style={{ minWidth: 42, textAlign: 'center', fontSize: 17, fontWeight: 900, color: 'var(--on-surf)' }}>{count}</span>
                  <IconButton name="plus" size={18} onClick={() => setCount(c => +(Number(c) + (Number(c) < 2 ? 0.5 : 1)).toFixed(2))} />
                </div>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <label style={{ fontSize: 13, fontWeight: 800, color: 'var(--on-surf-var)', display: 'block', marginBottom: 6 }}>{t.unit}</label>
                <div style={{ display: 'flex', gap: 7, overflowX: 'auto', paddingBottom: 4, scrollbarWidth: 'none', height: 52, alignItems: 'center' }}>
                  <ChipToggle label={t.none} sel={!unitId} onClick={() => setUnitId(null)} />
                  {units.map(u => <ChipToggle key={u.id} label={u[lang]} sel={unitId === u.id} onClick={() => setUnitId(u.id)} />)}
                </div>
              </div>
            </div>

            {/* brand + store */}
            <div style={{ display: 'flex', gap: 12 }}>
              <Field label={t.brand} value={brand} onChange={setBrand} placeholder={t.brandHint} />
              <Field label={t.seller} value={seller} onChange={setSeller} placeholder={t.sellerHint} />
            </div>

            {/* note */}
            <div>
              <label style={{ fontSize: 13, fontWeight: 800, color: 'var(--on-surf-var)', display: 'block', marginBottom: 6 }}>{t.note}</label>
              <textarea value={note} onChange={e => setNote(e.target.value)} placeholder={t.noteHint} rows={3}
                style={{ width: '100%', resize: 'none', border: 'none', outline: 'none', background: 'var(--field)', borderRadius: 14,
                  boxShadow: 'inset 0 0 0 1.3px var(--outline-var)', padding: '12px 14px', fontFamily: 'inherit', fontSize: 15.5,
                  fontWeight: 600, color: 'var(--on-surf)', boxSizing: 'border-box', lineHeight: 1.5 }} />
            </div>
          </div>
        )}
      </div>

      {/* actions */}
      <div style={{ display: 'flex', gap: 12, marginTop: 4 }}>
        {editing && <Button variant="outlined" danger icon="trash" onClick={onDelete} style={{ flex: '0 0 auto', boxShadow: 'inset 0 0 0 1.4px var(--error)', color: 'var(--error)' }} />}
        <Button full onClick={submit}>{editing ? t.save : t.addItem}</Button>
      </div>
    </div>
  );
}
const photoBtn = {
  flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 7,
  height: 78, borderRadius: 16, border: '1.5px dashed var(--outline-var)', background: 'var(--field)',
  cursor: 'pointer', fontFamily: 'inherit', fontSize: 13.5, fontWeight: 800, color: 'var(--on-surf)',
};
function ChipToggle({ label, sel, onClick }) {
  return (
    <button onClick={onClick} style={{
      height: 40, padding: '0 14px', borderRadius: 12, flexShrink: 0, cursor: 'pointer', fontFamily: 'inherit',
      border: sel ? 'none' : '1.4px solid var(--outline-var)', background: sel ? 'var(--primary)' : 'transparent',
      color: sel ? 'var(--on-primary)' : 'var(--on-surf)', fontSize: 14, fontWeight: 800, whiteSpace: 'nowrap',
    }}>{label}</button>
  );
}

// ════════════════════════ SETTINGS / SHARING ════════════════════════
function SettingsScreen({ ctx }) {
  const { t, lang, dark, dir, user, isShared, sharingWith, ownerName, receiverName,
    toggleLang, toggleTheme, startShare, doUnlink, logout } = ctx;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 22 }}>
      {/* account */}
      <Section title={t.account}>
        <Row>
          <Avatar name={user.name} />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 16.5, fontWeight: 900, color: 'var(--on-surf)' }}>{user.name}</div>
            <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--on-surf-var)' }}>@{user.id}</div>
          </div>
        </Row>
      </Section>

      {/* preferences */}
      <Section title={t.settings}>
        <Row>
          <Icon name="globe" size={22} color="var(--on-surf-var)" />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 15.5, fontWeight: 800, color: 'var(--on-surf)' }}>{t.language}</div>
          </div>
          <Seg options={[{ k: 'ar', l: t.arabic }, { k: 'en', l: t.english }]} value={lang} onChange={k => { if (k !== lang) toggleLang(); }} />
        </Row>
        <Row>
          <Icon name={dark ? 'moon' : 'sun'} size={22} color="var(--on-surf-var)" />
          <div style={{ flex: 1, fontSize: 15.5, fontWeight: 800, color: 'var(--on-surf)' }}>{t.theme}</div>
          <Seg options={[{ k: 'light', l: t.light }, { k: 'dark', l: t.dark }]} value={dark ? 'dark' : 'light'} onChange={k => { if ((k === 'dark') !== dark) toggleTheme(); }} />
        </Row>
      </Section>

      {/* sharing */}
      <Section title={t.sharing}>
        {isShared ? (
          <Row style={{ flexDirection: 'column', alignItems: 'stretch', gap: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <Avatar name={ownerName} tint />
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--on-surf-var)' }}>{t.receivingFrom}</div>
                <div style={{ fontSize: 16, fontWeight: 900, color: 'var(--on-surf)' }}>{ownerName}</div>
              </div>
            </div>
            <Button variant="outlined" full icon="close" onClick={doUnlink}>{t.unlink}</Button>
          </Row>
        ) : sharingWith ? (
          <Row style={{ flexDirection: 'column', alignItems: 'stretch', gap: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <Avatar name={receiverName} tint />
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--on-surf-var)' }}>{t.sharingWith}</div>
                <div style={{ fontSize: 16, fontWeight: 900, color: 'var(--on-surf)' }}>{receiverName}</div>
              </div>
              <span style={{ display: 'inline-flex', width: 9, height: 9, borderRadius: 9, background: 'var(--primary)' }} />
            </div>
            <div style={{ fontSize: 12.5, fontWeight: 700, color: 'var(--on-surf-var)' }}>{t.bothEdit}</div>
            <Button variant="outlined" full icon="close" onClick={doUnlink}>{t.unlink}</Button>
          </Row>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <p style={{ margin: 0, fontSize: 13.5, color: 'var(--on-surf-var)', lineHeight: 1.45 }}>{t.shareDesc}</p>
            <Button full icon="person" onClick={startShare}>{t.shareViaContacts}</Button>
          </div>
        )}
      </Section>

      <Button variant="outlined" full icon="logout" onClick={logout} style={{ color: 'var(--error)', boxShadow: 'inset 0 0 0 1.4px var(--error-c)' }}>{t.logout}</Button>
    </div>
  );
}

function Section({ title, children }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
      <div style={{ fontSize: 13, fontWeight: 900, color: 'var(--primary)', textTransform: 'uppercase', letterSpacing: 0.6, paddingInlineStart: 4 }}>{title}</div>
      {children}
    </div>
  );
}
function Avatar({ name, tint }) {
  return (
    <div style={{ width: 44, height: 44, borderRadius: 100, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: tint ? 'var(--primary-c)' : 'var(--primary)', color: tint ? 'var(--on-primary-c)' : 'var(--on-primary)', fontSize: 18, fontWeight: 900 }}>
      {(name || '?')[0].toUpperCase()}
    </div>
  );
}
function Seg({ options, value, onChange }) {
  return (
    <div style={{ display: 'flex', background: 'var(--surf-chh)', borderRadius: 100, padding: 3, gap: 2 }}>
      {options.map(o => (
        <button key={o.k} onClick={() => onChange(o.k)} style={{
          border: 'none', cursor: 'pointer', borderRadius: 100, padding: '7px 14px', fontFamily: 'inherit',
          fontSize: 13.5, fontWeight: 800, background: value === o.k ? 'var(--primary)' : 'transparent',
          color: value === o.k ? 'var(--on-primary)' : 'var(--on-surf-var)', transition: 'background .15s',
        }}>{o.l}</button>
      ))}
    </div>
  );
}

// ════════════════════════ COMPLETED LIST ════════════════════════
function CompletedList({ ctx }) {
  const { t, lang, completedItems, productName, catById, unitById, restoreItem, clearCompleted, relTime } = ctx;
  if (completedItems.length === 0) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 8, padding: '30px 20px 40px' }}>
        <div style={{ width: 80, height: 80, borderRadius: 24, background: 'var(--surf-c)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 4 }}>
          <Icon name="check" size={38} color="var(--on-surf-var)" />
        </div>
        <h3 style={{ margin: 0, fontSize: 18, fontWeight: 900, color: 'var(--on-surf)' }}>{t.noCompleted}</h3>
        <p style={{ margin: 0, fontSize: 14, color: 'var(--on-surf-var)' }}>{t.noCompletedSub}</p>
      </div>
    );
  }
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: -2 }}>
        <Button variant="text" icon="trash" onClick={clearCompleted} style={{ color: 'var(--error)', height: 38 }}>{t.clearAll}</Button>
      </div>
      {completedItems.map(it => {
        const cat = it.categoryId ? catById(it.categoryId) : null;
        const unit = it.unitId ? unitById(it.unitId) : null;
        const meta = [];
        if (it.count > 1 || unit) meta.push(`${it.count}${unit ? ' ' + unit[lang] : ''}`);
        if (it.brand) meta.push(it.brand);
        return (
          <div key={it.id} style={{ display: 'flex', alignItems: 'center', gap: 13, padding: 11, background: 'var(--surf-c)', borderRadius: 16 }}>
            <div style={{ width: 46, height: 46, borderRadius: 12, flexShrink: 0, background: 'var(--surf-chh)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative', opacity: 0.85 }}>
              <span style={{ fontSize: 23 }}>{cat ? cat.emoji : '🛒'}</span>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 16, fontWeight: 800, color: 'var(--on-surf)', textDecoration: 'line-through', textDecorationThickness: 2,
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', opacity: 0.85 }}>{productName(it.productId)}</div>
              <div style={{ fontSize: 12.5, fontWeight: 700, color: 'var(--on-surf-var)', marginTop: 1 }}>
                {t.completedAgo} · {relTime(it.completedAt, lang)}{meta.length ? '  ·  ' + meta.join('  ·  ') : ''}
              </div>
            </div>
            <button onClick={() => restoreItem(it.id)} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 38, padding: '0 14px',
              borderRadius: 100, border: 'none', background: 'var(--primary-c)', color: 'var(--on-primary-c)', cursor: 'pointer',
              fontFamily: 'inherit', fontSize: 13.5, fontWeight: 800, flexShrink: 0 }}>
              <Icon name="undo" size={16} />{t.restore}
            </button>
          </div>
        );
      })}
    </div>
  );
}

// ════════════════════════ CONTACT PICKER ════════════════════════
function ContactPicker({ ctx }) {
  const { t, dir, contacts, userByPhone, shareContact } = ctx;
  const [q, setQ] = React.useState('');
  const fmt = p => p.replace(/(\d{4})(\d{3})(\d{3})/, '$1 $2 $3');
  const list = contacts.filter(c => c.name.includes(q) || c.phone.includes(q));
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <Field value={q} onChange={setQ} placeholder={t.searchContacts}
        trailing={<Icon name="search" size={20} color="var(--on-surf-var)" />} />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 360, overflowY: 'auto' }}>
        {list.map((c, i) => {
          const onMoona = !!userByPhone(c.phone);
          return (
            <button key={i} onClick={() => shareContact(c)} style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '9px 10px',
              border: 'none', background: 'transparent', borderRadius: 14, cursor: 'pointer', fontFamily: 'inherit', textAlign: dir === 'rtl' ? 'right' : 'left' }}
              onMouseEnter={e => e.currentTarget.style.background = 'var(--surf-c)'}
              onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
              <Avatar name={c.name} tint={onMoona} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 16, fontWeight: 800, color: 'var(--on-surf)' }}>{c.name}</div>
                <div style={{ fontSize: 12.5, fontWeight: 700, color: 'var(--on-surf-var)', direction: 'ltr', textAlign: dir === 'rtl' ? 'right' : 'left' }}>{fmt(c.phone)}</div>
              </div>
              {onMoona ? (
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '5px 11px', borderRadius: 100,
                  background: 'var(--primary-c)', color: 'var(--on-primary-c)', fontSize: 12, fontWeight: 900, flexShrink: 0 }}>
                  <span style={{ width: 7, height: 7, borderRadius: 7, background: 'var(--primary)' }} />{t.onMoona}
                </span>
              ) : (
                <span style={{ padding: '6px 13px', borderRadius: 100, boxShadow: 'inset 0 0 0 1.3px var(--outline-var)',
                  color: 'var(--on-surf-var)', fontSize: 12.5, fontWeight: 800, flexShrink: 0 }}>{t.invite}</span>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}

window.MoonaForms = { ItemForm, SettingsScreen, Section, Avatar, Seg, ChipToggle, CompletedList, ContactPicker };
window.Avatar = Avatar; // shared with admin.jsx
