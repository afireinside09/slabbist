'use client';

import * as React from 'react';
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { SLAB } from '@/lib/tokens';
import { Icon, type IconName } from '@/components/icon';
import { SlabLogo } from '@/components/slab-logo';

export type AuthMode = 'login' | 'signup' | 'reset';

type AuthContextValue = {
  openAuth: (mode: AuthMode) => void;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [mode, setMode] = useState<AuthMode | null>(null);

  const openAuth = useCallback((next: AuthMode) => setMode(next), []);
  const close = useCallback(() => setMode(null), []);

  const value = useMemo(() => ({ openAuth }), [openAuth]);

  return (
    <AuthContext.Provider value={value}>
      {children}
      {mode && <AuthModal initialMode={mode} onClose={close} />}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}

// ————————————————————————————————————————————————————————————
// Modal (kept in-file so the function-prop boundary stays client→client).

const inputStyle: React.CSSProperties = {
  width: '100%',
  padding: '14px 14px 14px 42px',
  background: SLAB.elev2,
  border: '1px solid ' + SLAB.hair,
  borderRadius: 12,
  color: SLAB.text,
  fontSize: 14,
  fontFamily: SLAB.sans,
  outline: 'none',
  transition: 'border-color 0.15s',
};

const linkBtn: React.CSSProperties = {
  background: 'transparent',
  border: 'none',
  color: SLAB.gold,
  fontSize: 13,
  cursor: 'pointer',
  padding: 0,
  fontWeight: 500,
};

function AuthModal({
  initialMode,
  onClose,
}: {
  initialMode: AuthMode;
  onClose: () => void;
}) {
  const [mode, setMode] = useState<AuthMode>(initialMode);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [storeName, setStoreName] = useState('');
  const [showPw, setShowPw] = useState(false);
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = React.useId();

  useEffect(() => {
    const previouslyFocused = document.activeElement as HTMLElement | null;

    const getFocusable = () => {
      if (!dialogRef.current) return [] as HTMLElement[];
      return Array.from(
        dialogRef.current.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      );
    };

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
        return;
      }
      if (e.key !== 'Tab') return;
      const focusables = getFocusable();
      if (focusables.length === 0) return;
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const activeEl = document.activeElement as HTMLElement | null;
      if (e.shiftKey && activeEl === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && activeEl === last) {
        e.preventDefault();
        first.focus();
      }
    };

    window.addEventListener('keydown', onKey);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    const focusTimer = window.setTimeout(() => {
      const focusables = getFocusable();
      focusables[0]?.focus();
    }, 0);

    return () => {
      window.removeEventListener('keydown', onKey);
      window.clearTimeout(focusTimer);
      document.body.style.overflow = prevOverflow;
      previouslyFocused?.focus?.();
    };
  }, [onClose]);

  const submit = (e: React.SyntheticEvent<HTMLFormElement>) => {
    e.preventDefault();
    setLoading(true);
    setTimeout(() => {
      setLoading(false);
      setSuccess(true);
    }, 1100);
  };

  const titles: Record<AuthMode, { t: string; s: string }> = {
    login: { t: 'Welcome back', s: 'Sign in to your Slabbist store.' },
    signup: { t: 'Create your store', s: 'Set up Slabbist in under a minute.' },
    reset: { t: 'Reset your password', s: "We'll email a reset link." },
  };
  const { t, s } = titles[mode];

  return (
    <div
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 200,
        background: 'oklch(0.05 0.002 78 / 0.7)',
        backdropFilter: 'blur(14px)',
        WebkitBackdropFilter: 'blur(14px)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 20,
        animation: 'sbmFade 0.2s ease',
      }}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        style={{
          width: '100%',
          maxWidth: 440,
          borderRadius: 24,
          background: SLAB.elev,
          border: '1px solid ' + SLAB.hairStrong,
          boxShadow: '0 60px 160px oklch(0 0 0 / 0.6)',
          animation: 'sbmRise 0.3s ease',
          position: 'relative',
          overflow: 'hidden',
        }}
      >
        <button
          onClick={onClose}
          aria-label="Close"
          style={{
            position: 'absolute',
            top: 18,
            right: 18,
            zIndex: 2,
            width: 34,
            height: 34,
            borderRadius: 999,
            background: SLAB.elev2,
            border: '1px solid ' + SLAB.hair,
            color: SLAB.muted,
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Icon name="x" size={16} />
        </button>

        <div style={{ padding: 36, position: 'relative' }}>
          {success ? (
            <SuccessView mode={mode} email={email} onClose={onClose} titleId={titleId} />
          ) : (
            <>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 28 }}>
                <SlabLogo size={32} title="Slabbist" />
              </div>

              <h2
                id={titleId}
                style={{
                  fontFamily: SLAB.serif,
                  fontSize: 30,
                  letterSpacing: -0.8,
                  margin: '0 0 8px',
                  fontWeight: 400,
                }}
              >
                {t}
              </h2>
              <p style={{ fontSize: 13, color: SLAB.muted, margin: '0 0 28px' }}>{s}</p>

              {mode !== 'reset' && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 20 }}>
                  <OAuthBtn label="Continue with Apple" icon={<AppleLogo />} />
                  <OAuthBtn label="Continue with Google" icon={<GoogleLogo />} />
                </div>
              )}

              {mode !== 'reset' && (
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 12,
                    margin: '20px 0 20px',
                  }}
                >
                  <div style={{ flex: 1, height: 1, background: SLAB.hair }} />
                  <div
                    style={{
                      fontSize: 11,
                      color: SLAB.dim,
                      letterSpacing: 1,
                      textTransform: 'uppercase',
                      fontWeight: 500,
                    }}
                  >
                    Or
                  </div>
                  <div style={{ flex: 1, height: 1, background: SLAB.hair }} />
                </div>
              )}

              <form onSubmit={submit} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
                {mode === 'signup' && (
                  <Field label="Store name" icon="store">
                    <input
                      value={storeName}
                      onChange={(e) => setStoreName(e.target.value)}
                      required
                      placeholder="Third Street Cards"
                      style={inputStyle}
                    />
                  </Field>
                )}
                <Field label="Work email" icon="mail">
                  <input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    placeholder="you@store.com"
                    style={inputStyle}
                  />
                </Field>

                {mode !== 'reset' && (
                  <Field label="Password" icon="lock">
                    <input
                      type={showPw ? 'text' : 'password'}
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      required
                      placeholder={mode === 'signup' ? 'at least 10 characters' : '••••••••'}
                      style={inputStyle}
                      minLength={mode === 'signup' ? 10 : 1}
                    />
                    <button
                      type="button"
                      onClick={() => setShowPw((v) => !v)}
                      aria-label={showPw ? 'Hide password' : 'Show password'}
                      style={{
                        position: 'absolute',
                        right: 12,
                        top: '50%',
                        transform: 'translateY(-50%)',
                        background: 'transparent',
                        border: 'none',
                        color: SLAB.muted,
                        cursor: 'pointer',
                        padding: 4,
                      }}
                    >
                      <Icon name="eye" size={15} />
                    </button>
                  </Field>
                )}

                {mode === 'login' && (
                  <div style={{ textAlign: 'right', marginTop: -4 }}>
                    <button
                      type="button"
                      onClick={() => setMode('reset')}
                      style={{
                        background: 'transparent',
                        border: 'none',
                        color: SLAB.gold,
                        fontSize: 12,
                        cursor: 'pointer',
                        padding: 0,
                      }}
                    >
                      Forgot password?
                    </button>
                  </div>
                )}

                <button
                  type="submit"
                  disabled={loading}
                  style={{
                    marginTop: 8,
                    padding: '14px 18px',
                    borderRadius: 12,
                    background: SLAB.text,
                    color: SLAB.ink,
                    border: 'none',
                    fontSize: 14,
                    fontWeight: 600,
                    cursor: loading ? 'wait' : 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: 8,
                    opacity: loading ? 0.7 : 1,
                  }}
                >
                  {loading ? (
                    <>
                      <Spinner />
                      Working…
                    </>
                  ) : mode === 'login' ? (
                    'Sign in'
                  ) : mode === 'signup' ? (
                    'Create store'
                  ) : (
                    'Send reset link'
                  )}
                </button>

                {mode === 'signup' && (
                  <div
                    style={{
                      fontSize: 11,
                      color: SLAB.dim,
                      textAlign: 'center',
                      marginTop: 4,
                      lineHeight: 1.5,
                    }}
                  >
                    By creating a store you agree to our{' '}
                    <a href="#" style={{ color: SLAB.muted }}>
                      Terms
                    </a>{' '}
                    and{' '}
                    <a href="#" style={{ color: SLAB.muted }}>
                      Privacy Policy
                    </a>
                    .
                  </div>
                )}
              </form>

              <div
                style={{
                  textAlign: 'center',
                  marginTop: 24,
                  fontSize: 13,
                  color: SLAB.muted,
                }}
              >
                {mode === 'login' && (
                  <>
                    New to Slabbist?{' '}
                    <button onClick={() => setMode('signup')} style={linkBtn}>
                      Create a store
                    </button>
                  </>
                )}
                {mode === 'signup' && (
                  <>
                    Already have an account?{' '}
                    <button onClick={() => setMode('login')} style={linkBtn}>
                      Sign in
                    </button>
                  </>
                )}
                {mode === 'reset' && (
                  <button onClick={() => setMode('login')} style={linkBtn}>
                    ← Back to sign in
                  </button>
                )}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function Field({
  label,
  icon,
  children,
}: {
  label: string;
  icon: IconName;
  children: ReactNode;
}) {
  return (
    <label style={{ display: 'block', position: 'relative' }}>
      <div
        style={{
          fontSize: 11,
          letterSpacing: 1,
          textTransform: 'uppercase',
          color: SLAB.dim,
          marginBottom: 8,
          fontWeight: 600,
        }}
      >
        {label}
      </div>
      <div style={{ position: 'relative' }}>
        <div
          style={{
            position: 'absolute',
            left: 14,
            top: '50%',
            transform: 'translateY(-50%)',
            color: SLAB.muted,
            pointerEvents: 'none',
          }}
        >
          <Icon name={icon} size={15} />
        </div>
        {children}
      </div>
    </label>
  );
}

