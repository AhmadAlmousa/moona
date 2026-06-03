/* Moona — UI primitives + theme-aware phone shell. Styling via CSS vars. */

function themeVars(dark) {
  return dark ? window.MoonaData.THEME.dark : window.MoonaData.THEME.light;
}

// ───────────────────────── Phone shell ─────────────────────────
function StatusBar({ dark }) {
  const c = 'var(--on-surf)';
  return (
    <div style={{
      height: 38, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 22px', flexShrink: 0, direction: 'ltr', userSelect: 'none',
    }}>
      <span style={{ fontSize: 14, fontWeight: 700, color: c, letterSpacing: 0.3 }}>9:41</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        {/* signal */}
        <svg width="17" height="12" viewBox="0 0 17 12"><g fill={dark ? '#ECE7DD' : '#1D1B18'}>
          <rect x="0" y="8" width="3" height="4" rx="1"/><rect x="4.5" y="5.5" width="3" height="6.5" rx="1"/>
          <rect x="9" y="3" width="3" height="9" rx="1"/><rect x="13.5" y="0.5" width="3" height="11.5" rx="1"/>
        </g></svg>
        {/* wifi */}
        <svg width="16" height="12" viewBox="0 0 16 12"><path d="M8 11.2l2.2-2.7a3.4 3.4 0 00-4.4 0L8 11.2zM3.4 5.6a7 7 0 019.2 0l1.5-1.8a9.4 9.4 0 00-12.2 0l1.5 1.8z" fill={dark ? '#ECE7DD' : '#1D1B18'}/></svg>
        {/* battery */}
        <svg width="26" height="13" viewBox="0 0 26 13"><rect x="0.6" y="0.6" width="21" height="11.8" rx="3" fill="none" stroke={dark ? '#ECE7DD' : '#1D1B18'} strokeOpacity="0.45"/><rect x="2.2" y="2.2" width="16" height="8.6" rx="1.6" fill={dark ? '#ECE7DD' : '#1D1B18'}/><rect x="23" y="4" width="2" height="5" rx="1" fill={dark ? '#ECE7DD' : '#1D1B18'} fillOpacity="0.45"/></svg>
      </div>
    </div>
  );
}

function PhoneFrame({ dark, dir, children }) {
  const vars = themeVars(dark);
  return (
    <div className="moona-root" dir={dir} style={{
      ...vars,
      fontFamily: "'Nunito','Cairo',system-ui,sans-serif",
      width: 390, height: 838, borderRadius: 46, padding: 5,
      background: dark ? '#000' : '#2A2620',
      boxShadow: '0 40px 90px -20px var(--shadow), 0 0 0 1px rgba(0,0,0,0.25)',
      flexShrink: 0,
    }}>
      <div style={{
        width: '100%', height: '100%', borderRadius: 41, overflow: 'hidden',
        background: 'var(--surface)', color: 'var(--on-surf)',
        display: 'flex', flexDirection: 'column', position: 'relative',
      }}>
        <StatusBar dark={dark} />
        <div style={{ flex: 1, position: 'relative', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
          {children}
        </div>
        <div style={{ height: 22, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <div style={{ width: 128, height: 4.5, borderRadius: 3, background: 'var(--on-surf)', opacity: 0.32 }} />
        </div>
      </div>
    </div>
  );
}

// ───────────────────────── Buttons ─────────────────────────
function Button({ variant = 'filled', children, onClick, icon, full, danger, disabled, style }) {
  const base = {
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
    border: 'none', cursor: disabled ? 'default' : 'pointer', borderRadius: 100,
    padding: '0 22px', height: 48, fontSize: 16, fontWeight: 800, fontFamily: 'inherit',
    width: full ? '100%' : 'auto', opacity: disabled ? 0.4 : 1, transition: 'filter .15s, background .15s',
    whiteSpace: 'nowrap', ...style,
  };
  const variants = {
    filled: { background: danger ? 'var(--error)' : 'var(--primary)', color: danger ? 'var(--on-error-c)' : 'var(--on-primary)' },
    tonal:  { background: 'var(--primary-c)', color: 'var(--on-primary-c)' },
    text:   { background: 'transparent', color: 'var(--primary)', padding: '0 14px' },
    outlined: { background: 'transparent', color: 'var(--on-surf)', boxShadow: 'inset 0 0 0 1.4px var(--outline-var)' },
  };
  return (
    <button onClick={disabled ? undefined : onClick} style={{ ...base, ...variants[variant] }}
      onMouseDown={e => e.currentTarget.style.filter = 'brightness(0.93)'}
      onMouseUp={e => e.currentTarget.style.filter = 'none'}
      onMouseLeave={e => e.currentTarget.style.filter = 'none'}>
      {icon && <Icon name={icon} size={20} />}
      {children}
    </button>
  );
}

function IconButton({ name, onClick, size = 22, badge, dim, title, color }) {
  return (
    <button onClick={onClick} title={title} style={{
      width: 42, height: 42, borderRadius: 100, border: 'none', cursor: 'pointer',
      background: 'transparent', color: color || (dim ? 'var(--on-surf-var)' : 'var(--on-surf)'),
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', position: 'relative',
      flexShrink: 0, transition: 'background .15s',
    }}
      onMouseEnter={e => e.currentTarget.style.background = 'color-mix(in srgb, var(--on-surf) 8%, transparent)'}
      onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
      <Icon name={name} size={size} />
      {badge && <span style={{ position: 'absolute', top: 7, insetInlineEnd: 7, width: 8, height: 8, borderRadius: 8, background: 'var(--primary)', boxShadow: '0 0 0 2px var(--surface)' }} />}
    </button>
  );
}

// ───────────────────────── Text field ─────────────────────────
function Field({ label, value, onChange, placeholder, type = 'text', hint, error, inputMode, autoFocus, onFocus, onBlur, trailing, dir }) {
  const [focus, setFocus] = React.useState(false);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6, width: '100%' }}>
      {label && <label style={{ fontSize: 13, fontWeight: 800, color: error ? 'var(--error)' : 'var(--on-surf-var)' }}>{label}</label>}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, borderRadius: 14, background: 'var(--field)',
        boxShadow: `inset 0 0 0 ${focus ? 2 : 1.3}px ${error ? 'var(--error)' : focus ? 'var(--primary)' : 'var(--outline-var)'}`,
        padding: '0 14px', height: 52, transition: 'box-shadow .12s',
      }}>
        <input value={value} type={type} inputMode={inputMode} placeholder={placeholder} autoFocus={autoFocus} dir={dir}
          onChange={e => onChange(e.target.value)}
          onFocus={e => { setFocus(true); onFocus && onFocus(e); }}
          onBlur={e => { setFocus(false); onBlur && onBlur(e); }}
          style={{ flex: 1, border: 'none', outline: 'none', background: 'transparent', fontSize: 16, fontWeight: 600,
            color: 'var(--on-surf)', fontFamily: 'inherit', minWidth: 0 }} />
        {trailing}
      </div>
      {hint && !error && <span style={{ fontSize: 12, color: 'var(--on-surf-var)', opacity: 0.85 }}>{hint}</span>}
      {error && <span style={{ fontSize: 12, color: 'var(--error)', fontWeight: 700 }}>{error}</span>}
    </div>
  );
}

