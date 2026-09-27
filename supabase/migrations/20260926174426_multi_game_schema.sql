create table public.games (
  id integer generated always as identity primary key,
  name text not null check (length(name) between 1 and 40),
  universe_id bigint,
  discord_guild text,
  created_at timestamptz not null default now()
);
create unique index games_guild_idx on public.games (discord_guild) where discord_guild is not null;

create table private.game_keys (
  game_id integer primary key references public.games (id) on delete cascade,
  key_sha256 text not null unique
);

create table private.game_secrets (
  game_id integer not null references public.games (id) on delete cascade,
  key text not null,
  value text not null,
  primary key (game_id, key)
);

create table public.game_staff (
  game_id integer not null references public.games (id) on delete cascade,
  user_id uuid not null references public.dashboard_users (user_id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (game_id, user_id)
);

alter table public.dashboard_users drop constraint dashboard_users_role_check;
alter table public.dashboard_users add constraint dashboard_users_role_check
  check (role in ('owner','admin','staff','pending'));

insert into public.games (id, name, universe_id)
overriding system value
select 1, 'Main game', nullif((select value from private.secrets where key = 'universe_id'), '')::bigint;
select setval(pg_get_serial_sequence('public.games', 'id'), 1);

insert into private.game_keys (game_id, key_sha256)
select 1, value from private.secrets where key = 'game_key_sha256';

insert into private.game_secrets (game_id, key, value)
select 1, key, value from private.secrets where key in ('discord_webhook', 'open_cloud_key');

delete from private.secrets where key in ('game_key_sha256', 'discord_webhook', 'open_cloud_key', 'universe_id');

alter table public.config drop constraint config_id_check;
alter table public.config add column game_id integer references public.games (id) on delete cascade;
update public.config set game_id = 1;
alter table public.config drop constraint config_pkey;
alter table public.config drop column id;
alter table public.config alter column game_id set not null;
alter table public.config add primary key (game_id);

do $$
declare
  t text;
begin
  foreach t in array array['players','flags','actions','bans','servers','replays','maps','commands','appeals'] loop
    execute format('alter table public.%I add column game_id integer not null default 1 references public.games (id) on delete cascade', t);
    execute format('alter table public.%I alter column game_id drop default', t);
  end loop;
end;
$$;

alter table public.players drop constraint players_pkey;
alter table public.players add primary key (game_id, user_id);
alter table public.bans drop constraint bans_pkey;
alter table public.bans add primary key (game_id, user_id);

drop index public.players_last_seen_idx;
drop index public.players_peak_idx;
drop index public.flags_user_idx;
drop index public.flags_created_idx;
drop index public.actions_user_idx;
drop index public.actions_created_idx;
drop index public.bans_updated_idx;
drop index public.replays_user_idx;
drop index public.appeals_status_idx;
create index players_last_seen_idx on public.players (game_id, last_seen desc);
create index flags_user_idx on public.flags (game_id, user_id, created_at desc);
create index flags_created_idx on public.flags (game_id, created_at desc);
create index actions_user_idx on public.actions (game_id, user_id, created_at desc);
create index actions_created_idx on public.actions (game_id, created_at desc);
create index bans_updated_idx on public.bans (game_id, updated_at);
create index replays_user_idx on public.replays (game_id, user_id, created_at desc);
create index appeals_status_idx on public.appeals (game_id, status, created_at desc);
create index servers_game_idx on public.servers (game_id);

alter table public.players
  add column shadowed boolean not null default false,
  add column shadow_by text,
  add column shadowed_at timestamptz,
  add column reports_against integer not null default 0,
  add column reports_made integer not null default 0,
  add column reports_confirmed integer not null default 0,
  add column reports_dismissed integer not null default 0;

alter table public.actions drop constraint actions_action_check;
alter table public.actions add constraint actions_action_check
  check (action in ('kick','ban','unban','shadow','unshadow','revert'));

alter table public.commands drop constraint commands_kind_check;
alter table public.commands add constraint commands_kind_check
  check (kind in ('spectate','replay','kick','shadow','unshadow'));

create table public.reports (
  id bigint generated always as identity primary key,
  game_id integer not null references public.games (id) on delete cascade,
  target_id bigint not null,
  reporter_id bigint not null,
  reason text not null,
  note text not null default '',
  weight real not null default 1,
  server_id text,
  replay_id bigint,
  target_score real,
  status text not null default 'open' check (status in ('open','confirmed','dismissed')),
  decided_by text,
  decided_at timestamptz,
  notified boolean not null default false,
  created_at timestamptz not null default now()
);
create index reports_open_idx on public.reports (game_id, status, created_at desc);
create index reports_target_idx on public.reports (game_id, target_id, created_at desc);
create index reports_reporter_idx on public.reports (game_id, reporter_id, created_at desc);

create table public.ledger (
  id bigint generated always as identity primary key,
  game_id integer not null references public.games (id) on delete cascade,
  user_id bigint not null,
  kind text not null check (kind in ('currency','item','kill')),
  key text not null,
  amount real not null,
  victim bigint,
  source text not null default '',
  withheld boolean not null default false,
  server_id text,
  created_at timestamptz not null default now()
);
create index ledger_user_idx on public.ledger (game_id, user_id, created_at desc);

create table public.reverts (
  id bigint generated always as identity primary key,
  game_id integer not null references public.games (id) on delete cascade,
  user_id bigint not null,
  since timestamptz not null,
  summary jsonb not null,
  status text not null default 'pending' check (status in ('pending','sent','done','failed','empty')),
  result text,
  created_by text not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  done_at timestamptz
);
create index reverts_pending_idx on public.reverts (game_id, status, created_at) where status in ('pending','sent');
create index reverts_user_idx on public.reverts (game_id, user_id, created_at desc);

create or replace function private.my_games() returns integer[]
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.dashboard_users where user_id = (select auth.uid()) and role in ('owner','admin'))
      then (select coalesce(array_agg(id), '{}') from public.games)
    else (
      select coalesce(array_agg(s.game_id), '{}')
      from public.game_staff s join public.dashboard_users d on d.user_id = s.user_id
      where s.user_id = (select auth.uid()) and d.role = 'staff'
    )
  end;
