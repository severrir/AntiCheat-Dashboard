import { useEffect, useState } from 'react'
import { supabase, type Appeal, type Ban, type Player } from '../lib/supabase'
import { ago, errorText } from '../lib/format'
import { Button, Empty, Panel } from '../components/ui'

// staff side: every open appeal next to the ban reason and the player's latest replay
export function Appeals({ appeals, bans, players, open, openReplay }: {
  appeals: Appeal[]
  bans: Ban[]
  players: Player[]
  open: (id: number) => void
  openReplay: (id: number) => void
}) {
  const [tab, setTab] = useState<'open' | 'decided'>('open')
  const rows = appeals.filter((a) => (tab === 'open' ? a.status === 'open' : a.status !== 'open'))

  return (
    <div className="space-y-5">
      <div className="flex gap-1">
        {(['open', 'decided'] as const).map((t) => (
          <button key={t} onClick={() => setTab(t)} className={`rounded-lg px-3 py-1.5 text-sm ${tab === t ? 'bg-panel-2 text-text' : 'text-muted hover:text-text'}`}>
            {t === 'open' ? `Open · ${appeals.filter((a) => a.status === 'open').length}` : 'Decided'}
          </button>
        ))}
      </div>
      {rows.length === 0 ? (
        <Panel><Empty>{tab === 'open' ? 'No appeals waiting.' : 'Nothing decided yet.'}</Empty></Panel>
      ) : (
        rows.map((a) => (
          <AppealCard
            key={a.id}
            appeal={a}
            ban={bans.find((b) => b.user_id === a.user_id)}
            player={players.find((p) => p.user_id === a.user_id)}
            open={open}
            openReplay={openReplay}
          />
        ))
      )}
    </div>
  )
}

