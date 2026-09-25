create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.dashboard_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  discord_id text,
  username text not null default '',
  avatar_url text,
  role text not null default 'pending' check (role in ('owner','admin','pending')),
  created_at timestamptz not null default now()
);

create table public.players (
  user_id bigint primary key,
  username text not null default '',
  trust_score real not null default 0,
  peak_score real not null default 0,
  total_flags integer not null default 0,
  kicks integer not null default 0,
  last_server text,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index players_last_seen_idx on public.players (last_seen desc);
create index players_peak_idx on public.players (peak_score desc);

create table public.flags (
  id bigint generated always as identity primary key,
  user_id bigint not null,
  server_id text not null,
  check_name text not null,
  severity real not null,
  score_after real not null,
  hits integer not null default 1,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index flags_user_idx on public.flags (user_id, created_at desc);
create index flags_created_idx on public.flags (created_at desc);

create table public.actions (
  id bigint generated always as identity primary key,
  user_id bigint not null,
  action text not null check (action in ('kick','ban','unban')),
  reason text not null default '',
  actor text not null,
  created_at timestamptz not null default now()
);
create index actions_user_idx on public.actions (user_id, created_at desc);
create index actions_created_idx on public.actions (created_at desc);

create table public.bans (
  user_id bigint primary key,
  reason text not null default '',
  active boolean not null default true,
  banned_by text not null,
  expires_at timestamptz,
  updated_at timestamptz not null default now(),
  roblox_synced boolean not null default false
);
create index bans_updated_idx on public.bans (updated_at);

create table public.config (
  id smallint primary key default 1 check (id = 1),
  thresholds jsonb not null default '{}'::jsonb,
  version integer not null default 1,
  updated_at timestamptz not null default now(),
  updated_by text
);
insert into public.config default values;

create table private.secrets (
  key text primary key,
  value text not null
);

alter table public.dashboard_users enable row level security;
alter table public.players enable row level security;
alter table public.flags enable row level security;
alter table public.actions enable row level security;
alter table public.bans enable row level security;
alter table public.config enable row level security;

create or replace function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.dashboard_users
    where user_id = (select auth.uid()) and role in ('owner','admin')
  );
$$;

create or replace function private.is_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.dashboard_users
    where user_id = (select auth.uid()) and role = 'owner'
  );
$$;

create or replace function private.actor_name() returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(nullif(username, ''), discord_id, 'admin')
  from public.dashboard_users where user_id = (select auth.uid());
$$;

grant usage on schema private to authenticated;
revoke all on all functions in schema private from public, anon;
grant execute on function private.is_admin(), private.is_owner(), private.actor_name() to authenticated;

create policy "see self or admin" on public.dashboard_users for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
create policy "admins read players" on public.players for select to authenticated using ((select private.is_admin()));
create policy "admins read flags" on public.flags for select to authenticated using ((select private.is_admin()));
create policy "admins read actions" on public.actions for select to authenticated using ((select private.is_admin()));
create policy "admins read bans" on public.bans for select to authenticated using ((select private.is_admin()));
create policy "admins read config" on public.config for select to authenticated using ((select private.is_admin()));

-- first discord login becomes owner, everyone after waits for approval
create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  has_owner boolean;
begin
  perform pg_advisory_xact_lock(7340021);
  select exists (select 1 from public.dashboard_users where role = 'owner') into has_owner;
  insert into public.dashboard_users (user_id, discord_id, username, avatar_url, role)
  values (
    new.id,
    new.raw_user_meta_data ->> 'provider_id',
    left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), 64),
    new.raw_user_meta_data ->> 'avatar_url',
    case when not has_owner and coalesce(new.raw_app_meta_data ->> 'provider', '') = 'discord'
      then 'owner' else 'pending' end
  );
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

