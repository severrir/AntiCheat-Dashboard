-- service role only. the edge function uses these, nobody else can
create or replace function public.game_secret(p_name text) returns text
language sql stable security definer set search_path = '' as $$
  select value from private.secrets
  where key = p_name and p_name in ('game_key_sha256', 'discord_webhook');
$$;

create or replace function public.game_join(p_user_id bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object('banned', true, 'reason', reason,
       'expires', extract(epoch from expires_at))
     from public.bans
     where user_id = p_user_id and active and (expires_at is null or expires_at > now())),
    jsonb_build_object('banned', false));
$$;

create or replace function public.game_ingest(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  srv text := left(coalesce(p ->> 'server', ''), 64);
  since timestamptz := coalesce((p ->> 'since')::timestamptz, now() - interval '1 day');
  out_bans jsonb;
  out_cfg jsonb;
begin
  insert into public.players (user_id)
  select distinct (x ->> 'id')::bigint
  from jsonb_array_elements(p -> 'flags') x
  union
  select distinct (x ->> 'id')::bigint
  from jsonb_array_elements(p -> 'kicks') x
  on conflict (user_id) do nothing;

  insert into public.players (user_id, username, trust_score, peak_score, last_server, last_seen)
  select (x ->> 'id')::bigint, left(x ->> 'name', 32), (x ->> 'score')::real, (x ->> 'peak')::real, srv, now()
  from jsonb_array_elements(p -> 'players') x
  on conflict (user_id) do update set
    username = excluded.username,
    trust_score = excluded.trust_score,
    peak_score = greatest(public.players.peak_score, excluded.peak_score),
    last_server = excluded.last_server,
    last_seen = now();

  with ins as (
    insert into public.flags (user_id, server_id, check_name, severity, score_after, hits, context)
    select (x ->> 'id')::bigint, srv, left(x ->> 'check', 24), (x ->> 'sev')::real,
           (x ->> 'score')::real, (x ->> 'hits')::int, coalesce(x -> 'ctx', '{}'::jsonb)
    from jsonb_array_elements(p -> 'flags') x
    returning user_id, hits
  )
  update public.players pl set total_flags = pl.total_flags + c.n
  from (select user_id, sum(hits)::int n from ins group by user_id) c
  where pl.user_id = c.user_id;

  with k as (
    insert into public.actions (user_id, action, reason, actor)
    select (x ->> 'id')::bigint, 'kick', left(x ->> 'reason', 200), 'anticheat'
    from jsonb_array_elements(p -> 'kicks') x
    returning user_id
  )
  update public.players pl set kicks = pl.kicks + c.n
  from (select user_id, count(*)::int n from k group by user_id) c
  where pl.user_id = c.user_id;

  update public.bans b set roblox_synced = true
  from jsonb_array_elements(p -> 'acks') a
  where b.user_id = (a ->> 'id')::bigint and b.active = (a ->> 'active')::boolean;

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

  select jsonb_build_object('version', version, 'thresholds', thresholds) into out_cfg
  from public.config where id = 1;

  return jsonb_build_object('bans', out_bans, 'config', out_cfg, 'now', now());
end;
$$;

revoke all on function public.game_secret(text), public.game_join(bigint), public.game_ingest(jsonb) from public, anon, authenticated;
grant execute on function public.game_secret(text), public.game_join(bigint), public.game_ingest(jsonb) to service_role;

create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule('ac-flag-cleanup', '17 3 * * *',
  $$delete from public.flags where created_at < now() - interval '30 days'$$);

select cron.schedule('ac-expire-bans', '*/10 * * * *',
  $$update public.bans set active = false, updated_at = now(), roblox_synced = true
    where active and expires_at is not null and expires_at <= now()$$);
