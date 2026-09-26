-- every function now takes the game it works on. old single-game versions go away
drop function public.admin_ban(bigint, text, integer);
drop function public.admin_unban(bigint);
drop function public.admin_set_thresholds(jsonb);
drop function public.admin_set_features(jsonb);
drop function public.admin_set_webhook(text);
drop function public.webhook_configured();
drop function public.admin_set_secret(text, text);
drop function public.secrets_status();
drop function public.admin_command(text, bigint);
drop function public.tuning_suggestions();
drop function public.submit_appeal(text, text);
drop function public.my_appeals();
drop function public.game_ingest(jsonb);
drop function public.game_pulse(jsonb);
drop function public.game_join(bigint);
drop function public.game_replay(jsonb);
drop function public.game_map_check(bigint, text, integer, jsonb);
drop function public.game_map_chunk(bigint, text, integer, jsonb);
drop function private.take_commands(bigint[]);
drop function private.ack_commands(jsonb);
drop function private.alt_check(bigint);

-- ===== secrets the edge functions read (service role only) =====
create or replace function public.game_secret(p_name text) returns text
language sql stable security definer set search_path = '' as $$
  select value from private.secrets
  where key = p_name and p_name in ('discord_public_key', 'discord_client_id', 'discord_client_secret', 'cron_key');
$$;

create or replace function public.game_secret_for(p_game integer, p_name text) returns text
language sql stable security definer set search_path = '' as $$
  select value from private.game_secrets
  where game_id = p_game and key = p_name and p_name in ('discord_webhook', 'open_cloud_key');
$$;

-- which game does this key belong to
create or replace function public.game_auth(p_hash text) returns integer
language sql stable security definer set search_path = '' as $$
  select game_id from private.game_keys where key_sha256 = p_hash;
$$;

-- ===== games =====
create or replace function private.new_key(g integer) returns text
language plpgsql security definer set search_path = '' as $$
declare
  k text := 'ac_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  insert into private.game_keys (game_id, key_sha256)
  values (g, encode(extensions.digest(k, 'sha256'), 'hex'))
  on conflict (game_id) do update set key_sha256 = excluded.key_sha256;
  return k;
end;
$$;

-- the key is only ever shown here, once
create or replace function public.admin_create_game(p_name text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  g integer;
begin
  if not private.is_owner() then raise exception 'not allowed'; end if;
  p_name := trim(coalesce(p_name, ''));
  if length(p_name) < 1 or length(p_name) > 40 then raise exception 'name must be 1-40 characters'; end if;
  insert into public.games (name) values (p_name) returning id into g;
  insert into public.config (game_id) values (g);
  return jsonb_build_object('id', g, 'key', private.new_key(g));
end;
$$;

create or replace function public.admin_rotate_key(p_game integer) returns text
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.games where id = p_game) then raise exception 'no such game'; end if;
  return private.new_key(p_game);
end;
$$;

