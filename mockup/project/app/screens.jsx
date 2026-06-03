/* Moona — Login, Main list, ItemCard, CategoryBar, Add/Edit sheet */

// ════════════════════════ LOGIN ════════════════════════
function LoginScreen({ ctx }) {
  const { t, dir, signIn, openAdmin } = ctx;
  const [phone, setPhone] = React.useState('');
  const [pass, setPass] = React.useState('');
  const [err, setErr] = React.useState('');

  const submit = () => {
    const digits = phone.replace(/\D/g, '');
    if (digits.length < 8) { setErr(t.enterPhone); return; }
    const res = signIn(digits, pass);
    if (res === 'wrongpass') setErr(t.wrongPass);
  };

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 26px', overflow: 'auto' }}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 26, paddingBottom: 40 }}>
        {/* brand */}
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14, marginBottom: 6 }}>
          <div style={{ width: 92, height: 92, borderRadius: 28, background: 'var(--primary)', display: 'flex',
            alignItems: 'center', justifyContent: 'center', boxShadow: '0 14px 30px -8px color-mix(in srgb, var(--primary) 60%, transparent)' }}>
            <span style={{ fontSize: 50 }}>🧺</span>
          </div>
          <div style={{ textAlign: 'center' }}>
            <div style={{ fontSize: 32, fontWeight: 900, color: 'var(--on-surf)', letterSpacing: dir === 'rtl' ? 0 : -0.5 }}>{t.appName}</div>
            <div style={{ fontSize: 15, fontWeight: 700, color: 'var(--on-surf-var)' }}>{t.tagline}</div>
          </div>
        </div>

        <div style={{ textAlign: 'center', marginBottom: 2 }}>
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 900, color: 'var(--on-surf)' }}>{t.loginTitle}</h1>
          <p style={{ margin: '6px 0 0', fontSize: 14.5, color: 'var(--on-surf-var)', lineHeight: 1.45 }}>{t.loginSub}</p>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <Field label={t.phone} value={phone} onChange={v => { setPhone(v); setErr(''); }} placeholder={t.phoneHint} type="tel" inputMode="tel" dir="ltr" autoFocus />
          <Field label={t.password} value={pass} onChange={v => { setPass(v); setErr(''); }} type="password" placeholder="••••••" dir="ltr"
            error={err || undefined} />
          <Button full onClick={submit} style={{ height: 52, marginTop: 4 }}>{t.signIn}</Button>
          <p style={{ margin: 0, fontSize: 13, color: 'var(--on-surf-var)', textAlign: 'center', opacity: 0.9 }}>{t.newAccountNote}</p>
          <p style={{ margin: '-6px 0 0', fontSize: 12, color: 'var(--on-surf-var)', textAlign: 'center', opacity: 0.7 }}>{dir === 'rtl' ? 'تجربة: 0501112233' : 'Demo: 0501112233'}</p>
        </div>
      </div>
      <div style={{ paddingBottom: 16, display: 'flex', justifyContent: 'center' }}>
        <Button variant="text" icon="shield" onClick={openAdmin} style={{ fontWeight: 800 }}>{t.adminEntry}</Button>
      </div>
    </div>
  );
}

// ════════════════════════ CATEGORY BAR ════════════════════════
function CategoryBar({ ctx, cats, active, onSelect }) {
  const { t, lang } = ctx;
  const chip = (key, label, emoji, count, sel) => (
    <button key={key} onClick={() => onSelect(key)} style={{
      display: 'inline-flex', alignItems: 'center', gap: 7, height: 38, padding: '0 15px', borderRadius: 100,
      border: sel ? 'none' : '1.4px solid var(--outline-var)', background: sel ? 'var(--primary-c)' : 'transparent',
      color: sel ? 'var(--on-primary-c)' : 'var(--on-surf)', cursor: 'pointer', fontFamily: 'inherit',
      fontSize: 14.5, fontWeight: 800, whiteSpace: 'nowrap', flexShrink: 0,
    }}>
      {emoji && <span style={{ fontSize: 16 }}>{emoji}</span>}
      <span>{label}</span>
      <span style={{ fontSize: 12.5, fontWeight: 800, opacity: 0.6 }}>{count}</span>
    </button>
  );
  return (
    <div style={{ display: 'flex', gap: 9, overflowX: 'auto', padding: '4px 18px 14px', scrollbarWidth: 'none' }}>
      {chip('all', t.allItems, '', cats.allCount, active === 'all')}
      {cats.list.map(c => chip(c.id, c[lang], c.emoji, c.count, active === c.id))}
    </div>
  );
}

