-- ===== secrets the edge functions may read (service role only) =====
create or replace function public.game_secret(p_name text) returns text
language sql stable security definer set search_path = '' as $$
  select value from private.secrets
  where key = p_name and p_name in (
    'game_key_sha256', 'discord_webhook', 'open_cloud_key', 'universe_id',
    'discord_public_key', 'discord_client_id', 'discord_client_secret', 'cron_key'
  );
$$;
revoke all on function public.game_secret(text) from public, anon, authenticated;
grant execute on function public.game_secret(text) to service_role;

insert into private.secrets (key, value) values
  ('cron_key', encode(extensions.gen_random_bytes(32), 'hex')),
  ('universe_id', '10768018896'),
  ('discord_client_id', '1553113119298162788')
on conflict (key) do nothing;

-- ===== feature toggles =====
create or replace function public.admin_set_features(p_features jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  allowed text[] := array[
    'Movement','Character','Timing','Statistical','Combat','Client','NetGuard',
    'Honeypot','TrapVault','BaitNPC','BaitCoin','Replays','MapExport','MissionControl',
    'Spectator','CheaterIsland','AltDetection','GlobalBans','CrossServerTrust'
  ];
  k text;
  v jsonb;
  clean jsonb := '{}'::jsonb;
  new_version integer;
begin
  if not private.is_admin() then raise exception 'not allowed'; end if;
  if jsonb_typeof(p_features) <> 'object' then raise exception 'bad payload'; end if;
  for k, v in select * from jsonb_each(p_features) loop
    if k = any(allowed) and jsonb_typeof(v) = 'boolean' then
      clean := clean || jsonb_build_object(k, v);
    end if;
  end loop;
  update public.config set features = clean, version = version + 1,
    updated_at = now(), updated_by = private.actor_name()
  where id = 1 returning version into new_version;
  return new_version;
end;
$$;

-- ===== owner-managed secrets, write only =====
create or replace function public.admin_set_secret(p_key text, p_value text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() then raise exception 'not allowed'; end if;
  if p_key not in ('open_cloud_key', 'discord_public_key') then raise exception 'unknown setting'; end if;
  if p_value is null or p_value = '' then
    delete from private.secrets where key = p_key;
    return;
  end if;
  if p_key = 'discord_public_key' and p_value !~ '^[0-9a-f]{64}$' then
    raise exception 'that is not a discord public key';
  end if;
  if p_key = 'open_cloud_key' and (length(p_value) < 20 or length(p_value) > 4000 or p_value ~ '\s') then
    raise exception 'that does not look like an open cloud key';
  end if;
  insert into private.secrets (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

create or replace function public.secrets_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when private.is_admin() then jsonb_build_object(
    'discord_webhook', exists (select 1 from private.secrets where key = 'discord_webhook'),
    'open_cloud_key', exists (select 1 from private.secrets where key = 'open_cloud_key'),
    'discord_public_key', exists (select 1 from private.secrets where key = 'discord_public_key')
  ) else '{}'::jsonb end;
$$;

create or replace function public.admin_set_my_roblox(p_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then raise exception 'not allowed'; end if;
  if p_id is not null and (p_id <= 0 or p_id > 99999999999) then raise exception 'bad roblox id'; end if;
  update public.dashboard_users set roblox_id = p_id where user_id = (select auth.uid());
end;
$$;

-- ===== commands the dashboard sends into live servers =====
create or replace function public.admin_command(p_kind text, p_target bigint)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  me bigint;
  new_id bigint;
begin
  if not private.is_admin() then raise exception 'not allowed'; end if;
  if p_kind not in ('spectate', 'replay', 'kick') then raise exception 'bad command'; end if;
  if p_target is null or p_target <= 0 then raise exception 'bad user id'; end if;
  if p_kind = 'spectate' then
    select roblox_id into me from public.dashboard_users where user_id = (select auth.uid());
    if me is null then raise exception 'set your roblox id in settings first'; end if;
    update public.commands set status = 'expired'
    where kind = 'spectate' and admin_user = me and status in ('pending', 'sent');
  end if;
  insert into public.commands (kind, target_user, admin_user, created_by)
  values (p_kind, p_target, me, private.actor_name())
  returning id into new_id;
  return new_id;
end;
$$;

-- hands out pending commands for players on the calling server
create or replace function private.take_commands(p_ids bigint[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  out_cmds jsonb;
begin
  with picked as (
    update public.commands c set status = 'sent'
    where c.status in ('pending', 'sent')
      and c.created_at > now() - interval '5 minutes'
      and ((c.kind = 'spectate' and c.admin_user = any(p_ids))
        or (c.kind <> 'spectate' and c.target_user = any(p_ids)))
    returning c.id, c.kind, c.target_user, c.admin_user
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'kind', kind, 'target', target_user::text, 'admin', admin_user::text)), '[]'::jsonb)
  into out_cmds from picked;
  return out_cmds;
end;
$$;

create or replace function private.ack_commands(p jsonb) returns void
language sql security definer set search_path = '' as $$
  update public.commands c set
    status = case when (a ->> 'ok')::boolean then 'done' else 'failed' end,
    result = left(a ->> 'result', 200),
    done_at = now()
  from jsonb_array_elements(coalesce(p, '[]'::jsonb)) a
  where c.id = (a ->> 'id')::bigint and c.status = 'sent';
$$;

-- ===== alt detection: z-scored behaviour distance to banned players =====
create or replace function private.alt_check(p_user bigint) returns void
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
  select fingerprint into fp from public.players where user_id = p_user;
  if fp is null or array_length(fp, 1) <> 8 then return; end if;

  select count(*) into n from public.players
  where array_length(fingerprint, 1) = 8 and last_seen > now() - interval '30 days';
  -- needs a population to know what "normal" looks like
  if n < 20 then return; end if;

  select array_agg(m order by idx), array_agg(s order by idx) into mu, sd from (
    select g.idx, avg(p.fingerprint[g.idx]) m, greatest(stddev_pop(p.fingerprint[g.idx]), 1e-6) s
    from public.players p cross join generate_series(1, 8) as g(idx)
    where array_length(p.fingerprint, 1) = 8 and p.last_seen > now() - interval '30 days'
    group by g.idx
  ) t;

  select array_agg(distinct s) into my_sig
  from public.actions a cross join unnest(a.signature) s
  where a.user_id = p_user and a.action = 'kick';

  for r in
    select pl.user_id, pl.fingerprint from public.bans b
    join public.players pl on pl.user_id = b.user_id
    where b.active and array_length(pl.fingerprint, 1) = 8 and pl.user_id <> p_user
  loop
    d := 0;
    for i in 1..8 loop
      d := d + (((fp[i] - mu[i]) / sd[i]) - ((r.fingerprint[i] - mu[i]) / sd[i])) ^ 2;
    end loop;
    d := sqrt(d);
    -- same cheat tool signature pulls them closer
    if my_sig is not null then
      select count(*)::float8 / greatest(cardinality(my_sig), 1) into overlap
      from (
        select distinct s from public.actions a cross join unnest(a.signature) s
        where a.user_id = r.user_id and a.action = 'kick'
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
    where user_id = p_user;
  else
    update public.players set alt_of = null, alt_score = null
    where user_id = p_user and alt_of is not null;
  end if;
end;
$$;

-- ===== game ingest v2 =====
create or replace function public.game_ingest(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  srv text := left(coalesce(p ->> 'server', ''), 64);
  place bigint := nullif(p ->> 'place', '')::bigint;
  since timestamptz := coalesce((p ->> 'since')::timestamptz, now() - interval '1 day');
  ids bigint[];
  out_bans jsonb;
  out_cfg jsonb;
  alt_on boolean;
  r record;
begin
  insert into public.players (user_id)
  select distinct (x ->> 'id')::bigint from jsonb_array_elements(p -> 'flags') x
  union
  select distinct (x ->> 'id')::bigint from jsonb_array_elements(p -> 'kicks') x
  on conflict (user_id) do nothing;

  insert into public.players (user_id, username, trust_score, peak_score, last_server, last_seen,
                              fingerprint, account_age, on_island)
  select (x ->> 'id')::bigint, left(x ->> 'name', 32), (x ->> 'score')::real, (x ->> 'peak')::real,
         srv, now(),
         case when jsonb_typeof(x -> 'fp') = 'array'
           then (select array_agg(v::real) from jsonb_array_elements_text(x -> 'fp') v) end,
         nullif(x ->> 'age', '')::integer,
         coalesce((p ->> 'island')::boolean, false)
  from jsonb_array_elements(p -> 'players') x
  on conflict (user_id) do update set
    username = excluded.username,
    trust_score = excluded.trust_score,
    peak_score = greatest(public.players.peak_score, excluded.peak_score),
    last_server = excluded.last_server,
    last_seen = now(),
    fingerprint = coalesce(excluded.fingerprint, public.players.fingerprint),
    account_age = coalesce(excluded.account_age, public.players.account_age),
    on_island = excluded.on_island;

  with ins as (
    insert into public.flags (user_id, server_id, check_name, severity, raw, score_after, hits, context,
                              place_id, pos_x, pos_y, pos_z)
    select (x ->> 'id')::bigint, srv, left(x ->> 'check', 24), (x ->> 'sev')::real,
           nullif(x ->> 'raw', '')::real, (x ->> 'score')::real, (x ->> 'hits')::int,
           coalesce(x -> 'ctx', '{}'::jsonb), place,
           (x -> 'pos' ->> 0)::real, (x -> 'pos' ->> 1)::real, (x -> 'pos' ->> 2)::real
    from jsonb_array_elements(p -> 'flags') x
    returning user_id, hits
  )
  update public.players pl set total_flags = pl.total_flags + c.n
  from (select user_id, sum(hits)::int n from ins group by user_id) c
  where pl.user_id = c.user_id;

  with k as (
    insert into public.actions (user_id, action, reason, actor, replay_id, signature)
    select (x ->> 'id')::bigint, 'kick', left(x ->> 'reason', 200), 'anticheat',
           nullif(x ->> 'replay', '')::bigint,
           case when jsonb_typeof(x -> 'sig') = 'array'
             then (select array_agg(left(v, 40)) from jsonb_array_elements_text(x -> 'sig') v) end
    from jsonb_array_elements(p -> 'kicks') x
    returning user_id
  )
  update public.players pl set kicks = pl.kicks + c.n
  from (select user_id, count(*)::int n from k group by user_id) c
  where pl.user_id = c.user_id;

  update public.bans b set roblox_synced = true
  from jsonb_array_elements(p -> 'acks') a
  where b.user_id = (a ->> 'id')::bigint and b.active = (a ->> 'active')::boolean;

  perform private.ack_commands(p -> 'cmdAcks');

  select coalesce((features ->> 'AltDetection')::boolean, true) into alt_on from public.config where id = 1;
  if alt_on and exists (select 1 from public.bans where active) then
    for r in
      select (x ->> 'id')::bigint uid from jsonb_array_elements(p -> 'players') x
      where jsonb_typeof(x -> 'fp') = 'array' and coalesce((x ->> 'age')::int, 9999) < 30
      limit 20
    loop
      perform private.alt_check(r.uid);
    end loop;
  end if;

  select array_agg((x ->> 'id')::bigint) into ids from jsonb_array_elements(p -> 'players') x;

  if srv <> '' then
    insert into public.servers (server_id, place_id, players, threat, island, last_seen)
    values (srv, place, coalesce(cardinality(ids), 0), coalesce((p ->> 'threat')::smallint, 0),
            coalesce((p ->> 'island')::boolean, false), now())
    on conflict (server_id) do update set
      place_id = excluded.place_id, players = excluded.players, threat = excluded.threat,
      island = excluded.island, last_seen = now();
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
    where updated_at > since or not roblox_synced
    order by updated_at
    limit 500
  ) b;

  select jsonb_build_object('version', version, 'thresholds', thresholds, 'features', features)
  into out_cfg from public.config where id = 1;

  return jsonb_build_object(
    'bans', out_bans,
    'config', out_cfg,
    'commands', private.take_commands(coalesce(ids, '{}')),
    'now', now()
  );
end;
$$;

-- ===== live pulse, every few seconds =====
create or replace function public.game_pulse(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  srv text := left(coalesce(p ->> 'server', ''), 64);
  ids bigint[];
begin
  select array_agg((x ->> 'id')::bigint) into ids from jsonb_array_elements(p -> 'players') x;
  perform private.ack_commands(p -> 'cmdAcks');
  if srv <> '' then
    insert into public.servers (server_id, place_id, players, threat, island, last_seen)
    values (srv, nullif(p ->> 'place', '')::bigint, coalesce(cardinality(ids), 0),
            coalesce((p ->> 'threat')::smallint, 0), coalesce((p ->> 'island')::boolean, false), now())
    on conflict (server_id) do update set
      place_id = excluded.place_id, players = excluded.players, threat = excluded.threat,
      island = excluded.island, last_seen = now();
  end if;
  return jsonb_build_object('commands', private.take_commands(coalesce(ids, '{}')));
end;
$$;

create or replace function public.game_join(p_user_id bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'banned', b.user_id is not null,
    'reason', b.reason,
    'expires', extract(epoch from b.expires_at),
    'carry', case when pl.user_id is not null and coalesce((c.features ->> 'CrossServerTrust')::boolean, true)
      then jsonb_build_object('score', pl.trust_score, 'away', extract(epoch from now() - pl.last_seen))
    end
  )
  from (select 1) one
  left join public.bans b on b.user_id = p_user_id and b.active and (b.expires_at is null or b.expires_at > now())
  left join public.players pl on pl.user_id = p_user_id
  left join public.config c on c.id = 1;
$$;

create or replace function public.game_replay(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  new_id bigint;
  new_token text;
begin
  insert into public.replays (user_id, server_id, place_id, map_version, kind, reason, meta, samples, events)
  values ((p ->> 'user')::bigint, left(p ->> 'server', 64), nullif(p ->> 'place', '')::bigint,
          left(p ->> 'mapVersion', 64), p ->> 'kind', left(coalesce(p ->> 'reason', ''), 200),
          coalesce(p -> 'meta', '{}'::jsonb), p -> 'samples', p -> 'events')
  returning id, token into new_id, new_token;
  return jsonb_build_object('id', new_id, 'token', new_token);
end;
$$;

create or replace function public.game_map_check(p_place bigint, p_version text, p_total integer, p_bounds jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  m record;
begin
  select * into m from public.maps where place_id = p_place and version = p_version;
  if found and m.received >= m.total then return false; end if;
  if not found then
    insert into public.maps (place_id, version, total, bounds) values (p_place, left(p_version, 64), p_total, p_bounds)
    on conflict do nothing;
  end if;
  return true;
end;
$$;

create or replace function public.game_map_chunk(p_place bigint, p_version text, p_idx integer, p_parts jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.map_chunks (place_id, version, idx, parts) values (p_place, p_version, p_idx, p_parts)
  on conflict (place_id, version, idx) do update set parts = excluded.parts;
  update public.maps set received = (
    select count(*) from public.map_chunks where place_id = p_place and version = p_version
  ) where place_id = p_place and version = p_version;
end;
$$;

-- ===== appeals =====
create or replace function public.submit_appeal(p_user text, p_message text)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := (select auth.uid());
  target bigint;
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
  if not exists (select 1 from public.bans where user_id = target and active) then
    raise exception 'that account is not banned';
  end if;
  if exists (select 1 from public.appeals where user_id = target and status = 'open') then
    raise exception 'there is already an open appeal for that account';
  end if;

  select count(*) into recent from public.appeals where discord_user = uid and created_at > now() - interval '1 day';
  if recent >= 3 then raise exception 'too many appeals today, try tomorrow'; end if;

  select username into uname from public.players where user_id = target;
  select username into dname from public.dashboard_users where user_id = uid;

  insert into public.appeals (user_id, username, message, discord_user, discord_name)
  values (target, coalesce(uname, ''), p_message, uid, coalesce(dname, ''))
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.my_appeals()
returns table (id bigint, user_id bigint, username text, status text, note text, created_at timestamptz, decided_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select a.id, a.user_id, a.username, a.status, a.note, a.created_at, a.decided_at
  from public.appeals a where a.discord_user = (select auth.uid())
  order by a.created_at desc limit 20;
$$;

create or replace function public.decide_appeal(p_id bigint, p_approve boolean, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  who text;
  target bigint;
begin
  if not private.is_admin() then raise exception 'not allowed'; end if;
  who := private.actor_name();
  update public.appeals set
    status = case when p_approve then 'approved' else 'denied' end,
    note = left(coalesce(p_note, ''), 500), decided_by = who, decided_at = now()
  where id = p_id and status = 'open'
  returning user_id into target;
  if target is null then raise exception 'appeal not found or already decided'; end if;
  if p_approve then
    update public.bans set active = false, updated_at = now(), roblox_synced = false
    where user_id = target and active;
    insert into public.actions (user_id, action, reason, actor) values (target, 'unban', 'appeal approved', who);
  end if;
end;
$$;

-- ===== learning loop: what your ban/unban decisions say about each check =====
-- volatile, it builds a temp table
create or replace function public.tuning_suggestions()
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
  if not private.is_admin() then raise exception 'not allowed'; end if;
  select thresholds into thr from public.config where id = 1;

  create temp table if not exists _labels (user_id bigint primary key, label integer) on commit drop;
  truncate _labels;
  insert into _labels
  select k.user_id,
    case
      when exists (select 1 from public.appeals ap where ap.user_id = k.user_id and ap.status = 'approved')
        or exists (select 1 from public.actions a where a.user_id = k.user_id and a.action = 'unban') then 0
      when exists (select 1 from public.bans b where b.user_id = k.user_id and b.active) then 1
    end
  from (select distinct user_id from public.actions where action = 'kick' and created_at > now() - interval '90 days') k;
  delete from _labels where label is null;
  select count(*) into labeled from _labels;

  if labeled >= 5 then
    for r in
      select f.check_name,
        count(distinct f.user_id) filter (where l.label = 1) cheaters,
        count(distinct f.user_id) filter (where l.label = 0) legit
      from public.flags f join _labels l on l.user_id = f.user_id
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

    select max(pl.peak_score) into legit_peak from _labels l join public.players pl using (user_id) where l.label = 0;
    select min(pl.peak_score) into cheat_peak from _labels l join public.players pl using (user_id) where l.label = 1;
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

-- ===== instant global bans: tell the notify function, which calls roblox open cloud =====
create or replace function private.notify_ban() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT'
    or new.active is distinct from old.active
    or (new.active and new.updated_at is distinct from old.updated_at) then
    perform net.http_post(
      url := 'https://kapvjoemzsdqiealluzl.supabase.co/functions/v1/notify',
      body := jsonb_build_object('id', new.user_id::text, 'active', new.active, 'reason', new.reason),
      headers := jsonb_build_object('Content-Type', 'application/json',
        'x-cron-key', (select value from private.secrets where key = 'cron_key'))
    );
  end if;
  return new;
end;
$$;
revoke all on function private.notify_ban() from public, anon, authenticated;

create trigger bans_notify after insert or update on public.bans
  for each row execute function private.notify_ban();

-- ===== grants =====
revoke all on function public.admin_set_features(jsonb), public.admin_set_secret(text, text), public.secrets_status(),
  public.admin_set_my_roblox(bigint), public.admin_command(text, bigint), public.submit_appeal(text, text),
  public.my_appeals(), public.decide_appeal(bigint, boolean, text), public.tuning_suggestions()
  from public, anon;
grant execute on function public.admin_set_features(jsonb), public.admin_set_secret(text, text), public.secrets_status(),
  public.admin_set_my_roblox(bigint), public.admin_command(text, bigint), public.submit_appeal(text, text),
  public.my_appeals(), public.decide_appeal(bigint, boolean, text), public.tuning_suggestions()
  to authenticated;

revoke all on function public.game_ingest(jsonb), public.game_pulse(jsonb), public.game_join(bigint),
  public.game_replay(jsonb), public.game_map_check(bigint, text, integer, jsonb),
  public.game_map_chunk(bigint, text, integer, jsonb) from public, anon, authenticated;
grant execute on function public.game_ingest(jsonb), public.game_pulse(jsonb), public.game_join(bigint),
  public.game_replay(jsonb), public.game_map_check(bigint, text, integer, jsonb),
  public.game_map_chunk(bigint, text, integer, jsonb) to service_role;

revoke all on function private.take_commands(bigint[]), private.ack_commands(jsonb), private.alt_check(bigint)
  from public, anon, authenticated;

-- ===== housekeeping + daily report =====
select cron.schedule('ac-housekeeping', '*/5 * * * *', $$
  update public.commands set status = 'expired' where status in ('pending','sent') and created_at < now() - interval '5 minutes';
  delete from public.servers where last_seen < now() - interval '10 minutes';
  delete from public.replays where created_at < now() - interval '90 days';
  delete from public.commands where created_at < now() - interval '7 days';
$$);

-- 06:00 utc is 10:00 in tbilisi
select cron.schedule('ac-daily-report', '0 6 * * *', $$
  select net.http_post(
    url := 'https://kapvjoemzsdqiealluzl.supabase.co/functions/v1/report',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-cron-key', (select value from private.secrets where key = 'cron_key'))
  );
$$);
