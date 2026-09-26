import { useEffect, useState } from 'react'
import { supabase, type Config, type DashUser, type GameStaff } from '../lib/supabase'
import { DEFAULTS, FEATURES, FEATURE_DEFAULTS, GROUPS } from '../lib/thresholds'
import { ago, errorText } from '../lib/format'
import { useGame } from '../lib/game'
import { Button, Panel } from '../components/ui'

type Props = { config: Config | null; users: DashUser[]; staff: GameStaff[]; me: DashUser; reload: () => void }

export function Settings({ config, users, staff, me, reload }: Props) {
  const isOwner = me.role === 'owner'
  const isAdmin = isOwner || me.role === 'admin'
  return (
    <div className="space-y-5">
      <GameSettings isOwner={isOwner} />
      <Features config={config} reload={reload} />
      <Thresholds config={config} reload={reload} />
      <MyRoblox me={me} reload={reload} />
      <Webhook />
      <Keys />
      <DiscordBot />
      {isAdmin && <Team users={users} staff={staff} me={me} reload={reload} />}
    </div>
  )
}

const inputClass = 'rounded-lg border border-line bg-panel-2 px-3 py-1.5 text-sm outline-none focus:border-accent/60'

// shows a freshly made game key exactly once. it's never stored anywhere we can read back
function KeyReveal({ value, done }: { value: string; done: () => void }) {
  const [copied, setCopied] = useState(false)
  return (
    <div className="space-y-2 rounded-lg border border-warn/40 bg-warn/5 p-3">
      <div className="text-sm font-medium text-warn">Copy this key now, it won't be shown again</div>
      <div className="flex gap-2">
        <input readOnly value={value} onFocus={(e) => e.target.select()} className={`${inputClass} flex-1 font-mono text-xs`} />
        <Button
          onClick={() => {
            navigator.clipboard?.writeText(value).then(() => setCopied(true), () => {})
          }}
        >
          {copied ? 'Copied' : 'Copy'}
        </Button>
        <Button tone="ghost" onClick={done}>
          Done
        </Button>
      </div>
      <ol className="list-decimal space-y-1 pl-5 text-xs text-muted">
        <li>
          Live servers: Creator Dashboard → your experience → Secrets → add <code className="text-text">anticheat_key</code> with this value.
        </li>
        <li>
          Studio: a ModuleScript <code className="text-text">ServerKey</code> inside <code className="text-text">ServerScriptService.AntiCheat</code> that
          returns it as a string. Keep that script out of published copies you share.
        </li>
        <li>The old key stops working right away.</li>
      </ol>
    </div>
  )
}