create or replace function public.admin_ban(p_user_id bigint, p_reason text, p_hours integer default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  who text;
begin
  if not private.is_admin() then raise exception 'not allowed'; end if;
  if p_user_id is null or p_user_id <= 0 then raise exception 'bad user id'; end if;
  if p_hours is not null and (p_hours < 1 or p_hours > 87600) then raise exception 'bad duration'; end if;
  who := private.actor_name();
  insert into public.bans (user_id, reason, active, banned_by, expires_at, updated_at, roblox_synced)
  values (p_user_id, left(coalesce(p_reason, ''), 200), true, who,
          case when p_hours is null then null else now() + make_interval(hours => p_hours) end,
          now(), false)
  on conflict (user_id) do update set
    reason = excluded.reason, active = true, banned_by = excluded.banned_by,
    expires_at = excluded.expires_at, updated_at = now(), roblox_synced = false;
  insert into public.actions (user_id, action, reason, actor)
  values (p_user_id, 'ban', left(coalesce(p_reason, ''), 200), who);
end;
$$;

create or replace function public.admin_unban(p_user_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  who text;
begin
  if not private.is_admin() then raise exception 'not allowed'; end if;
  who := private.actor_name();
  update public.bans set active = false, updated_at = now(), roblox_synced = false
  where user_id = p_user_id and active;
  if found then
    insert into public.actions (user_id, action, reason, actor) values (p_user_id, 'unban', '', who);
  end if;
end;
$$;

-- only known keys, only numbers, clamped. anything else gets dropped
create or replace function public.admin_set_thresholds(p_thresholds jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  allowed text[] := array[
    'KickScore','HalfLife','SpeedMargin','TeleportDistance','FlyTime','FlyHeight',
    'RemoteBurstMultiplier','MinCorroboratingChecks','HeartbeatTimeout','TimingMinCV',
    'AccuracyCap','WeightMovement','WeightCharacter','WeightRemote','WeightStatistical',
    'WeightTiming','WeightHoneypot','WeightClient','WeightCombat'
  ];
  k text;
  v jsonb;
  clean jsonb := '{}'::jsonb;
  new_version integer;
begin
  if not private.is_admin() then raise exception 'not allowed'; end if;
  if jsonb_typeof(p_thresholds) <> 'object' then raise exception 'bad payload'; end if;
  for k, v in select * from jsonb_each(p_thresholds) loop
    if k = any(allowed) and jsonb_typeof(v) = 'number' then
      clean := clean || jsonb_build_object(k, greatest(0, least((v)::text::numeric, 100000)));
    end if;
  end loop;
  update public.config set thresholds = clean, version = version + 1,
    updated_at = now(), updated_by = private.actor_name()
  where id = 1 returning version into new_version;
  return new_version;
end;
$$;

create or replace function public.admin_set_role(p_target uuid, p_role text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() then raise exception 'not allowed'; end if;
  if p_role not in ('admin','pending') then raise exception 'bad role'; end if;
  if p_target = (select auth.uid()) then raise exception 'cannot change own role'; end if;
  update public.dashboard_users set role = p_role where user_id = p_target and role <> 'owner';
end;
$$;

create or replace function public.admin_remove_user(p_target uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() then raise exception 'not allowed'; end if;
  if p_target = (select auth.uid()) then raise exception 'cannot remove yourself'; end if;
  delete from public.dashboard_users where user_id = p_target and role <> 'owner';
end;
$$;

create or replace function public.admin_set_webhook(p_url text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() then raise exception 'not allowed'; end if;
  if p_url is null or p_url = '' then
    delete from private.secrets where key = 'discord_webhook';
    return;
  end if;
  if p_url !~ '^https://(discord\.com|discordapp\.com)/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$' then
    raise exception 'not a discord webhook url';
  end if;
  insert into private.secrets (key, value) values ('discord_webhook', p_url)
  on conflict (key) do update set value = excluded.value;
end;
$$;

create or replace function public.webhook_configured()
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_admin() and exists (select 1 from private.secrets where key = 'discord_webhook');
$$;

revoke all on function public.admin_ban(bigint, text, integer), public.admin_unban(bigint),
  public.admin_set_thresholds(jsonb), public.admin_set_role(uuid, text), public.admin_remove_user(uuid),
  public.admin_set_webhook(text), public.webhook_configured() from public, anon;
grant execute on function public.admin_ban(bigint, text, integer), public.admin_unban(bigint),
  public.admin_set_thresholds(jsonb), public.admin_set_role(uuid, text), public.admin_remove_user(uuid),
  public.admin_set_webhook(text), public.webhook_configured() to authenticated;

alter publication supabase_realtime add table public.flags, public.players, public.bans;