// ───────────────────────── Bottom sheet ─────────────────────────
function Sheet({ open, onClose, children, title }) {
  const [mounted, setMounted] = React.useState(open);
  React.useEffect(() => { if (open) setMounted(true); }, [open]);
  if (!mounted) return null;
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 60, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
      <div onClick={onClose} onTransitionEnd={() => { if (!open) setMounted(false); }} style={{
        position: 'absolute', inset: 0, background: 'var(--scrim)', opacity: open ? 1 : 0, transition: 'opacity .25s',
      }} />
      <div style={{
        position: 'relative', background: 'var(--surf-low)', borderTopLeftRadius: 28, borderTopRightRadius: 28,
        boxShadow: '0 -8px 40px var(--shadow)', maxHeight: '92%', display: 'flex', flexDirection: 'column',
        transform: open ? 'translateY(0)' : 'translateY(101%)', transition: 'transform .3s cubic-bezier(.32,.72,0,1)',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 12 }}>
          <div style={{ width: 38, height: 4, borderRadius: 4, background: 'var(--outline-var)' }} />
        </div>
        {title && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 14px 0 20px' }}>
            <h2 style={{ margin: 0, fontSize: 21, fontWeight: 900, color: 'var(--on-surf)' }}>{title}</h2>
            <IconButton name="close" onClick={onClose} dim />
          </div>
        )}
        <div style={{ overflowY: 'auto', padding: '14px 20px 22px' }}>{children}</div>
      </div>
    </div>
  );
}

// ───────────────────────── Center dialog ─────────────────────────
function Dialog({ open, onClose, children }) {
  if (!open) return null;
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 70, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 28 }}>
      <div onClick={onClose} style={{ position: 'absolute', inset: 0, background: 'var(--scrim)' }} />
      <div style={{ position: 'relative', background: 'var(--surf-ch)', borderRadius: 26, padding: 24, width: '100%', boxShadow: '0 20px 50px var(--shadow)' }}>
        {children}
      </div>
    </div>
  );
}

// ───────────────────────── Toast ─────────────────────────
function Toast({ toast }) {
  if (!toast) return null;
  return (
    <div style={{
      position: 'absolute', bottom: 96, left: 16, right: 16, zIndex: 80, display: 'flex', justifyContent: 'center',
      pointerEvents: 'none',
    }}>
      <div key={toast.key} style={{
        background: 'var(--on-surf)', color: 'var(--surface)', padding: '12px 20px', borderRadius: 14,
        fontSize: 14.5, fontWeight: 800, boxShadow: '0 8px 24px var(--shadow)', maxWidth: '100%',
        animation: 'moonaToast .3s ease',
      }}>{toast.msg}</div>
    </div>
  );
}

// ───────────────────────── Switch ─────────────────────────
function Switch({ on, onChange }) {
  return (
    <button onClick={() => onChange(!on)} style={{
      width: 52, height: 32, borderRadius: 100, border: on ? 'none' : '2px solid var(--outline)',
      background: on ? 'var(--primary)' : 'var(--surf-chh)', position: 'relative', cursor: 'pointer',
      transition: 'background .2s', flexShrink: 0, padding: 0,
    }}>
      <span style={{
        position: 'absolute', top: '50%', insetInlineStart: on ? 24 : 6, transform: 'translateY(-50%)',
        width: on ? 22 : 16, height: on ? 22 : 16, borderRadius: 100,
        background: on ? 'var(--on-primary)' : 'var(--outline)', transition: 'all .2s',
      }} />
    </button>
  );
}

// Helper: section card row used in settings/admin
function Row({ children, onClick, style }) {
  return (
    <div onClick={onClick} style={{
      display: 'flex', alignItems: 'center', gap: 14, padding: '14px 16px', background: 'var(--surf-c)',
      borderRadius: 16, cursor: onClick ? 'pointer' : 'default', ...style,
    }}>{children}</div>
  );
}

Object.assign(window, { PhoneFrame, themeVars, Button, IconButton, Field, Sheet, Dialog, Toast, Switch, Row });