function GameSettings({ isOwner }: { isOwner: boolean }) {
  const { game, games, current, reloadGames } = useGame()
  const [name, setName] = useState('')
  const [universe, setUniverse] = useState('')
  const [guild, setGuild] = useState('')
  const [msg, setMsg] = useState('')
  const [key, setKey] = useState<string | null>(null)
  const [newName, setNewName] = useState('')
  const [confirmDelete, setConfirmDelete] = useState('')

  useEffect(() => {
    setName(current?.name ?? '')
    setUniverse(current?.universe_id ? String(current.universe_id) : '')
    setGuild(current?.discord_guild ?? '')
  }, [current?.name, current?.universe_id, current?.discord_guild])

  // switching games hides a key that was just shown
  useEffect(() => {
    setKey(null)
    setMsg('')
    setConfirmDelete('')
  }, [current?.id])

  async function save() {
    const { error } = await supabase.rpc('admin_update_game', {
      p_game: game,
      p_name: name.trim(),
      p_universe: universe ? Number(universe) : null,
      p_guild: guild.trim() || null,
    })
    setMsg(error ? errorText(error) : 'Saved.')
    reloadGames()
  }

  async function rotate() {
    const { data, error } = await supabase.rpc('admin_rotate_key', { p_game: game })
    if (error) setMsg(errorText(error))
    else setKey(String(data))
  }

  async function create() {
    const { data, error } = await supabase.rpc('admin_create_game', { p_name: newName.trim() })
    if (error) {
      setMsg(errorText(error))
      return
    }
    const made = data as { id: number; key: string }
    setNewName('')
    reloadGames()
    setKey(made.key)
    setMsg(`Created "${newName.trim()}". This is its key. Switch to it with the game picker at the top to set it up.`)
  }

  async function remove() {
    const { error } = await supabase.rpc('admin_delete_game', { p_game: game })
    if (error) setMsg(errorText(error))
    else {
      setMsg('Deleted.')
      reloadGames()
    }
  }

  return (
    <Panel title="Game" right={<span className="font-mono text-xs text-muted">id {game}</span>}>
      <div className="space-y-4 p-4">
        <form
          className="grid gap-3 sm:grid-cols-3"
          onSubmit={(e) => {
            e.preventDefault()
            save()
          }}
        >
          <label className="text-xs text-muted">
            Name
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={40} className={`${inputClass} mt-1 w-full text-text`} />
          </label>
          <label className="text-xs text-muted">
            Universe id <span className="text-muted/70">(for instant bans)</span>
            <input
              value={universe}
              onChange={(e) => setUniverse(e.target.value.replace(/\D/g, ''))}
              inputMode="numeric"
              maxLength={14}
              className={`${inputClass} mt-1 w-full font-mono text-text`}
            />
          </label>
          <label className="text-xs text-muted">
            Discord server id <span className="text-muted/70">(for the bot)</span>
            <input
              value={guild}
              onChange={(e) => setGuild(e.target.value.replace(/\D/g, ''))}
              inputMode="numeric"
              maxLength={25}
              className={`${inputClass} mt-1 w-full font-mono text-text`}
            />
          </label>
          <div className="sm:col-span-3">
            <Button tone="accent" type="submit" disabled={!name.trim()}>
              Save
            </Button>
          </div>
        </form>

        {key ? (
          <KeyReveal value={key} done={() => setKey(null)} />
        ) : (
          isOwner && (
            <div className="flex flex-wrap items-center gap-2 border-t border-line pt-4">
              <Button onClick={rotate}>New game key</Button>
              <span className="text-xs text-muted">Game servers prove which game they are with this key. Only its hash is stored.</span>
            </div>
          )
        )}

        {isOwner && (
          <div className="grid gap-4 border-t border-line pt-4 lg:grid-cols-2">
            <form
              className="space-y-2"
              onSubmit={(e) => {
                e.preventDefault()
                create()
              }}
            >
              <div className="text-xs font-semibold uppercase tracking-[0.14em] text-muted">Add another game</div>
              <p className="text-xs text-muted">
                Same anticheat, its own key, settings, bans, webhook and staff. Give a client's staff access to only their game in Team below.
              </p>
              <div className="flex gap-2">
                <input value={newName} onChange={(e) => setNewName(e.target.value)} maxLength={40} placeholder="Game name" className={`${inputClass} flex-1`} />
                <Button tone="accent" type="submit" disabled={!newName.trim()}>
                  Create
                </Button>
              </div>
            </form>
            {games.length > 1 && (
              <form
                className="space-y-2"
                onSubmit={(e) => {
                  e.preventDefault()
                  remove()
                }}
              >
                <div className="text-xs font-semibold uppercase tracking-[0.14em] text-bad">Delete this game</div>
                <p className="text-xs text-muted">Removes every player, flag, ban, replay and report of {current?.name}. Type its name to confirm.</p>
                <div className="flex gap-2">
                  <input value={confirmDelete} onChange={(e) => setConfirmDelete(e.target.value)} placeholder={current?.name} className={`${inputClass} flex-1`} />
                  <Button tone="danger" type="submit" disabled={confirmDelete !== current?.name}>
                    Delete
                  </Button>
                </div>
              </form>
            )}
          </div>
        )}
        {msg && <p className="text-sm text-muted">{msg}</p>}
      </div>
    </Panel>
  )
}

function Features({ config, reload }: { config: Config | null; reload: () => void }) {
  const { game } = useGame()
  const [busy, setBusy] = useState<string | null>(null)
  const [msg, setMsg] = useState('')
  const current = { ...FEATURE_DEFAULTS, ...(config?.features ?? {}) }

  async function toggle(key: string) {
    setBusy(key)
    setMsg('')
    const next = { ...current, [key]: !current[key] }
    // only send what differs from the default, the game falls back cleanly for the rest
    const diff = Object.fromEntries(Object.entries(next).filter(([k, v]) => v !== FEATURE_DEFAULTS[k]))
    const { error } = await supabase.rpc('admin_set_features', { p_game: game, p_features: diff })
    setBusy(null)
    if (error) setMsg(errorText(error))
    else {
      setMsg('Saved. Servers switch within 20s.')
      reload()
    }
  }

  return (
    <Panel title="Features" right={<span className="text-xs text-muted">live, no republish</span>}>
      <div className="grid gap-2 p-4 sm:grid-cols-2 xl:grid-cols-3">
        {FEATURES.map((f) => {
          const on = current[f.key]
          return (
            <button
              key={f.key}
              onClick={() => toggle(f.key)}
              disabled={busy !== null}
              className={`flex items-start gap-3 rounded-lg border p-3 text-left transition disabled:opacity-60 ${
                on ? 'border-accent/30 bg-accent/5' : 'border-line bg-panel-2'
              }`}
            >
              <span className={`mt-0.5 flex h-5 w-9 shrink-0 items-center rounded-full p-0.5 transition ${on ? 'bg-accent' : 'bg-line'}`}>
                <span className={`h-4 w-4 rounded-full bg-white transition ${on ? 'translate-x-4' : ''}`} />
              </span>
              <span>
                <span className="block text-sm font-medium">
                  {f.label}
                  {f.key === 'CheaterIsland' && <span className="ml-2 text-[10px] uppercase text-warn">published games only</span>}
                </span>
                <span className="block text-xs text-muted">{f.hint}</span>
              </span>
            </button>
          )
        })}
      </div>
      {msg && <p className="px-4 pb-3 text-sm text-muted">{msg}</p>}
    </Panel>
  )
}

