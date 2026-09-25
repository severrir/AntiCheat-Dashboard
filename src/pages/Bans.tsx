import { useMemo, useState } from 'react'
import { supabase, type Ban, type Player } from '../lib/supabase'
import { ago, errorText } from '../lib/format'
import { Button, Empty, Panel } from '../components/ui'

export function Bans({ bans, players, open }: { bans: Ban[]; players: Player[]; open: (id: number) => void }) {
  const [id, setId] = useState('')
  const [reason, setReason] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const names = useMemo(() => new Map(players.map((p) => [p.user_id, p.username])), [players])
  const active = bans.filter((b) => b.active)
  const past = bans.filter((b) => !b.active).slice(0, 50)

  // ban someone who never joined yet, straight by user id
  async function banById() {
    const userId = Number(id.trim())
    if (!Number.isSafeInteger(userId) || userId <= 0) {
      setError('That is not a Roblox user id.')
      return
    }
    if (!reason.trim()) {
      setError('Give a reason.')
      return
    }
    setBusy(true)
    setError('')
    const { error } = await supabase.rpc('admin_ban', { p_user_id: userId, p_reason: reason.trim(), p_hours: null })
    setBusy(false)
    if (error) setError(errorText(error))
    else {
      setId('')
      setReason('')
    }
  }

  const row = (b: Ban) => (
    <li key={b.user_id}>
      <button onClick={() => open(b.user_id)} className="grid w-full grid-cols-[1fr_auto] items-center gap-4 px-4 py-3 text-left hover:bg-panel-2">
        <div className="min-w-0">
          <div className="truncate font-medium">
            {names.get(b.user_id) || b.user_id}
            <span className="ml-2 font-mono text-xs text-muted">{b.user_id}</span>
          </div>
          <div className="truncate text-sm text-muted">{b.reason || 'no reason'}</div>
        </div>
        <div className="text-right text-xs text-muted">
          <div>
            {b.banned_by} · {ago(b.updated_at)}
          </div>
          <div>{b.expires_at ? `until ${new Date(b.expires_at).toLocaleDateString()}` : b.active ? 'permanent' : 'lifted'}</div>
        </div>
      </button>
    </li>
  )

  return (
    <div className="space-y-5">
      <Panel title="Ban by user id">
        <form
          className="flex flex-wrap items-center gap-2 p-4"
          onSubmit={(e) => {
            e.preventDefault()
            banById()
          }}
        >
          <input
            value={id}
            onChange={(e) => setId(e.target.value.replace(/\D/g, ''))}
            inputMode="numeric"
            maxLength={19}
            placeholder="Roblox user id"
            className="w-44 rounded-lg border border-line bg-panel-2 px-3 py-1.5 font-mono text-sm outline-none focus:border-bad/60"
          />
          <input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            maxLength={200}
            placeholder="Reason"
            className="min-w-48 flex-1 rounded-lg border border-line bg-panel-2 px-3 py-1.5 text-sm outline-none focus:border-bad/60"
          />
          <Button tone="danger" type="submit" disabled={busy}>
            Ban permanently
          </Button>
          {error && <div className="w-full text-sm text-bad">{error}</div>}
        </form>
      </Panel>

      <Panel title={`Active bans · ${active.length}`}>
        {active.length === 0 ? <Empty>No one is banned.</Empty> : <ul className="divide-y divide-line">{active.map(row)}</ul>}
      </Panel>

      {past.length > 0 && (
        <Panel title="Lifted / expired">
          <ul className="divide-y divide-line opacity-70">{past.map(row)}</ul>
        </Panel>
      )}
    </div>
  )
}