function AppealCard({ appeal, ban, player, open, openReplay }: {
  appeal: Appeal
  ban?: Ban
  player?: Player
  open: (id: number) => void
  openReplay: (id: number) => void
}) {
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [replayId, setReplayId] = useState<number | null>(null)

  useEffect(() => {
    supabase
      .from('replays')
      .select('id')
      .eq('user_id', appeal.user_id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()
      .then(({ data }) => setReplayId(data?.id ?? null))
  }, [appeal.user_id])

  async function decide(approve: boolean) {
    setBusy(true)
    setError('')
    const { error } = await supabase.rpc('decide_appeal', { p_id: appeal.id, p_approve: approve, p_note: note })
    setBusy(false)
    if (error) setError(errorText(error))
  }

  const tone = appeal.status === 'approved' ? 'text-good' : appeal.status === 'denied' ? 'text-bad' : 'text-warn'

  return (
    <Panel>
      <div className="space-y-4 p-4">
        <div className="flex flex-wrap items-center gap-3">
          <button onClick={() => open(appeal.user_id)} className="text-lg font-semibold hover:text-accent">
            {appeal.username || appeal.user_id}
          </button>
          <span className={`text-xs font-semibold uppercase ${tone}`}>{appeal.status}</span>
          <span className="text-xs text-muted">
            by {appeal.discord_name || 'discord user'} · {ago(appeal.created_at)}
          </span>
          {replayId && (
            <button onClick={() => openReplay(replayId)} className="ml-auto rounded-lg border border-accent/40 bg-accent/10 px-3 py-1 text-sm text-accent hover:bg-accent/20">
              ▶ Watch what they did
            </button>
          )}
        </div>
        <div className="grid gap-3 md:grid-cols-2">
          <div className="rounded-lg bg-panel-2 p-3">
            <div className="mb-1 text-[11px] uppercase tracking-[0.14em] text-muted">Their side</div>
            <p className="whitespace-pre-wrap text-sm">{appeal.message}</p>
          </div>
          <div className="rounded-lg bg-panel-2 p-3 text-sm">
            <div className="mb-1 text-[11px] uppercase tracking-[0.14em] text-muted">The record</div>
            <p>Ban reason: {ban?.reason || '—'}</p>
            <p className="text-muted">
              Banned by {ban?.banned_by ?? '?'}
              {ban ? ` · ${ago(ban.updated_at)}` : ''}
            </p>
            {player && (
              <p className="mt-2 text-muted">
                {player.kicks} kicks · {player.total_flags} flags · peak score {Math.round(player.peak_score)}
              </p>
            )}
          </div>
        </div>
        {appeal.status === 'open' ? (
          <div className="flex flex-wrap items-center gap-2">
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={500}
              placeholder="Note to the player (optional)"
              className="min-w-60 flex-1 rounded-lg border border-line bg-panel-2 px-3 py-1.5 text-sm outline-none focus:border-accent/60"
            />
            <Button tone="accent" onClick={() => decide(true)} disabled={busy}>
              Approve & unban
            </Button>
            <Button tone="danger" onClick={() => decide(false)} disabled={busy}>
              Deny
            </Button>
          </div>
        ) : (
          appeal.note && <p className="text-sm text-muted">Note: {appeal.note} ({appeal.decided_by})</p>
        )}
        {error && <p className="text-sm text-bad">{error}</p>}
      </div>
    </Panel>
  )
}

type Mine = { id: number; user_id: number; username: string; status: string; note: string; created_at: string; decided_at: string | null }

// public side: anyone signed in with discord can appeal a ban
export function AppealForm() {
  const [player, setPlayer] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState(false)
  const [mine, setMine] = useState<Mine[]>([])

  const load = () => supabase.rpc('my_appeals').then(({ data }) => setMine((data as Mine[]) ?? []))
  useEffect(() => {
    load()
  }, [])

  async function submit() {
    setBusy(true)
    setError('')
    const { error } = await supabase.rpc('submit_appeal', { p_user: player.trim(), p_message: message })
    setBusy(false)
    if (error) {
      setError(errorText(error))
      return
    }
    setDone(true)
    setMessage('')
    load()
  }

  return (
    <div className="mx-auto max-w-xl space-y-5">
      <div>
        <h1 className="text-xl font-semibold">Appeal a ban</h1>
        <p className="mt-1 text-sm text-muted">
          Think you were banned by mistake? Tell us what happened. A moderator will look at your appeal next to a recording of
          what the anticheat saw.
        </p>
      </div>
      <Panel>
        <form
          className="space-y-3 p-4"
          onSubmit={(e) => {
            e.preventDefault()
            submit()
          }}
        >
          <label className="block">
            <span className="text-sm">Roblox username or user id</span>
            <input
              value={player}
              onChange={(e) => setPlayer(e.target.value)}
              maxLength={25}
              required
              className="mt-1 w-full rounded-lg border border-line bg-panel-2 px-3 py-2 text-sm outline-none focus:border-accent/60"
            />
          </label>
          <label className="block">
            <span className="text-sm">What happened?</span>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              maxLength={1500}
              rows={6}
              required
              className="mt-1 w-full rounded-lg border border-line bg-panel-2 px-3 py-2 text-sm outline-none focus:border-accent/60"
            />
            <span className="text-xs text-muted">{message.length}/1500</span>
          </label>
          <Button tone="accent" type="submit" disabled={busy || !player.trim() || message.trim().length < 10}>
            Send appeal
          </Button>
          {error && <p className="text-sm text-bad">{error}</p>}
          {done && <p className="text-sm text-good">Sent. You can check its status below.</p>}
        </form>
      </Panel>
      {mine.length > 0 && (
        <Panel title="Your appeals">
          <ul className="divide-y divide-line">
            {mine.map((a) => (
              <li key={a.id} className="px-4 py-3 text-sm">
                <div className="flex items-center justify-between">
                  <span className="font-medium">{a.username || a.user_id}</span>
                  <span className={a.status === 'approved' ? 'text-good' : a.status === 'denied' ? 'text-bad' : 'text-warn'}>{a.status}</span>
                </div>
                <div className="text-xs text-muted">sent {ago(a.created_at)}{a.decided_at ? ` · decided ${ago(a.decided_at)}` : ''}</div>
                {a.note && <p className="mt-1 text-muted">{a.note}</p>}
              </li>
            ))}
          </ul>
        </Panel>
      )}
    </div>
  )
}