function MyRoblox({ me, reload }: { me: DashUser; reload: () => void }) {
  const [id, setId] = useState(me.roblox_id ? String(me.roblox_id) : '')
  const [msg, setMsg] = useState('')
  async function save() {
    const n = id.trim() ? Number(id) : null
    const { error } = await supabase.rpc('admin_set_my_roblox', { p_id: n })
    setMsg(error ? errorText(error) : 'Saved.')
    reload()
  }
  return (
    <Panel title="Your Roblox account">
      <form className="flex flex-wrap items-center gap-2 p-4" onSubmit={(e) => { e.preventDefault(); save() }}>
        <input
          value={id}
          onChange={(e) => setId(e.target.value.replace(/\D/g, ''))}
          inputMode="numeric"
          maxLength={12}
          placeholder="Roblox user id"
          className="w-44 rounded-lg border border-line bg-panel-2 px-3 py-1.5 font-mono text-sm outline-none focus:border-accent/60"
        />
        <Button tone="accent" type="submit">Save</Button>
        <span className="text-xs text-muted">
          Needed for "Spectate" on the dashboard: with the game open, it pulls you into the suspect's server, invisible. The id must also be in Config.Admins in the game.
        </span>
        {msg && <span className="w-full text-sm text-muted">{msg}</span>}
      </form>
    </Panel>
  )
}

function Keys() {
  const { game } = useGame()
  const [status, setStatus] = useState<Record<string, boolean>>({})
  const [value, setValue] = useState('')
  const [msg, setMsg] = useState('')
  const load = () => supabase.rpc('secrets_status', { p_game: game }).then(({ data }) => setStatus((data as Record<string, boolean>) ?? {}))
  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [game])
  async function save(v: string) {
    const { error } = await supabase.rpc('admin_set_secret', { p_game: game, p_key: 'open_cloud_key', p_value: v.trim() })
    setMsg(error ? errorText(error) : v ? 'Saved.' : 'Removed.')
    setValue('')
    load()
  }
  return (
    <Panel title="Roblox Open Cloud key" right={<span className={`text-xs ${status.open_cloud_key ? 'text-good' : 'text-muted'}`}>{status.open_cloud_key ? 'connected' : 'not set'}</span>}>
      <form className="flex flex-wrap items-center gap-2 p-4" onSubmit={(e) => { e.preventDefault(); save(value) }}>
        <input
          type="password"
          autoComplete="off"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="Paste a new key to replace the current one"
          className="min-w-64 flex-1 rounded-lg border border-line bg-panel-2 px-3 py-1.5 font-mono text-sm outline-none focus:border-accent/60"
        />
        <Button tone="accent" type="submit" disabled={!value.trim()}>Save</Button>
        <div className="w-full text-xs text-muted">
          Makes bans hit every server in about a second. Needs the Messaging Service "publish" permission for this game's
          experience, and its universe id above. Write only, it can never be read back.
        </div>
        {msg && <div className="w-full text-sm text-muted">{msg}</div>}
      </form>
    </Panel>
  )
}

function DiscordBot() {
  const endpoint = 'https://kapvjoemzsdqiealluzl.supabase.co/functions/v1/discord'
  const invite = 'https://discord.com/oauth2/authorize?client_id=1553113119298162788&scope=applications.commands'
  return (
    <Panel title="Discord bot">
      <div className="space-y-2 p-4 text-sm">
        <p className="text-muted">
          <code className="text-text">/check</code> <code className="text-text">/ban</code> <code className="text-text">/unban</code>{' '}
          <code className="text-text">/replay</code> <code className="text-text">/shadow</code>, usable by staff of the game linked to
          that Discord server (Game → Discord server id). With only one game, every server uses it.
        </p>
        <ol className="list-decimal space-y-1 pl-5 text-muted">
          <li>
            Discord Developer Portal → your app → General Information → Interactions Endpoint URL:
            <code className="ml-1 break-all rounded bg-panel-2 px-1.5 py-0.5 text-xs text-text">{endpoint}</code>
          </li>
          <li>
            Add it to your server:{' '}
            <a href={invite} target="_blank" rel="noopener noreferrer" className="text-accent hover:underline">
              install link ↗
            </a>
          </li>
        </ol>
      </div>
    </Panel>
  )
}

