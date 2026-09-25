create extension if not exists pg_net with schema extensions;
create extension if not exists pgcrypto with schema extensions;

alter table public.flags
  add column raw real,
  add column place_id bigint,
  add column pos_x real,
  add column pos_y real,
  add column pos_z real;
create index flags_place_idx on public.flags (place_id, created_at desc) where pos_x is not null;

alter table public.players
  add column fingerprint real[],
  add column account_age integer,
  add column alt_of bigint,
  add column alt_score real,
  add column on_island boolean not null default false;

alter table public.actions
  add column replay_id bigint,
  add column signature text[];

alter table public.dashboard_users add column roblox_id bigint;

alter table public.config
  add column features jsonb not null default '{}'::jsonb;

create table public.servers (
  server_id text primary key,
  place_id bigint,
  players integer not null default 0,
  threat smallint not null default 0,
  island boolean not null default false,
  last_seen timestamptz not null default now()
);

create table public.replays (
  id bigint generated always as identity primary key,
  user_id bigint not null,
  server_id text,
  place_id bigint,
  map_version text,
  kind text not null check (kind in ('kick','capture','session')),
  reason text not null default '',
  token text not null default encode(extensions.gen_random_bytes(18), 'hex'),
  meta jsonb not null default '{}'::jsonb,
  samples jsonb not null,
  events jsonb not null,
  created_at timestamptz not null default now()
);
create index replays_user_idx on public.replays (user_id, created_at desc);

create table public.maps (
  place_id bigint not null,
  version text not null,
  total integer not null,
  received integer not null default 0,
  bounds jsonb,
  created_at timestamptz not null default now(),
  primary key (place_id, version)
);

create table public.map_chunks (
  place_id bigint not null,
  version text not null,
  idx integer not null,
  parts jsonb not null,
  primary key (place_id, version, idx),
  foreign key (place_id, version) references public.maps (place_id, version) on delete cascade
);

create table public.commands (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('spectate','replay','kick')),
  target_user bigint not null,
  admin_user bigint,
  status text not null default 'pending' check (status in ('pending','sent','done','failed','expired')),
  result text,
  created_by text not null,
  created_at timestamptz not null default now(),
  done_at timestamptz
);
create index commands_pending_idx on public.commands (status, created_at) where status in ('pending','sent');

create table public.appeals (
  id bigint generated always as identity primary key,
  user_id bigint not null,
  username text not null default '',
  message text not null,
  discord_user uuid references auth.users (id) on delete set null,
  discord_name text not null default '',
  status text not null default 'open' check (status in ('open','approved','denied')),
  note text not null default '',
  decided_by text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);
create index appeals_status_idx on public.appeals (status, created_at desc);
create index appeals_discord_idx on public.appeals (discord_user, created_at desc);

alter table public.servers enable row level security;
alter table public.replays enable row level security;
alter table public.maps enable row level security;
alter table public.map_chunks enable row level security;
alter table public.commands enable row level security;
alter table public.appeals enable row level security;

create policy "admins read servers" on public.servers for select to authenticated using ((select private.is_admin()));
create policy "admins read replays" on public.replays for select to authenticated using ((select private.is_admin()));
create policy "admins read maps" on public.maps for select to authenticated using ((select private.is_admin()));
create policy "admins read map chunks" on public.map_chunks for select to authenticated using ((select private.is_admin()));
create policy "admins read commands" on public.commands for select to authenticated using ((select private.is_admin()));
create policy "admins read appeals" on public.appeals for select to authenticated using ((select private.is_admin()));

-- live radar goes over a private broadcast channel, only admins may listen
create policy "admins receive mission" on realtime.messages for select to authenticated
  using ((select private.is_admin()) and realtime.topic() = 'mission');

alter publication supabase_realtime add table public.servers, public.appeals;
