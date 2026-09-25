import { useEffect, useState } from 'react'
import { supabase, type Config, type DashUser } from '../lib/supabase'
import { DEFAULTS, GROUPS } from '../lib/thresholds'
import { ago, errorText } from '../lib/format'
import { Button, Panel } from '../components/ui'

type Props = { config: Config | null; users: DashUser[]; me: DashUser; reload: () => void }

export function Settings({ config, users, me, reload }: Props) {
  const isOwner = me.role === 'owner'
  return (
    <div className="space-y-5">
      <Thresholds config={config} reload={reload} />
      {isOwner && <Webhook />}
      <Team users={users} me={me} reload={reload} />
    </div>
  )
}

function Thresholds({ config, reload }: { config: Config | null; reload: () => void }) {
  const [values, setValues] = useState<Record<string, number>>(DEFAULTS)
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    setValues({ ...DEFAULTS, ...(config?.thresholds ?? {}) })
  }, [config?.version, config?.thresholds])

  const changed = Object.keys(DEFAULTS).filter((k) => values[k] !== DEFAULTS[k])

  async function save(next: Record<string, number>) {
    setBusy(true)
    setMsg('')
    // only send what differs from default, so the game falls back cleanly
    const diff = Object.fromEntries(Object.entries(next).filter(([k, v]) => v !== DEFAULTS[k] && Number.isFinite(v)))
    const { data, error } = await supabase.rpc('admin_set_thresholds', { p_thresholds: diff })
    setBusy(false)
    if (error) setMsg(errorText(error))
    else {
      setMsg(`Saved as v${data}. Servers pick it up on their next sync (~20s).`)
      reload()
    }
  }

  return (
    <Panel
      title="Detection tuning"
      right={
        config && (
          <span className="text-xs text-muted">
            v{config.version}
            {config.updated_by && ` · ${config.updated_by}`} · {ago(config.updated_at)}
          </span>
        )
      }
    >
      <div className="grid gap-6 p-4 lg:grid-cols-2">
        {GROUPS.map((g) => (
          <div key={g.title}>
            <div className="mb-2 text-xs font-semibold text-text">{g.title}</div>
            <div className="space-y-2">
              {g.fields.map((f) => (
                <label key={f.key} className="grid grid-cols-[1fr_110px] items-center gap-3">
                  <span>
                    <span className={`text-sm ${values[f.key] !== f.def ? 'text-accent' : ''}`}>{f.label}</span>
                    <span className="block text-[11px] text-muted">{f.hint}</span>
                  </span>
                  <input
                    type="number"
                    step={f.step}
                    min={0}
                    max={100000}
                    value={Number.isFinite(values[f.key]) ? values[f.key] : ''}
                    onChange={(e) => setValues((v) => ({ ...v, [f.key]: e.target.value === '' ? NaN : Number(e.target.value) }))}
                    className="rounded-lg border border-line bg-panel-2 px-2 py-1 text-right font-mono text-sm outline-none focus:border-accent/60"
                  />
                </label>
              ))}
            </div>
          </div>
        ))}
      </div>
      <div className="flex flex-wrap items-center gap-3 border-t border-line px-4 py-3">
        <Button tone="accent" onClick={() => save(values)} disabled={busy}>
          Push to servers
        </Button>
        <Button onClick={() => save(DEFAULTS)} disabled={busy || changed.length === 0}>
          Reset to defaults
        </Button>
        <span className="text-xs text-muted">{changed.length} changed from default</span>
        {msg && <span className="text-sm text-muted">{msg}</span>}
      </div>
    </Panel>
  )
}