// ════════════════════════ ITEM CARD ════════════════════════
function ItemCard({ ctx, item, showBadge }) {
  const { t, lang, dir, density, productName, catById, unitById, toggleScratch, scratched, openEdit } = ctx;
  const cat = item.categoryId ? catById(item.categoryId) : null;
  const unit = item.unitId ? unitById(item.unitId) : null;
  const sc = scratched[item.id];
  const imp = item.important && !sc;
  const pads = { compact: 9, regular: 12, comfy: 16 }[density];
  const thumb = { compact: 42, regular: 50, comfy: 58 }[density];

  // long-press detection
  const timer = React.useRef(null);
  const moved = React.useRef(false);
  const start = () => { moved.current = false; timer.current = setTimeout(() => { moved.current = true; openEdit(item); }, 500); };
  const end = () => { clearTimeout(timer.current); };

  const meta = [];
  if (item.count > 1 || unit) meta.push(`${item.count}${unit ? ' ' + unit[lang] : ''}`);
  if (item.brand) meta.push(item.brand);
  if (item.seller) meta.push(item.seller);

  return (
    <div
      onClick={() => { if (!moved.current) toggleScratch(item.id); }}
      onContextMenu={e => { e.preventDefault(); openEdit(item); }}
      onPointerDown={start} onPointerUp={end} onPointerLeave={end} onPointerCancel={end}
      style={{
        display: 'flex', alignItems: 'center', gap: 13, padding: pads, paddingInlineEnd: pads + 2,
        background: imp ? 'color-mix(in srgb, var(--error) 13%, var(--surf-c))' : 'var(--surf-c)',
        boxShadow: imp ? 'inset 0 0 0 1.5px color-mix(in srgb, var(--error) 30%, transparent)' : 'none',
        borderRadius: 18, cursor: 'pointer', userSelect: 'none',
        opacity: sc ? 0.55 : 1, transition: 'opacity .2s, background .2s', position: 'relative', overflow: 'hidden',
      }}>
      {/* thumbnail */}
      <div style={{ width: thumb, height: thumb, borderRadius: 13, flexShrink: 0, position: 'relative',
        background: item.image ? 'linear-gradient(135deg,#9fd9b8,#6bbf8e)' : 'var(--surf-chh)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
        {item.image
          ? <Icon name="imageIcon" size={thumb * 0.42} color="rgba(255,255,255,0.95)" />
          : <span style={{ fontSize: thumb * 0.5 }}>{cat ? cat.emoji : '🛒'}</span>}
      </div>

      {/* text */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
          {imp && <span style={{ width: 7, height: 7, borderRadius: 7, background: 'var(--error)', flexShrink: 0 }} />}
          <span style={{ fontSize: density === 'compact' ? 16 : 17, fontWeight: 800, color: 'var(--on-surf)',
            textDecoration: sc ? 'line-through' : 'none', textDecorationThickness: 2, whiteSpace: 'nowrap',
            overflow: 'hidden', textOverflow: 'ellipsis' }}>{productName(item.productId)}</span>
        </div>
        {meta.length > 0 && (
          <div style={{ fontSize: 13.5, fontWeight: 700, color: 'var(--on-surf-var)', marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {meta.join('  ·  ')}
          </div>
        )}
      </div>

      {/* trailing: undo (scratched) or category badge */}
      {sc ? (
        <button onClick={e => { e.stopPropagation(); toggleScratch(item.id); }} style={{
          display: 'inline-flex', alignItems: 'center', gap: 6, height: 36, padding: '0 14px', borderRadius: 100,
          border: 'none', background: 'var(--primary)', color: 'var(--on-primary)', fontFamily: 'inherit',
          fontSize: 14, fontWeight: 800, cursor: 'pointer', flexShrink: 0,
        }}>
          <Icon name="undo" size={17} /> {t.undo}
        </button>
      ) : showBadge && cat ? (
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '5px 11px', borderRadius: 100,
          background: 'var(--surf-chh)', color: 'var(--on-surf-var)', fontSize: 12.5, fontWeight: 800, flexShrink: 0 }}>
          <span style={{ fontSize: 13 }}>{cat.emoji}</span>{cat[lang]}
        </span>
      ) : null}

      {sc && <div className="moona-countdown" key={'cd' + (sc.key || 0)} style={{
        position: 'absolute', bottom: 0, insetInlineStart: 0, height: 3, background: 'var(--primary)',
      }} />}
    </div>
  );
}

// ════════════════════════ MAIN LIST ════════════════════════
function MainScreen({ ctx }) {
  const { t, lang, dir, dark, items, cats, filter, setFilter, openAdd, openSettings,
    toggleLang, toggleTheme, ownerName, isShared, openCompleted, completedCount } = ctx;

  const visible = filter === 'all' ? items : items.filter(i => i.categoryId === filter);
  const showBadge = filter === 'all';

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
      {/* header */}
      <div style={{ padding: '6px 10px 4px 16px', display: 'flex', alignItems: 'center', gap: 4 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <h1 style={{ margin: 0, fontSize: 27, fontWeight: 900, color: 'var(--on-surf)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {isShared ? `${ownerName} · ${t.sharedListOf}` : t.myList}
            </h1>
          </div>
          {isShared && (
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 2, color: 'var(--primary)' }}>
              <Icon name="share" size={13} color="var(--primary)" />
              <span style={{ fontSize: 12.5, fontWeight: 800 }}>{t.receivingFrom} {ownerName}</span>
            </div>
          )}
        </div>
        <IconButton name="globe" onClick={toggleLang} title={t.language} dim size={20} />
        <IconButton name="trash" onClick={openCompleted} title={t.completed} dim size={20} badge={completedCount > 0} />
        <IconButton name={dark ? 'sun' : 'moon'} onClick={toggleTheme} title={t.theme} dim size={20} />
        <IconButton name="settings" onClick={openSettings} title={t.settings} dim size={20} badge={isShared || ctx.sharingWith} />
      </div>

      <CategoryBar ctx={ctx} cats={cats} active={filter} onSelect={setFilter} />

      {/* list */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '2px 16px 120px', minHeight: 0 }}>
        {visible.length === 0 ? (
          <EmptyState ctx={ctx} filtered={filter !== 'all'} />
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {visible.map(it => <ItemCard key={it.id} ctx={ctx} item={it} showBadge={showBadge} />)}
            <div style={{ textAlign: 'center', padding: '14px 0 4px', fontSize: 12.5, fontWeight: 700, color: 'var(--on-surf-var)', opacity: 0.7 }}>
              {t.longPressHint}
            </div>
          </div>
        )}
      </div>

      {/* FAB */}
      <button onClick={openAdd} style={{
        position: 'absolute', bottom: 22, insetInlineEnd: 20, height: 60, paddingInline: 22, borderRadius: 20, border: 'none',
        background: 'var(--primary)', color: 'var(--on-primary)', display: 'inline-flex', alignItems: 'center', gap: 9,
        cursor: 'pointer', boxShadow: '0 12px 28px -6px color-mix(in srgb, var(--primary) 55%, transparent)', zIndex: 30,
        fontFamily: 'inherit', fontSize: 16.5, fontWeight: 900,
      }}>
        <Icon name="plus" size={24} /> {t.addItem}
      </button>
    </div>
  );
}

function EmptyState({ ctx, filtered }) {
  const { t, openAdd } = ctx;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '78%', textAlign: 'center', gap: 6, padding: '0 30px' }}>
      <div style={{ width: 96, height: 96, borderRadius: 30, background: 'var(--surf-c)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 8 }}>
        <span style={{ fontSize: 48, opacity: 0.9 }}>{filtered ? '🔍' : '🛒'}</span>
      </div>
      <h2 style={{ margin: 0, fontSize: 21, fontWeight: 900, color: 'var(--on-surf)' }}>{filtered ? t.emptyCatTitle : t.emptyTitle}</h2>
      <p style={{ margin: 0, fontSize: 14.5, color: 'var(--on-surf-var)', lineHeight: 1.45 }}>{filtered ? t.emptyCatSub : t.emptySub}</p>
      {!filtered && <Button icon="plus" onClick={openAdd} style={{ marginTop: 14 }}>{t.addItem}</Button>}
    </div>
  );
}

window.MoonaScreens = { LoginScreen, MainScreen, CategoryBar, ItemCard, EmptyState };
