create or replace function public.admin_set_my_roblox(p_id bigint)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not exists (
    select 1 from public.dashboard_users
    where user_id = (select auth.uid()) and role in ('owner', 'admin', 'staff')
  ) then
    raise exception 'not allowed';
  end if;
  if p_id is not null and (p_id <= 0 or p_id > 99999999999) then raise exception 'bad roblox id'; end if;
  update public.dashboard_users set roblox_id = p_id where user_id = (select auth.uid());
end;
$$;

create or replace function public.decide_appeal(p_id bigint, p_approve boolean, p_note text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
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
    if found then
      insert into public.actions (game_id, user_id, action, reason, actor) values (g, target, 'unban', 'appeal approved', who);
    end if;
    update public.reverts set status = 'failed', result = 'cancelled, appeal approved'
    where game_id = g and user_id = target and status in ('pending', 'sent');
  end if;
end;
$$;

create or replace function public.tuning_suggestions(p_game integer)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
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
      when exists (select 1 from public.bans b where b.game_id = p_game and b.user_id = k.user_id and b.active) then 1
      when exists (select 1 from public.appeals ap where ap.game_id = p_game and ap.user_id = k.user_id and ap.status = 'approved')
        or exists (select 1 from public.actions a where a.game_id = p_game and a.user_id = k.user_id and a.action = 'unban') then 0
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
