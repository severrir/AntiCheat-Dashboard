-- a shadow set from game code (AntiCheat.Shadow) is a staff shadow, not the score's
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
    select (x ->> 'id')::bigint uid, (x ->> 'on')::boolean on_, left(coalesce(x ->> 'why', ''), 120) why,
           x ->> 'by' = 'staff' staff
    from jsonb_array_elements(coalesce(p -> 'shadow', '[]'::jsonb)) x
  ), upd as (
    -- game code shadowing someone counts as staff: no auto-kick, and it stays that way on rejoin
    update public.players pl set shadowed = s.on_,
      shadow_by = case when s.on_ then case when s.staff then 'game code' else 'anticheat' end end,
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