function OAuthBtn({ label, icon }: { label: string; icon: ReactNode }) {
  return (
    <button
      type="button"
      className="slab-oauth-btn"
      style={{
        padding: '12px 16px',
        borderRadius: 12,
        border: '1px solid ' + SLAB.hair,
        color: SLAB.text,
        fontSize: 13,
        fontWeight: 500,
        cursor: 'pointer',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 10,
      }}
    >
      {icon}
      {label}
    </button>
  );
}

const AppleLogo = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
    <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.08zM12 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
  </svg>
);

const GoogleLogo = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden>
    <path
      fill="#4285F4"
      d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
    />
    <path
      fill="#34A853"
      d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
    />
    <path
      fill="#FBBC05"
      d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09 0-.73.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
    />
    <path
      fill="#EA4335"
      d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
    />
  </svg>
);

function Spinner() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" style={{ animation: 'sbmSpin 0.8s linear infinite' }} aria-hidden>
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="2.5" fill="none" opacity="0.25" />
      <path
        d="M21 12a9 9 0 0 0-9-9"
        stroke="currentColor"
        strokeWidth="2.5"
        fill="none"
        strokeLinecap="round"
      />
    </svg>
  );
}

function SuccessView({
  mode,
  email,
  onClose,
  titleId,
}: {
  mode: AuthMode;
  email: string;
  onClose: () => void;
  titleId: string;
}) {
  const msgs: Record<AuthMode, { t: string; s: string }> = {
    login: { t: 'Signed in', s: 'Opening your store…' },
    signup: { t: 'Store created', s: `We've sent a verification email to ${email || 'you'}.` },
    reset: { t: 'Check your inbox', s: `We've sent a reset link to ${email || 'your email'}.` },
  };
  const m = msgs[mode];
  return (
    <div style={{ textAlign: 'center', padding: '20px 0' }}>
      <div
        style={{
          width: 68,
          height: 68,
          borderRadius: '50%',
          margin: '0 auto 24px',
          background: `linear-gradient(135deg, ${SLAB.gold}, ${SLAB.goldDim})`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: SLAB.ink,
          boxShadow: '0 0 40px oklch(0.82 0.13 78 / 0.40)',
          animation: 'sbmPop 0.5s ease',
        }}
      >
        <Icon name="check" size={32} sw={3} />
      </div>
      <h2
        id={titleId}
        style={{
          fontFamily: SLAB.serif,
          fontSize: 28,
          letterSpacing: -0.6,
          margin: '0 0 10px',
          fontWeight: 400,
        }}
      >
        {m.t}
      </h2>
      <p style={{ fontSize: 13, color: SLAB.muted, margin: '0 0 28px' }}>{m.s}</p>
      <button
        onClick={onClose}
        style={{
          padding: '12px 28px',
          borderRadius: 999,
          background: SLAB.text,
          color: SLAB.ink,
          border: 'none',
          fontSize: 13,
          fontWeight: 600,
          cursor: 'pointer',
        }}
      >
        Done
      </button>
    </div>
  );
}