create or replace function public.admin_update_game(p_game integer, p_name text, p_universe bigint, p_guild text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.gate(p_game);
  p_name := trim(coalesce(p_name, ''));
  p_guild := nullif(trim(coalesce(p_guild, '')), '');
  if length(p_name) < 1 or length(p_name) > 40 then raise exception 'name must be 1-40 characters'; end if;
  if p_universe is not null and (p_universe <= 0 or p_universe > 99999999999999) then raise exception 'bad universe id'; end if;
  if p_guild is not null and p_guild !~ '^[0-9]{5,25}$' then raise exception 'bad discord server id'; end if;
  if p_guild is not null and exists (select 1 from public.games where discord_guild = p_guild and id <> p_game) then
    raise exception 'that discord server is already linked to another game';
  end if;
  update public.games set name = p_name, universe_id = p_universe, discord_guild = p_guild where id = p_game;
end;
$$;

create or replace function public.admin_delete_game(p_game integer) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() then raise exception 'not allowed'; end if;
  if (select count(*) from public.games) <= 1 then raise exception 'you need at least one game'; end if;
  delete from public.games where id = p_game;
end;
$$;

-- ===== team =====
create or replace function public.admin_set_role(p_target uuid, p_role text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() then raise exception 'not allowed'; end if;
  if p_role not in ('admin', 'staff', 'pending') then raise exception 'bad role'; end if;
  if p_target = (select auth.uid()) then raise exception 'cannot change own role'; end if;
  update public.dashboard_users set role = p_role where user_id = p_target and role <> 'owner';
  if p_role <> 'staff' then
    delete from public.game_staff where user_id = p_target;
  end if;
end;
$$;

create or replace function public.admin_set_staff(p_target uuid, p_game integer, p_on boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.dashboard_users where user_id = p_target and role in ('staff', 'pending')) then
    raise exception 'only pending or staff accounts get per-game access';
  end if;
  if p_on then
    insert into public.game_staff (game_id, user_id) values (p_game, p_target) on conflict do nothing;
    update public.dashboard_users set role = 'staff' where user_id = p_target and role = 'pending';
  else
    delete from public.game_staff where game_id = p_game and user_id = p_target;
  end if;
end;
$$;

-- ===== settings per game =====
create or replace function public.admin_set_thresholds(p_game integer, p_thresholds jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  allowed text[] := array[
    'KickScore','HalfLife','SpeedMargin','TeleportDistance','FlyTime','FlyHeight',
    'RemoteBurstMultiplier','MinCorroboratingChecks','HeartbeatTimeout','TimingMinCV',
    'AccuracyCap','ShadowScore','WeightMovement','WeightCharacter','WeightRemote','WeightStatistical',
    'WeightTiming','WeightHoneypot','WeightClient','WeightCombat'
  ];
  k text;
  v jsonb;
  clean jsonb := '{}'::jsonb;
  new_version integer;
begin
  perform private.gate(p_game);
  if jsonb_typeof(p_thresholds) <> 'object' then raise exception 'bad payload'; end if;
  for k, v in select * from jsonb_each(p_thresholds) loop
    if k = any(allowed) and jsonb_typeof(v) = 'number' then
      clean := clean || jsonb_build_object(k, greatest(0, least((v)::text::numeric, 100000)));
    end if;
  end loop;
  update public.config set thresholds = clean, version = version + 1,
    updated_at = now(), updated_by = private.actor_name()
  where game_id = p_game returning version into new_version;
  return new_version;
end;
$$;

create or replace function public.admin_set_features(p_game integer, p_features jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  allowed text[] := array[
    'Movement','Character','Timing','Statistical','Combat','Client','NetGuard',
    'Honeypot','TrapVault','BaitNPC','BaitCoin','Replays','MapExport','MissionControl',
    'Spectator','CheaterIsland','AltDetection','GlobalBans','CrossServerTrust',
    'ShadowMode','Reports','RevertGains'
  ];
  k text;
  v jsonb;
  clean jsonb := '{}'::jsonb;
  new_version integer;
begin
  perform private.gate(p_game);
  if jsonb_typeof(p_features) <> 'object' then raise exception 'bad payload'; end if;
  for k, v in select * from jsonb_each(p_features) loop
    if k = any(allowed) and jsonb_typeof(v) = 'boolean' then
      clean := clean || jsonb_build_object(k, v);
    end if;
  end loop;
  update public.config set features = clean, version = version + 1,
    updated_at = now(), updated_by = private.actor_name()
  where game_id = p_game returning version into new_version;
  return new_version;
end;
$$;

create or replace function public.admin_set_webhook(p_game integer, p_url text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.gate(p_game);
  if p_url is null or p_url = '' then
    delete from private.game_secrets where game_id = p_game and key = 'discord_webhook';
    return;
  end if;
  if p_url !~ '^https://(discord\.com|discordapp\.com)/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$' then
    raise exception 'not a discord webhook url';
  end if;
  insert into private.game_secrets (game_id, key, value) values (p_game, 'discord_webhook', p_url)
  on conflict (game_id, key) do update set value = excluded.value;
end;
$$;

create or replace function public.admin_set_secret(p_game integer, p_key text, p_value text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_key = 'discord_public_key' then
    -- the bot is shared by every game
    if not private.is_owner() then raise exception 'not allowed'; end if;
    if p_value is null or p_value = '' then
      delete from private.secrets where key = p_key;
      return;
    end if;
    if p_value !~ '^[0-9a-f]{64}$' then raise exception 'that is not a discord public key'; end if;
    insert into private.secrets (key, value) values (p_key, p_value)
    on conflict (key) do update set value = excluded.value;
    return;
  end if;

  perform private.gate(p_game);
  if p_key <> 'open_cloud_key' then raise exception 'unknown setting'; end if;
  if p_value is null or p_value = '' then
    delete from private.game_secrets where game_id = p_game and key = p_key;
    return;
  end if;
  if length(p_value) < 20 or length(p_value) > 4000 or p_value ~ '\s' then
    raise exception 'that does not look like an open cloud key';
  end if;
  insert into private.game_secrets (game_id, key, value) values (p_game, p_key, p_value)
  on conflict (game_id, key) do update set value = excluded.value;
end;
$$;

create or replace function public.secrets_status(p_game integer)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when private.can_see(p_game) then jsonb_build_object(
    'discord_webhook', exists (select 1 from private.game_secrets where game_id = p_game and key = 'discord_webhook'),
    'open_cloud_key', exists (select 1 from private.game_secrets where game_id = p_game and key = 'open_cloud_key'),
    'discord_public_key', exists (select 1 from private.secrets where key = 'discord_public_key'),
    'game_key', exists (select 1 from private.game_keys where game_id = p_game)
  ) else '{}'::jsonb end;
$$;

-- ===== undo what a cheater gained =====
-- everything they got since they started cheating (first flag in the last week), or since p_since
create or replace function private.queue_revert(g integer, uid bigint, p_since timestamptz, who text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  since timestamptz := p_since;
  summary jsonb;
  n integer;
  new_id bigint;
begin
  if since is null then
    select min(created_at) into since from public.flags
    where game_id = g and user_id = uid and created_at > now() - interval '7 days';
    since := coalesce(since, now() - interval '1 day') - interval '10 minutes';
  end if;

  select count(*) into n from public.ledger
  where game_id = g and user_id = uid and created_at >= since and not withheld;

  with l as (
    select * from public.ledger
    where game_id = g and user_id = uid and created_at >= since and not withheld
  )
  select jsonb_build_object(
    'currency', coalesce((
      select jsonb_object_agg(key, total) from (
        select key, sum(amount) total from l where kind = 'currency' group by key having sum(amount) <> 0
      ) c), '{}'::jsonb),
    'items', coalesce((
      select jsonb_object_agg(key, total) from (
        select key, sum(amount) total from l where kind = 'item' group by key having sum(amount) <> 0
      ) i), '{}'::jsonb),
    'kills', coalesce((select sum(amount) from l where kind = 'kill'), 0),
    -- who they took things from, so the game can give it back
    'victims', coalesce((
      select jsonb_object_agg(v.victim::text, jsonb_strip_nulls(jsonb_build_object(
        'kills', nullif(v.kills, 0),
        'currency', (select jsonb_object_agg(key, s) from (
            select key, sum(amount) s from l where victim = v.victim and kind = 'currency' group by key) x),
        'items', (select jsonb_object_agg(key, s) from (
            select key, sum(amount) s from l where victim = v.victim and kind = 'item' group by key) y)
      )))
      from (
        select victim, sum(amount) filter (where kind = 'kill') kills
        from l where victim is not null group by victim order by 2 desc nulls last limit 200
      ) v), '{}'::jsonb)
  ) into summary;

  -- one open undo per player is enough, the newest one covers everything
  update public.reverts set status = 'failed', result = 'replaced by a newer undo'
  where game_id = g and user_id = uid and status in ('pending', 'sent');

  insert into public.reverts (game_id, user_id, since, summary, status, created_by, result)
  values (g, uid, since, summary, case when n = 0 then 'empty' else 'pending' end, who,
          case when n = 0 then 'nothing recorded to undo' end)
  returning id into new_id;

  if n > 0 then
    insert into public.actions (game_id, user_id, action, reason, actor)
    values (g, uid, 'revert', format('undoing %s gains since %s', n, to_char(since, 'YYYY-MM-DD HH24:MI')), who);
  end if;
  return new_id;
end;
$$;

create or replace function public.admin_revert(p_game integer, p_user_id bigint, p_hours integer)
returns bigint language plpgsql security definer set search_path = '' as $$
begin
  perform private.gate(p_game);
  if p_hours is not null and (p_hours < 1 or p_hours > 720) then raise exception 'pick 1 to 720 hours'; end if;
  return private.queue_revert(p_game, p_user_id,
    case when p_hours is null then null else now() - make_interval(hours => p_hours) end,
    private.actor_name());
end;
$$;

-- ===== reports =====
create or replace function private.close_reports(g integer, uid bigint, confirmed boolean, who text)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  with closed as (
    update public.reports set status = case when confirmed then 'confirmed' else 'dismissed' end,
      decided_by = who, decided_at = now()
    where game_id = g and target_id = uid and status = 'open'
    returning reporter_id
  ), per as (
    select reporter_id, count(*)::int c from closed group by reporter_id
  )
  update public.players p set
    reports_confirmed = p.reports_confirmed + case when confirmed then per.c else 0 end,
    reports_dismissed = p.reports_dismissed + case when confirmed then 0 else per.c end
  from per where p.game_id = g and p.user_id = per.reporter_id;
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.admin_decide_reports(p_game integer, p_target bigint, p_confirm boolean)
returns integer language plpgsql security definer set search_path = '' as $$
begin
  perform private.gate(p_game);
  return private.close_reports(p_game, p_target, p_confirm, private.actor_name());
end;
$$;

-- ===== bans =====
create or replace function public.admin_ban(p_game integer, p_user_id bigint, p_reason text, p_hours integer default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  who text;
  revert_on boolean;
begin
  perform private.gate(p_game);
  if p_user_id is null or p_user_id <= 0 then raise exception 'bad user id'; end if;
  if p_hours is not null and (p_hours < 1 or p_hours > 87600) then raise exception 'bad duration'; end if;
  who := private.actor_name();
  insert into public.bans (game_id, user_id, reason, active, banned_by, expires_at, updated_at, roblox_synced)
  values (p_game, p_user_id, left(coalesce(p_reason, ''), 200), true, who,
          case when p_hours is null then null else now() + make_interval(hours => p_hours) end,
          now(), false)
  on conflict (game_id, user_id) do update set
    reason = excluded.reason, active = true, banned_by = excluded.banned_by,
    expires_at = excluded.expires_at, updated_at = now(), roblox_synced = false;
  insert into public.actions (game_id, user_id, action, reason, actor)
  values (p_game, p_user_id, 'ban', left(coalesce(p_reason, ''), 200), who);

  perform private.close_reports(p_game, p_user_id, true, who);
  select coalesce((features ->> 'RevertGains')::boolean, true) into revert_on from public.config where game_id = p_game;
  if revert_on then
    perform private.queue_revert(p_game, p_user_id, null, who);
  end if;
end;
$$;

create or replace function public.admin_unban(p_game integer, p_user_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  who text;
begin
  perform private.gate(p_game);
  who := private.actor_name();
  update public.bans set active = false, updated_at = now(), roblox_synced = false
  where game_id = p_game and user_id = p_user_id and active;
  if found then
    insert into public.actions (game_id, user_id, action, reason, actor) values (p_game, p_user_id, 'unban', '', who);
    -- an undo that hasn't run yet shouldn't punish someone we just cleared
    update public.reverts set status = 'failed', result = 'cancelled by unban'
    where game_id = p_game and user_id = p_user_id and status in ('pending', 'sent');
  end if;
end;
$$;

-- ===== shadow mode =====
create or replace function public.admin_set_shadow(p_game integer, p_user_id bigint, p_on boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  who text;
begin
  perform private.gate(p_game);
  if p_user_id is null or p_user_id <= 0 then raise exception 'bad user id'; end if;
  who := private.actor_name();
  insert into public.players (game_id, user_id, shadowed, shadow_by, shadowed_at)
  values (p_game, p_user_id, p_on, case when p_on then who end, case when p_on then now() end)
  on conflict (game_id, user_id) do update set
    shadowed = p_on,
    shadow_by = case when p_on then who end,
    shadowed_at = case when p_on then now() end;
  -- live servers flip it within a pulse, everyone else gets it on join
  update public.commands set status = 'expired'
  where game_id = p_game and target_user = p_user_id and kind in ('shadow', 'unshadow') and status in ('pending', 'sent');
  insert into public.commands (game_id, kind, target_user, created_by)
  values (p_game, case when p_on then 'shadow' else 'unshadow' end, p_user_id, who);
  insert into public.actions (game_id, user_id, action, reason, actor)
  values (p_game, p_user_id, case when p_on then 'shadow' else 'unshadow' end, '', who);
end;
$$;

-- ===== dashboard commands =====
create or replace function public.admin_command(p_game integer, p_kind text, p_target bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  me bigint;
  new_id bigint;
begin
  perform private.gate(p_game);
  if p_kind not in ('spectate', 'replay', 'kick') then raise exception 'bad command'; end if;
  if p_target is null or p_target <= 0 then raise exception 'bad user id'; end if;
  if p_kind = 'spectate' then
    select roblox_id into me from public.dashboard_users where user_id = (select auth.uid());
    if me is null then raise exception 'set your roblox id in settings first'; end if;
    update public.commands set status = 'expired'
    where kind = 'spectate' and admin_user = me and status in ('pending', 'sent');
  end if;
  insert into public.commands (game_id, kind, target_user, admin_user, created_by)
  values (p_game, p_kind, p_target, me, private.actor_name())
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function private.take_commands(g integer, p_ids bigint[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  out_cmds jsonb;
begin
  with picked as (
    update public.commands c set status = 'sent'
    where c.game_id = g
      and c.status in ('pending', 'sent')
      and c.created_at > now() - interval '5 minutes'
      and ((c.kind = 'spectate' and c.admin_user = any(p_ids))
        or (c.kind <> 'spectate' and c.target_user = any(p_ids)))
    returning c.id, c.kind, c.target_user, c.admin_user
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'kind', p.kind, 'target', p.target_user::text, 'admin', p.admin_user::text,
    'server', pl.last_server)), '[]'::jsonb)
  into out_cmds
  from picked p left join public.players pl on pl.game_id = g and pl.user_id = p.target_user;
  return out_cmds;
end;
$$;

create or replace function private.ack_commands(g integer, p jsonb) returns void
language sql security definer set search_path = '' as $$
  update public.commands c set
    status = case when (a ->> 'ok')::boolean then 'done' else 'failed' end,
    result = left(a ->> 'result', 200),
    done_at = now()
  from jsonb_array_elements(coalesce(p, '[]'::jsonb)) a
  where c.game_id = g and c.id = (a ->> 'id')::bigint and c.status = 'sent';
$$;

-- ===== alt detection, inside one game =====
create or replace function private.alt_check(g integer, p_user bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  fp real[];
  mu float8[];
  sd float8[];
  n integer;
  best_d float8;
  best_id bigint;
  d float8;
  r record;
  i integer;
  my_sig text[];
  overlap float8;
begin
  select fingerprint into fp from public.players where game_id = g and user_id = p_user;
  if fp is null or array_length(fp, 1) <> 8 then return; end if;

  select count(*) into n from public.players
  where game_id = g and array_length(fingerprint, 1) = 8 and last_seen > now() - interval '30 days';
  if n < 20 then return; end if;

  select array_agg(m order by idx), array_agg(s order by idx) into mu, sd from (
    select gs.idx, avg(p.fingerprint[gs.idx]) m, greatest(stddev_pop(p.fingerprint[gs.idx]), 1e-6) s
    from public.players p cross join generate_series(1, 8) as gs(idx)
    where p.game_id = g and array_length(p.fingerprint, 1) = 8 and p.last_seen > now() - interval '30 days'
    group by gs.idx
  ) t;

  select array_agg(distinct s) into my_sig
  from public.actions a cross join unnest(a.signature) s
  where a.game_id = g and a.user_id = p_user and a.action = 'kick';

  for r in
    select pl.user_id, pl.fingerprint from public.bans b
    join public.players pl on pl.game_id = b.game_id and pl.user_id = b.user_id
    where b.game_id = g and b.active and array_length(pl.fingerprint, 1) = 8 and pl.user_id <> p_user
  loop
    d := 0;
    for i in 1..8 loop
      d := d + (((fp[i] - mu[i]) / sd[i]) - ((r.fingerprint[i] - mu[i]) / sd[i])) ^ 2;
    end loop;
    d := sqrt(d);
    if my_sig is not null then
      select count(*)::float8 / greatest(cardinality(my_sig), 1) into overlap
      from (
        select distinct s from public.actions a cross join unnest(a.signature) s
        where a.game_id = g and a.user_id = r.user_id and a.action = 'kick'
      ) t where t.s = any(my_sig);
      if overlap >= 0.6 then d := d * 0.6; end if;
    end if;
    if best_d is null or d < best_d then
      best_d := d;
      best_id := r.user_id;
    end if;
  end loop;

  if best_d is not null and best_d < 1.2 then
    update public.players set alt_of = best_id, alt_score = round((1 - best_d / 4)::numeric, 3)
    where game_id = g and user_id = p_user;
  else
    update public.players set alt_of = null, alt_score = null
    where game_id = g and user_id = p_user and alt_of is not null;
  end if;
end;
$$;

-- ===== game server sync =====
create or replace function public.game_ingest(p_game integer, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  g integer := p_game;
  srv text := left(coalesce(p ->> 'server', ''), 64);
  place bigint := nullif(p ->> 'place', '')::bigint;
  since timestamptz := coalesce((p ->> 'since')::timestamptz, now() - interval '1 day');
  ids bigint[];
  out_bans jsonb;
  out_cfg jsonb;
  out_reverts jsonb;
  new_reports jsonb;
  alt_on boolean;
  r record;
begin
  insert into public.players (game_id, user_id)
  select g, u from (
    select (x ->> 'id')::bigint u from jsonb_array_elements(p -> 'flags') x
    union select (x ->> 'id')::bigint from jsonb_array_elements(p -> 'kicks') x
    union select (x ->> 'target')::bigint from jsonb_array_elements(p -> 'reports') x
    union select (x ->> 'reporter')::bigint from jsonb_array_elements(p -> 'reports') x
  ) s where u is not null
  on conflict (game_id, user_id) do nothing;

  insert into public.players (game_id, user_id, username, trust_score, peak_score, last_server, last_seen,
                              fingerprint, account_age, on_island)
  select g, (x ->> 'id')::bigint, left(x ->> 'name', 32), (x ->> 'score')::real, (x ->> 'peak')::real,
         srv, now(),
         case when jsonb_typeof(x -> 'fp') = 'array'
           then (select array_agg(v::real) from jsonb_array_elements_text(x -> 'fp') v) end,
         nullif(x ->> 'age', '')::integer,
         coalesce((p ->> 'island')::boolean, false)
  from jsonb_array_elements(p -> 'players') x
  on conflict (game_id, user_id) do update set
    username = excluded.username,
    trust_score = excluded.trust_score,
    peak_score = greatest(public.players.peak_score, excluded.peak_score),
    last_server = excluded.last_server,
    last_seen = now(),
    fingerprint = coalesce(excluded.fingerprint, public.players.fingerprint),
    account_age = coalesce(excluded.account_age, public.players.account_age),
    on_island = excluded.on_island;

  with ins as (
    insert into public.flags (game_id, user_id, server_id, check_name, severity, raw, score_after, hits, context,
                              place_id, pos_x, pos_y, pos_z)
    select g, (x ->> 'id')::bigint, srv, left(x ->> 'check', 24), (x ->> 'sev')::real,
           nullif(x ->> 'raw', '')::real, (x ->> 'score')::real, (x ->> 'hits')::int,
           coalesce(x -> 'ctx', '{}'::jsonb), place,
           (x -> 'pos' ->> 0)::real, (x -> 'pos' ->> 1)::real, (x -> 'pos' ->> 2)::real
    from jsonb_array_elements(p -> 'flags') x
    returning user_id, hits
  )
  update public.players pl set total_flags = pl.total_flags + c.n
  from (select user_id, sum(hits)::int n from ins group by user_id) c
  where pl.game_id = g and pl.user_id = c.user_id;

  with k as (
    insert into public.actions (game_id, user_id, action, reason, actor, replay_id, signature)
    select g, (x ->> 'id')::bigint, 'kick', left(x ->> 'reason', 200), 'anticheat',
           nullif(x ->> 'replay', '')::bigint,
           case when jsonb_typeof(x -> 'sig') = 'array'
             then (select array_agg(left(v, 40)) from jsonb_array_elements_text(x -> 'sig') v) end
    from jsonb_array_elements(p -> 'kicks') x
    returning user_id
  )
  update public.players pl set kicks = pl.kicks + c.n
  from (select user_id, count(*)::int n from k group by user_id) c
  where pl.game_id = g and pl.user_id = c.user_id;

  -- the server shadowed someone on its own
  with s as (
    select (x ->> 'id')::bigint uid, (x ->> 'on')::boolean on_, left(coalesce(x ->> 'why', ''), 120) why
    from jsonb_array_elements(coalesce(p -> 'shadow', '[]'::jsonb)) x
  ), upd as (
    update public.players pl set shadowed = s.on_,
      shadow_by = case when s.on_ then 'anticheat' end,
      shadowed_at = case when s.on_ then now() end
    from s where pl.game_id = g and pl.user_id = s.uid and pl.shadowed is distinct from s.on_
    returning pl.user_id, s.on_, s.why
  )
  insert into public.actions (game_id, user_id, action, reason, actor)
  select g, user_id, case when on_ then 'shadow' else 'unshadow' end, why, 'anticheat' from upd;

  -- reports: weighted by how often this reporter has been right before
  with rep as (
    select (x ->> 'target')::bigint target, (x ->> 'reporter')::bigint reporter,
           left(x ->> 'reason', 24) reason, left(coalesce(x ->> 'note', ''), 200) note,
           least(greatest(coalesce((x ->> 'w')::real, 1), 0), 1) hint,
           nullif(x ->> 'replay', '')::bigint replay, nullif(x ->> 'score', '')::real score
    from jsonb_array_elements(coalesce(p -> 'reports', '[]'::jsonb)) x
  ), ok as (
    select rep.* from rep
    where rep.target <> rep.reporter
      -- nobody gets more than 20 reports a day into the system
      and (select count(*) from public.reports r2
           where r2.game_id = g and r2.reporter_id = rep.reporter and r2.created_at > now() - interval '1 day') < 20
  ), ins as (
    insert into public.reports (game_id, target_id, reporter_id, reason, note, weight, server_id, replay_id, target_score)
    select g, ok.target, ok.reporter, ok.reason, ok.note,
           round((ok.hint * 2 * (pl.reports_confirmed + 1)::real
                  / (pl.reports_confirmed + pl.reports_dismissed + 2))::numeric, 2),
           srv, ok.replay, ok.score
    from ok join public.players pl on pl.game_id = g and pl.user_id = ok.reporter
    returning target_id, reporter_id
  )
  select coalesce(jsonb_agg(jsonb_build_array(target_id, reporter_id)), '[]'::jsonb) into new_reports from ins;

  -- two statements, a player can be both reported and reporter in the same batch
  update public.players pl set reports_against = pl.reports_against + c.n
  from (select (x ->> 0)::bigint uid, count(*)::int n from jsonb_array_elements(new_reports) x group by 1) c
  where pl.game_id = g and pl.user_id = c.uid;
  update public.players pl set reports_made = pl.reports_made + c.n
  from (select (x ->> 1)::bigint uid, count(*)::int n from jsonb_array_elements(new_reports) x group by 1) c
  where pl.game_id = g and pl.user_id = c.uid;

  insert into public.ledger (game_id, user_id, kind, key, amount, victim, source, withheld, server_id)
  select g, (x ->> 'id')::bigint, x ->> 'kind', left(x ->> 'key', 40), (x ->> 'amount')::real,
         nullif(x ->> 'victim', '')::bigint, left(coalesce(x ->> 'source', ''), 40),
         coalesce((x ->> 'withheld')::boolean, false), srv
  from jsonb_array_elements(coalesce(p -> 'ledger', '[]'::jsonb)) x
  where x ->> 'kind' in ('currency', 'item', 'kill');

  update public.reverts rv set
    status = case when (a ->> 'ok')::boolean then 'done' else 'failed' end,
    result = left(a ->> 'result', 200), done_at = now()
  from jsonb_array_elements(coalesce(p -> 'revertAcks', '[]'::jsonb)) a
  where rv.game_id = g and rv.id = (a ->> 'id')::bigint and rv.status = 'sent';

  update public.bans b set roblox_synced = true
  from jsonb_array_elements(p -> 'acks') a
  where b.game_id = g and b.user_id = (a ->> 'id')::bigint and b.active = (a ->> 'active')::boolean;

  perform private.ack_commands(g, p -> 'cmdAcks');

  select coalesce((features ->> 'AltDetection')::boolean, true) into alt_on from public.config where game_id = g;
  if alt_on and exists (select 1 from public.bans where game_id = g and active) then
    for r in
      select (x ->> 'id')::bigint uid from jsonb_array_elements(p -> 'players') x
      where jsonb_typeof(x -> 'fp') = 'array' and coalesce((x ->> 'age')::int, 9999) < 30
      limit 20
    loop
      perform private.alt_check(g, r.uid);
    end loop;
  end if;

  select array_agg((x ->> 'id')::bigint) into ids from jsonb_array_elements(p -> 'players') x;

  if srv <> '' then
    insert into public.servers (server_id, game_id, place_id, players, threat, island, last_seen)
    values (srv, g, place, coalesce(cardinality(ids), 0), coalesce((p ->> 'threat')::smallint, 0),
            coalesce((p ->> 'island')::boolean, false), now())
    on conflict (server_id) do update set
      game_id = excluded.game_id, place_id = excluded.place_id, players = excluded.players,
      threat = excluded.threat, island = excluded.island, last_seen = now();
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', user_id::text,
      'active', active and (expires_at is null or expires_at > now()),
      'reason', reason,
      'expires', extract(epoch from expires_at),
      'synced', roblox_synced)), '[]'::jsonb)
  into out_bans
  from (
    select * from public.bans
    where game_id = g and (updated_at > since or not roblox_synced)
    order by updated_at
    limit 500
  ) b;

  -- undo jobs go to whichever server asks first. a server that died mid-job gets it retried after 2 minutes
  with picked as (
    update public.reverts rv set status = 'sent', sent_at = now()
    where rv.id in (
      select id from public.reverts
      where game_id = g and created_at > now() - interval '7 days'
        and (status = 'pending' or (status = 'sent' and sent_at < now() - interval '2 minutes'))
      order by created_at limit 3
      for update skip locked
    )
    returning rv.id, rv.user_id, rv.summary
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'user', user_id::text, 'summary', summary)), '[]'::jsonb)
  into out_reverts from picked;

  select jsonb_build_object('version', version, 'thresholds', thresholds, 'features', features)
  into out_cfg from public.config where game_id = g;

  return jsonb_build_object(
    'bans', out_bans,
    'config', out_cfg,
    'commands', private.take_commands(g, coalesce(ids, '{}')),
    'reverts', out_reverts,
    'now', now()
  );
end;
$$;

create or replace function public.game_pulse(p_game integer, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  srv text := left(coalesce(p ->> 'server', ''), 64);
  ids bigint[];
begin
  select array_agg((x ->> 'id')::bigint) into ids from jsonb_array_elements(p -> 'players') x;
  perform private.ack_commands(p_game, p -> 'cmdAcks');
  if srv <> '' then
    insert into public.servers (server_id, game_id, place_id, players, threat, island, last_seen)
    values (srv, p_game, nullif(p ->> 'place', '')::bigint, coalesce(cardinality(ids), 0),
            coalesce((p ->> 'threat')::smallint, 0), coalesce((p ->> 'island')::boolean, false), now())
    on conflict (server_id) do update set
      game_id = excluded.game_id, place_id = excluded.place_id, players = excluded.players,
      threat = excluded.threat, island = excluded.island, last_seen = now();
  end if;
  return jsonb_build_object('commands', private.take_commands(p_game, coalesce(ids, '{}')));
end;
$$;

-- ban check on join, plus what follows the player between servers: suspicion, shadow mode,
-- and "someone you reported got banned"
create or replace function public.game_join(p_game integer, p_user_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  b record;
  pl record;
  carry_on boolean;
  thanks integer;
begin
  select * into b from public.bans
  where game_id = p_game and user_id = p_user_id and active and (expires_at is null or expires_at > now());
  select * into pl from public.players where game_id = p_game and user_id = p_user_id;
  select coalesce((features ->> 'CrossServerTrust')::boolean, true) into carry_on from public.config where game_id = p_game;

  with n as (
    update public.reports set notified = true
    where game_id = p_game and reporter_id = p_user_id and status = 'confirmed' and not notified
    returning 1
  )
  select count(*) into thanks from n;

  return jsonb_build_object(
    'banned', b.user_id is not null,
    'reason', b.reason,
    'expires', extract(epoch from b.expires_at),
    'carry', case when pl.user_id is not null and carry_on
      then jsonb_build_object('score', pl.trust_score, 'away', extract(epoch from now() - pl.last_seen)) end,
    'shadow', coalesce(pl.shadowed, false),
    'shadowBy', pl.shadow_by,
    'thanks', thanks
  );
end;
$$;

create or replace function public.game_replay(p_game integer, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  new_id bigint;
  new_token text;
begin
  insert into public.replays (game_id, user_id, server_id, place_id, map_version, kind, reason, meta, samples, events)
  values (p_game, (p ->> 'user')::bigint, left(p ->> 'server', 64), nullif(p ->> 'place', '')::bigint,
          left(p ->> 'mapVersion', 64), p ->> 'kind', left(coalesce(p ->> 'reason', ''), 200),
          coalesce(p -> 'meta', '{}'::jsonb), p -> 'samples', p -> 'events')
  returning id, token into new_id, new_token;
  return jsonb_build_object('id', new_id, 'token', new_token);
end;
$$;

create or replace function public.game_map_check(p_game integer, p_place bigint, p_version text, p_total integer, p_bounds jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  m record;
begin
  select * into m from public.maps where place_id = p_place and version = p_version;
  -- another game's place, leave it alone
  if found and m.game_id <> p_game then return false; end if;
  if found and m.received >= m.total then return false; end if;
  if not found then
    insert into public.maps (game_id, place_id, version, total, bounds)
    values (p_game, p_place, left(p_version, 64), p_total, p_bounds)
    on conflict do nothing;
  end if;
  return true;
end;
$$;

create or replace function public.game_map_chunk(p_game integer, p_place bigint, p_version text, p_idx integer, p_parts jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.maps where place_id = p_place and version = p_version and game_id = p_game) then
    return;
  end if;
  insert into public.map_chunks (place_id, version, idx, parts) values (p_place, p_version, p_idx, p_parts)
  on conflict (place_id, version, idx) do update set parts = excluded.parts;
  update public.maps set received = (
    select count(*) from public.map_chunks where place_id = p_place and version = p_version
  ) where place_id = p_place and version = p_version;
end;
$$;

-- ===== appeals =====
create or replace function public.submit_appeal(p_user text, p_message text, p_game integer default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  target bigint;
  g integer := p_game;
  uname text;
  recent integer;
  dname text;
  new_id bigint;
begin
  if uid is null then raise exception 'sign in first'; end if;
  p_message := trim(coalesce(p_message, ''));
  if length(p_message) < 10 then raise exception 'write a little more about what happened'; end if;
  if length(p_message) > 1500 then raise exception 'keep it under 1500 characters'; end if;
  p_user := trim(coalesce(p_user, ''));

  if p_user ~ '^[0-9]{1,19}$' then
    target := p_user::bigint;
  else
    select user_id into target from public.players
    where lower(username) = lower(p_user) order by last_seen desc limit 1;
  end if;
  if target is null then raise exception 'could not find that player'; end if;

  -- no game given: the game they were most recently banned from
  if g is null then
    select game_id into g from public.bans where user_id = target and active order by updated_at desc limit 1;
  end if;
  if g is null or not exists (select 1 from public.bans where game_id = g and user_id = target and active) then
    raise exception 'that account is not banned';
  end if;
  if exists (select 1 from public.appeals where game_id = g and user_id = target and status = 'open') then
    raise exception 'there is already an open appeal for that account';
  end if;

  select count(*) into recent from public.appeals where discord_user = uid and created_at > now() - interval '1 day';
  if recent >= 3 then raise exception 'too many appeals today, try tomorrow'; end if;

  select username into uname from public.players where game_id = g and user_id = target;
  select username into dname from public.dashboard_users where user_id = uid;

  insert into public.appeals (game_id, user_id, username, message, discord_user, discord_name)
  values (g, target, coalesce(uname, ''), p_message, uid, coalesce(dname, ''))
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.my_appeals()
returns table (id bigint, user_id bigint, username text, game text, status text, note text,
               created_at timestamptz, decided_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select a.id, a.user_id, a.username, gm.name, a.status, a.note, a.created_at, a.decided_at
  from public.appeals a join public.games gm on gm.id = a.game_id
  where a.discord_user = (select auth.uid())
  order by a.created_at desc limit 20;
$$;

create or replace function public.decide_appeal(p_id bigint, p_approve boolean, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  who text;
  target bigint;
  g integer;
begin
  select game_id into g from public.appeals where id = p_id;
  perform private.gate(g);
  who := private.actor_name();
  update public.appeals set
    status = case when p_approve then 'approved' else 'denied' end,
    note = left(coalesce(p_note, ''), 500), decided_by = who, decided_at = now()
  where id = p_id and status = 'open'
  returning user_id into target;
  if target is null then raise exception 'appeal not found or already decided'; end if;
  if p_approve then
    update public.bans set active = false, updated_at = now(), roblox_synced = false
    where game_id = g and user_id = target and active;
    insert into public.actions (game_id, user_id, action, reason, actor) values (g, target, 'unban', 'appeal approved', who);
    update public.reverts set status = 'failed', result = 'cancelled, appeal approved'
    where game_id = g and user_id = target and status in ('pending', 'sent');
  end if;
end;
$$;

-- ===== learning loop, per game =====
create or replace function public.tuning_suggestions(p_game integer)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  thr jsonb;
  labeled integer;
  result jsonb := '[]'::jsonb;
  r record;
  cur float8;
  sug float8;
  legit_peak float8;
  cheat_peak float8;
begin
  perform private.gate(p_game);
  select thresholds into thr from public.config where game_id = p_game;

  create temp table if not exists _labels (user_id bigint primary key, label integer) on commit drop;
  truncate _labels;
  insert into _labels
  select k.user_id,
    case
      when exists (select 1 from public.appeals ap where ap.game_id = p_game and ap.user_id = k.user_id and ap.status = 'approved')
        or exists (select 1 from public.actions a where a.game_id = p_game and a.user_id = k.user_id and a.action = 'unban') then 0
      when exists (select 1 from public.bans b where b.game_id = p_game and b.user_id = k.user_id and b.active) then 1
    end
  from (select distinct user_id from public.actions
        where game_id = p_game and action = 'kick' and created_at > now() - interval '90 days') k;
  delete from _labels where label is null;
  select count(*) into labeled from _labels;

  if labeled >= 5 then
    for r in
      select f.check_name,
        count(distinct f.user_id) filter (where l.label = 1) cheaters,
        count(distinct f.user_id) filter (where l.label = 0) legit
      from public.flags f join _labels l on l.user_id = f.user_id
      where f.game_id = p_game
      group by f.check_name
    loop
      if r.cheaters + r.legit >= 3 then
        cur := coalesce((thr ->> ('Weight' || r.check_name))::float8, 1);
        sug := round(least(3, greatest(0, cur * (0.5 + r.cheaters::float8 / (r.cheaters + r.legit))))::numeric, 2);
        if abs(sug - cur) >= 0.05 then
          result := result || jsonb_build_object(
            'key', 'Weight' || r.check_name, 'current', cur, 'suggested', sug,
            'reason', format('%s of %s kicked players this check flagged turned out to be real cheaters',
                             r.cheaters, r.cheaters + r.legit));
        end if;
      end if;
    end loop;

    select max(pl.peak_score) into legit_peak from _labels l
      join public.players pl on pl.game_id = p_game and pl.user_id = l.user_id where l.label = 0;
    select min(pl.peak_score) into cheat_peak from _labels l
      join public.players pl on pl.game_id = p_game and pl.user_id = l.user_id where l.label = 1;
    cur := coalesce((thr ->> 'KickScore')::float8, 100);
    if legit_peak is not null and (cheat_peak is null or legit_peak * 1.1 < cheat_peak) and legit_peak * 1.1 > cur then
      result := result || jsonb_build_object(
        'key', 'KickScore', 'current', cur, 'suggested', round((legit_peak * 1.1)::numeric),
        'reason', 'wrongly kicked players peaked just above the current kick score, while every confirmed cheater went well past it');
    end if;
  end if;

  return jsonb_build_object('labeled', labeled, 'needed', 5, 'suggestions', result);
end;
$$;

-- ===== instant bans: the notify function publishes into that game's servers =====
create or replace function private.notify_ban() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT'
    or new.active is distinct from old.active
    or (new.active and new.updated_at is distinct from old.updated_at) then
    perform net.http_post(
      url := 'https://kapvjoemzsdqiealluzl.supabase.co/functions/v1/notify',
      body := jsonb_build_object('game', new.game_id, 'id', new.user_id::text, 'active', new.active, 'reason', new.reason),
      headers := jsonb_build_object('Content-Type', 'application/json',
        'x-cron-key', (select value from private.secrets where key = 'cron_key'))
    );
  end if;
  return new;
end;
$$;

-- ===== grants =====
revoke all on function
  public.admin_create_game(text), public.admin_rotate_key(integer), public.admin_update_game(integer, text, bigint, text),
  public.admin_delete_game(integer), public.admin_set_role(uuid, text), public.admin_set_staff(uuid, integer, boolean),
  public.admin_set_thresholds(integer, jsonb), public.admin_set_features(integer, jsonb),
  public.admin_set_webhook(integer, text), public.admin_set_secret(integer, text, text), public.secrets_status(integer),
  public.admin_revert(integer, bigint, integer), public.admin_decide_reports(integer, bigint, boolean),
  public.admin_ban(integer, bigint, text, integer), public.admin_unban(integer, bigint),
  public.admin_set_shadow(integer, bigint, boolean), public.admin_command(integer, text, bigint),
  public.submit_appeal(text, text, integer), public.my_appeals(), public.decide_appeal(bigint, boolean, text),
  public.tuning_suggestions(integer)
  from public, anon;
grant execute on function
  public.admin_create_game(text), public.admin_rotate_key(integer), public.admin_update_game(integer, text, bigint, text),
  public.admin_delete_game(integer), public.admin_set_role(uuid, text), public.admin_set_staff(uuid, integer, boolean),
  public.admin_set_thresholds(integer, jsonb), public.admin_set_features(integer, jsonb),
  public.admin_set_webhook(integer, text), public.admin_set_secret(integer, text, text), public.secrets_status(integer),
  public.admin_revert(integer, bigint, integer), public.admin_decide_reports(integer, bigint, boolean),
  public.admin_ban(integer, bigint, text, integer), public.admin_unban(integer, bigint),
  public.admin_set_shadow(integer, bigint, boolean), public.admin_command(integer, text, bigint),
  public.submit_appeal(text, text, integer), public.my_appeals(), public.decide_appeal(bigint, boolean, text),
  public.tuning_suggestions(integer)
  to authenticated;

revoke all on function public.game_secret(text), public.game_secret_for(integer, text), public.game_auth(text),
  public.game_ingest(integer, jsonb), public.game_pulse(integer, jsonb), public.game_join(integer, bigint),
  public.game_replay(integer, jsonb), public.game_map_check(integer, bigint, text, integer, jsonb),
  public.game_map_chunk(integer, bigint, text, integer, jsonb)
  from public, anon, authenticated;
grant execute on function public.game_secret(text), public.game_secret_for(integer, text), public.game_auth(text),
  public.game_ingest(integer, jsonb), public.game_pulse(integer, jsonb), public.game_join(integer, bigint),
  public.game_replay(integer, jsonb), public.game_map_check(integer, bigint, text, integer, jsonb),
  public.game_map_chunk(integer, bigint, text, integer, jsonb)
  to service_role;

revoke all on function private.new_key(integer), private.queue_revert(integer, bigint, timestamptz, text),
  private.close_reports(integer, bigint, boolean, text), private.take_commands(integer, bigint[]),
  private.ack_commands(integer, jsonb), private.alt_check(integer, bigint), private.notify_ban()
  from public, anon, authenticated;

-- ===== housekeeping =====
select cron.schedule('ac-housekeeping', '*/5 * * * *', $$
  update public.commands set status = 'expired' where status in ('pending','sent') and created_at < now() - interval '5 minutes';
  update public.reverts set status = 'failed', result = 'no server picked it up for a week'
    where status in ('pending','sent') and created_at < now() - interval '7 days';
  delete from public.servers where last_seen < now() - interval '10 minutes';
  delete from public.replays where created_at < now() - interval '90 days';
  delete from public.commands where created_at < now() - interval '7 days';
  delete from public.ledger where created_at < now() - interval '30 days';
  delete from public.reports where created_at < now() - interval '90 days';
  delete from public.reverts where created_at < now() - interval '90 days';
$$);