$$;

create or replace function private.can_see(g integer) returns boolean
language sql stable security definer set search_path = '' as $$
  select g is not null and g = any(private.my_games());
$$;

create or replace function private.gate(g integer) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.can_see(g) then raise exception 'not allowed'; end if;
end;
$$;

create or replace function private.topic_game(t text) returns integer
language sql immutable set search_path = '' as $$
  select case when t ~ '^mission:[0-9]{1,9}$' then split_part(t, ':', 2)::integer end;
$$;

revoke all on function private.my_games(), private.can_see(integer), private.gate(integer), private.topic_game(text)
  from public, anon;
grant execute on function private.my_games(), private.can_see(integer), private.gate(integer), private.topic_game(text)
  to authenticated;

alter table public.games enable row level security;
alter table public.game_staff enable row level security;
alter table public.reports enable row level security;
alter table public.ledger enable row level security;
alter table public.reverts enable row level security;

drop policy "admins read players" on public.players;
drop policy "admins read flags" on public.flags;
drop policy "admins read actions" on public.actions;
drop policy "admins read bans" on public.bans;
drop policy "admins read config" on public.config;
drop policy "admins read servers" on public.servers;
drop policy "admins read replays" on public.replays;
drop policy "admins read maps" on public.maps;
drop policy "admins read map chunks" on public.map_chunks;
drop policy "admins read commands" on public.commands;
drop policy "admins read appeals" on public.appeals;
drop policy "admins receive mission" on realtime.messages;

do $$
declare
  t text;
begin
  foreach t in array array['players','flags','actions','bans','config','servers','replays','maps','commands',
                           'appeals','reports','ledger','reverts'] loop
    execute format(
      'create policy "staff read own games" on public.%I for select to authenticated using (game_id in (select unnest(private.my_games())))', t);
  end loop;
end;
$$;

create policy "staff read own games" on public.games for select to authenticated
  using (id in (select unnest(private.my_games())));
create policy "staff read own games" on public.map_chunks for select to authenticated
  using (exists (
    select 1 from public.maps m
    where m.place_id = map_chunks.place_id and m.version = map_chunks.version
      and m.game_id in (select unnest(private.my_games()))
  ));
create policy "see own or admin" on public.game_staff for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

create policy "staff receive own mission" on realtime.messages for select to authenticated
  using (private.topic_game(realtime.topic()) in (select unnest(private.my_games())));

alter publication supabase_realtime add table public.reports, public.reverts, public.games;
