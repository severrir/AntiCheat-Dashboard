// flag context straight from the game. rendered as text only, never html
export function Context({ ctx }: { ctx: Record<string, string | number | boolean> | null }) {
  const entries = Object.entries(ctx ?? {}).slice(0, 8)
  if (entries.length === 0) return <span />
  return (
    <div className="flex flex-wrap gap-1.5">
      {entries.map(([k, v]) => (
        <span key={k} className="rounded bg-panel-2 px-1.5 py-0.5 font-mono text-[11px] text-muted">
          <span className="text-muted/70">{k}</span> <span className="text-text">{typeof v === 'number' ? +v.toFixed(2) : String(v)}</span>
        </span>
      ))}
    </div>
  )
}
