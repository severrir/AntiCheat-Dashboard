-- ban / unban / shadow live in one place. the dashboard calls them through admin_*, the
-- discord bot (service role) through bot_*, so both close reports and queue undo the same way

create or replace function private.do_ban(g integer, uid bigint, p_reason text, p_hours integer, who text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  revert_on boolean;
begin
  if uid is null or uid <= 0 then raise exception 'bad user id'; end if;
  if p_hours is not null and (p_hours < 1 or p_hours > 87600) then raise exception 'bad duration'; end if;
  insert into public.bans (game_id, user_id, reason, active, banned_by, expires_at, updated_at, roblox_synced)
  values (g, uid, left(coalesce(p_reason, ''), 200), true, who,
          case when p_hours is null then null else now() + make_interval(hours => p_hours) end,
          now(), false)
  on conflict (game_id, user_id) do update set
    reason = excluded.reason, active = true, banned_by = excluded.banned_by,
    expires_at = excluded.expires_at, updated_at = now(), roblox_synced = false;
  insert into public.actions (game_id, user_id, action, reason, actor)
  values (g, uid, 'ban', left(coalesce(p_reason, ''), 200), who);

  perform private.close_reports(g, uid, true, who);
  select coalesce((features ->> 'RevertGains')::boolean, true) into revert_on from public.config where game_id = g;
  if revert_on then
    perform private.queue_revert(g, uid, null, who);
  end if;
end;
$$;

create or replace function private.do_unban(g integer, uid bigint, who text, why text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.bans set active = false, updated_at = now(), roblox_synced = false
  where game_id = g and user_id = uid and active;
  if not found then return false; end if;
  insert into public.actions (game_id, user_id, action, reason, actor) values (g, uid, 'unban', coalesce(why, ''), who);
  -- an undo that hasn't run yet shouldn't punish someone we just cleared
  update public.reverts set status = 'failed', result = 'cancelled by unban'
  where game_id = g and user_id = uid and status in ('pending', 'sent');
  return true;
end;
$$;

create or replace function private.do_shadow(g integer, uid bigint, p_on boolean, who text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if uid is null or uid <= 0 then raise exception 'bad user id'; end if;
  insert into public.players (game_id, user_id, shadowed, shadow_by, shadowed_at)
  values (g, uid, p_on, case when p_on then who end, case when p_on then now() end)
  on conflict (game_id, user_id) do update set
    shadowed = p_on,
    shadow_by = case when p_on then who end,
    shadowed_at = case when p_on then now() end;
  -- live servers flip it within a pulse, everyone else gets it on join
  update public.commands set status = 'expired'
  where game_id = g and target_user = uid and kind in ('shadow', 'unshadow') and status in ('pending', 'sent');
  insert into public.commands (game_id, kind, target_user, created_by)
  values (g, case when p_on then 'shadow' else 'unshadow' end, uid, who);
  insert into public.actions (game_id, user_id, action, reason, actor)
  values (g, uid, case when p_on then 'shadow' else 'unshadow' end, '', who);
end;
$$;

create or replace function public.admin_ban(p_game integer, p_user_id bigint, p_reason text, p_hours integer default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.gate(p_game);
  perform private.do_ban(p_game, p_user_id, p_reason, p_hours, private.actor_name());
end;
$$;

create or replace function public.admin_unban(p_game integer, p_user_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.gate(p_game);
  perform private.do_unban(p_game, p_user_id, private.actor_name(), '');
end;
$$;

create or replace function public.admin_set_shadow(p_game integer, p_user_id bigint, p_on boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.gate(p_game);
  perform private.do_shadow(p_game, p_user_id, p_on, private.actor_name());
end;
$$;

create or replace function public.bot_ban(p_game integer, p_user_id bigint, p_reason text, p_hours integer, p_actor text)
returns void language sql security definer set search_path = '' as $$
  select private.do_ban(p_game, p_user_id, p_reason, p_hours, left(p_actor, 80));
$$;

create or replace function public.bot_unban(p_game integer, p_user_id bigint, p_actor text)
returns boolean language sql security definer set search_path = '' as $$
  select private.do_unban(p_game, p_user_id, left(p_actor, 80), '');
$$;

create or replace function public.bot_shadow(p_game integer, p_user_id bigint, p_on boolean, p_actor text)
returns void language sql security definer set search_path = '' as $$
  select private.do_shadow(p_game, p_user_id, p_on, left(p_actor, 80));
$$;

revoke all on function private.do_ban(integer, bigint, text, integer, text), private.do_unban(integer, bigint, text, text),
  private.do_shadow(integer, bigint, boolean, text) from public, anon, authenticated;
revoke all on function public.bot_ban(integer, bigint, text, integer, text), public.bot_unban(integer, bigint, text),
  public.bot_shadow(integer, bigint, boolean, text) from public, anon, authenticated;
grant execute on function public.bot_ban(integer, bigint, text, integer, text), public.bot_unban(integer, bigint, text),
  public.bot_shadow(integer, bigint, boolean, text) to service_role;
