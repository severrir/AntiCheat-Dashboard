import type { ReactNode } from 'react'
import { CHECK_COLORS } from '../lib/format'

export function Panel({ title, right, children, className = '' }: { title?: string; right?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`rounded-xl border border-line bg-panel/80 backdrop-blur ${className}`}>
      {title && (
        <header className="flex items-center justify-between border-b border-line px-4 py-3">
          <h2 className="text-xs font-semibold uppercase tracking-[0.14em] text-muted">{title}</h2>
          {right}
        </header>
      )}
      {children}
    </section>
  )
}

export function Stat({ label, value, tone = 'text-text', hint }: { label: string; value: ReactNode; tone?: string; hint?: string }) {
  return (
    <div className="rounded-xl border border-line bg-panel/80 p-4">
      <div className="text-[11px] font-medium uppercase tracking-[0.14em] text-muted">{label}</div>
      <div className={`mt-2 font-mono text-3xl font-medium ${tone}`}>{value}</div>
      {hint && <div className="mt-1 text-xs text-muted">{hint}</div>}
    </div>
  )
}

export function CheckTag({ name }: { name: string }) {
  const color = CHECK_COLORS[name] ?? CHECK_COLORS.Custom
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-md border px-2 py-0.5 font-mono text-[11px]"
      style={{ borderColor: `${color}40`, color, background: `${color}12` }}
    >
      <span className="h-1.5 w-1.5 rounded-full" style={{ background: color }} />
      {name}
    </span>
  )
}

export function Button({
  children,
  onClick,
  tone = 'default',
  disabled,
  type = 'button',
}: {
  children: ReactNode
  onClick?: () => void
  tone?: 'default' | 'danger' | 'accent' | 'ghost'
  disabled?: boolean
  type?: 'button' | 'submit'
}) {
  const tones = {
    default: 'border-line bg-panel-2 hover:border-muted/50 text-text',
    danger: 'border-bad/40 bg-bad/10 text-bad hover:bg-bad/20',
    accent: 'border-accent/40 bg-accent/10 text-accent hover:bg-accent/20',
    ghost: 'border-transparent text-muted hover:text-text',
  }
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`inline-flex items-center justify-center gap-2 rounded-lg border px-3 py-1.5 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-40 ${tones[tone]}`}
    >
      {children}
    </button>
  )
}

export function ScoreBar({ score, kick }: { score: number; kick: number }) {
  const pct = Math.min(100, (score / Math.max(kick, 1)) * 100)
  const color = pct >= 100 ? 'var(--color-bad)' : pct >= 50 ? 'var(--color-warn)' : 'var(--color-accent)'
  return (
    <div className="h-1.5 w-full overflow-hidden rounded-full bg-line">
      <div className="h-full rounded-full transition-all" style={{ width: `${pct}%`, background: color }} />
    </div>
  )
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="px-4 py-10 text-center text-sm text-muted">{children}</div>
}

export function Dot({ on }: { on: boolean }) {
  return <span className={`inline-block h-2 w-2 rounded-full ${on ? 'live-dot bg-good' : 'bg-line'}`} />
}