function Webhook() {
  const [url, setUrl] = useState('')
  const [set, setSet] = useState<boolean | null>(null)
  const [msg, setMsg] = useState('')

  useEffect(() => {
    supabase.rpc('webhook_configured').then(({ data }) => setSet(Boolean(data)))
  }, [])

  async function save(value: string) {
    setMsg('')
    const { error } = await supabase.rpc('admin_set_webhook', { p_url: value.trim() })
    if (error) setMsg(errorText(error))
    else {
      setSet(value.trim() !== '')
      setUrl('')
      setMsg(value.trim() ? 'Saved. Kicks will post there.' : 'Removed.')
    }
  }

  return (
    <Panel title="Discord kick alerts" right={<span className={`text-xs ${set ? 'text-good' : 'text-muted'}`}>{set === null ? '' : set ? 'connected' : 'not set'}</span>}>
      <form
        className="flex flex-wrap items-center gap-2 p-4"
        onSubmit={(e) => {
          e.preventDefault()
          save(url)
        }}
      >
        <input
          type="password"
          autoComplete="off"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="https://discord.com/api/webhooks/..."
          className="min-w-64 flex-1 rounded-lg border border-line bg-panel-2 px-3 py-1.5 font-mono text-sm outline-none focus:border-accent/60"
        />
        <Button tone="accent" type="submit" disabled={!url.trim()}>
          Save
        </Button>
        {set && (
          <Button tone="ghost" onClick={() => save('')}>
            Remove
          </Button>
        )}
        <div className="w-full text-xs text-muted">Stored server-side only. It can be replaced but never read back, not even here.</div>
        {msg && <div className="w-full text-sm text-muted">{msg}</div>}
      </form>
    </Panel>
  )
}

function Team({ users, me, reload }: { users: DashUser[]; me: DashUser; reload: () => void }) {
  const isOwner = me.role === 'owner'
  const [msg, setMsg] = useState('')

  async function setRole(id: string, role: 'admin' | 'pending') {
    const { error } = await supabase.rpc('admin_set_role', { p_target: id, p_role: role })
    if (error) setMsg(errorText(error))
    else reload()
  }
  async function remove(id: string) {
    const { error } = await supabase.rpc('admin_remove_user', { p_target: id })
    if (error) setMsg(errorText(error))
    else reload()
  }

  return (
    <Panel title="Team">
      <ul className="divide-y divide-line">
        {users.map((u) => (
          <li key={u.user_id} className="flex items-center gap-3 px-4 py-3">
            {u.avatar_url?.startsWith('https://cdn.discordapp.com/') ? (
              <img src={u.avatar_url} alt="" className="h-8 w-8 rounded-full" />
            ) : (
              <div className="grid h-8 w-8 place-items-center rounded-full bg-panel-2 text-xs">{(u.username || '?').slice(0, 1).toUpperCase()}</div>
            )}
            <div className="min-w-0 flex-1">
              <div className="truncate text-sm font-medium">
                {u.username || 'Discord user'} {u.user_id === me.user_id && <span className="text-muted">(you)</span>}
              </div>
              <div className="font-mono text-[11px] text-muted">{u.discord_id}</div>
            </div>
            <span
              className={`rounded px-2 py-0.5 text-[11px] font-semibold uppercase ${
                u.role === 'owner' ? 'bg-accent/15 text-accent' : u.role === 'admin' ? 'bg-good/15 text-good' : 'bg-warn/15 text-warn'
              }`}
            >
              {u.role}
            </span>
            {isOwner && u.role !== 'owner' && (
              <div className="flex gap-1">
                {u.role === 'pending' ? (
                  <Button tone="accent" onClick={() => setRole(u.user_id, 'admin')}>
                    Approve
                  </Button>
                ) : (
                  <Button onClick={() => setRole(u.user_id, 'pending')}>Revoke</Button>
                )}
                <Button tone="ghost" onClick={() => remove(u.user_id)}>
                  Remove
                </Button>
              </div>
            )}
          </li>
        ))}
      </ul>
      {msg && <div className="px-4 pb-3 text-sm text-bad">{msg}</div>}
      {!isOwner && <div className="px-4 pb-3 text-xs text-muted">Only the owner can approve people.</div>}
    </Panel>
  )
}