function Thresholds({ config, reload }: { config: Config | null; reload: () => void }) {
  const { game } = useGame()
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
    const { data, error } = await supabase.rpc('admin_set_thresholds', { p_game: game, p_thresholds: diff })
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
  const { game } = useGame()
  const [url, setUrl] = useState('')
  const [set, setSet] = useState<boolean | null>(null)
  const [msg, setMsg] = useState('')

  useEffect(() => {
    setSet(null)
    supabase.rpc('secrets_status', { p_game: game }).then(({ data }) => setSet(Boolean((data as Record<string, boolean>)?.discord_webhook)))
  }, [game])

  async function save(value: string) {
    setMsg('')
    const { error } = await supabase.rpc('admin_set_webhook', { p_game: game, p_url: value.trim() })
    if (error) setMsg(errorText(error))
    else {
      setSet(value.trim() !== '')
      setUrl('')
      setMsg(value.trim() ? 'Saved. Kicks, auto-shadows, reports and the daily report post there.' : 'Removed.')
    }
  }

  return (
    <Panel title="Discord alerts" right={<span className={`text-xs ${set ? 'text-good' : 'text-muted'}`}>{set === null ? '' : set ? 'connected' : 'not set'}</span>}>
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

function Team({ users, staff, me, reload }: { users: DashUser[]; staff: GameStaff[]; me: DashUser; reload: () => void }) {
  const isOwner = me.role === 'owner'
  const { games } = useGame()
  const [msg, setMsg] = useState('')

  async function setRole(id: string, role: 'admin' | 'staff' | 'pending') {
    setMsg('')
    const { error } = await supabase.rpc('admin_set_role', { p_target: id, p_role: role })
    if (error) setMsg(errorText(error))
    else reload()
  }
  async function setSeat(id: string, game: number, on: boolean) {
    setMsg('')
    const { error } = await supabase.rpc('admin_set_staff', { p_target: id, p_game: game, p_on: on })
    if (error) setMsg(errorText(error))
    else reload()
  }
  async function remove(id: string) {
    const { error } = await supabase.rpc('admin_remove_user', { p_target: id })
    if (error) setMsg(errorText(error))
    else reload()
  }

  const tone = (role: string) =>
    role === 'owner' ? 'bg-accent/15 text-accent' : role === 'admin' ? 'bg-good/15 text-good' : role === 'staff' ? 'bg-veil/15 text-veil' : 'bg-warn/15 text-warn'

  return (
    <Panel title="Team">
      <ul className="divide-y divide-line">
        {users.map((u) => {
          const seats = new Set(staff.filter((s) => s.user_id === u.user_id).map((s) => s.game_id))
          return (
            <li key={u.user_id} className="space-y-2 px-4 py-3">
              <div className="flex items-center gap-3">
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
                {isOwner && u.role !== 'owner' ? (
                  <select
                    value={u.role}
                    onChange={(e) => setRole(u.user_id, e.target.value as 'admin' | 'staff' | 'pending')}
                    className="rounded-lg border border-line bg-panel-2 px-2 py-1 text-xs"
                    aria-label="Role"
                  >
                    <option value="pending">Pending</option>
                    <option value="staff">Staff (chosen games)</option>
                    <option value="admin">Admin (every game)</option>
                  </select>
                ) : (
                  <span className={`rounded px-2 py-0.5 text-[11px] font-semibold uppercase ${tone(u.role)}`}>{u.role}</span>
                )}
                {isOwner && u.role !== 'owner' && (
                  <Button tone="ghost" onClick={() => remove(u.user_id)}>
                    Remove
                  </Button>
                )}
              </div>
              {(u.role === 'staff' || (isOwner && u.role === 'pending')) && (
                <div className="flex flex-wrap items-center gap-1.5 pl-11">
                  <span className="text-[11px] text-muted">{u.role === 'pending' ? 'Approve for:' : 'Games:'}</span>
                  {games.map((g) => {
                    const on = seats.has(g.id)
                    return (
                      <button
                        key={g.id}
                        disabled={!isOwner}
                        onClick={() => setSeat(u.user_id, g.id, !on)}
                        className={`rounded-md border px-2 py-0.5 text-xs transition disabled:cursor-default ${
                          on ? 'border-veil/40 bg-veil/10 text-veil' : 'border-line text-muted hover:text-text'
                        }`}
                      >
                        {on ? '✓ ' : '+ '}
                        {g.name}
                      </button>
                    )
                  })}
                </div>
              )}
            </li>
          )
        })}
      </ul>
      {msg && <div className="px-4 pb-3 text-sm text-bad">{msg}</div>}
      <div className="px-4 pb-3 text-xs text-muted">
        {isOwner
          ? 'Admins see every game. Staff only see the games ticked for them, which is how a client gets access to just their own game.'
          : 'Only the owner can approve people.'}
      </div>
    </Panel>
  )
}
