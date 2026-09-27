alter table public.replays add column rig jsonb, add column poses jsonb;
alter table public.maps add column sky jsonb, add column terrain jsonb;

create table public.map_terrain (
  place_id bigint not null,
  version text not null,
  idx integer not null,
  start integer not null,
  data jsonb not null,
  primary key (place_id, version, idx),
  foreign key (place_id, version) references public.maps (place_id, version) on delete cascade
);
alter table public.map_terrain enable row level security;
create policy "staff read own games" on public.map_terrain for select to authenticated
  using (exists (
    select 1 from public.maps m
    where m.place_id = map_terrain.place_id and m.version = map_terrain.version
      and m.game_id in (select unnest(private.my_games()))
  ));

create or replace function public.game_replay(p_game integer, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  new_id bigint;
  new_token text;
begin
  insert into public.replays (game_id, user_id, server_id, place_id, map_version, kind, reason, meta, samples, events, rig, poses)
  values (p_game, (p ->> 'user')::bigint, left(p ->> 'server', 64), nullif(p ->> 'place', '')::bigint,
          left(p ->> 'mapVersion', 64), p ->> 'kind', left(coalesce(p ->> 'reason', ''), 200),
          coalesce(p -> 'meta', '{}'::jsonb), p -> 'samples', p -> 'events',
          case when jsonb_typeof(p -> 'rig') = 'object' then p -> 'rig' end,
          case when jsonb_typeof(p -> 'poses') = 'array' then p -> 'poses' end)
  returning id, token into new_id, new_token;
  return jsonb_build_object('id', new_id, 'token', new_token);
end;
$$;

drop function public.game_map_check(integer, bigint, text, integer, jsonb);
create or replace function public.game_map_check(p_game integer, p_place bigint, p_version text, p_total integer,
                                                 p_bounds jsonb, p_sky jsonb default null, p_terrain jsonb default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  m record;
begin
  select * into m from public.maps where place_id = p_place and version = p_version;
  if found and m.game_id <> p_game then return false; end if;
  if found and m.received >= m.total then return false; end if;
  if not found then
    insert into public.maps (game_id, place_id, version, total, bounds, sky, terrain)
    values (p_game, p_place, left(p_version, 64), p_total, p_bounds, p_sky, p_terrain)
    on conflict do nothing;
  end if;
  return true;
end;
$$;

create or replace function private.map_received(p_place bigint, p_version text) returns void
language sql security definer set search_path = '' as $$
  update public.maps set received =
    (select count(*) from public.map_chunks where place_id = p_place and version = p_version)
    + (select count(*) from public.map_terrain where place_id = p_place and version = p_version)
  where place_id = p_place and version = p_version;
$$;

create or replace function public.game_map_chunk(p_game integer, p_place bigint, p_version text, p_idx integer, p_parts jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.maps where place_id = p_place and version = p_version and game_id = p_game) then
    return;
  end if;
  insert into public.map_chunks (place_id, version, idx, parts) values (p_place, p_version, p_idx, p_parts)
  on conflict (place_id, version, idx) do update set parts = excluded.parts;
  perform private.map_received(p_place, p_version);
end;
$$;

create or replace function public.game_map_terrain(p_game integer, p_place bigint, p_version text, p_idx integer,
                                                   p_start integer, p_data jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.maps where place_id = p_place and version = p_version and game_id = p_game) then
    return;
  end if;
  insert into public.map_terrain (place_id, version, idx, start, data) values (p_place, p_version, p_idx, p_start, p_data)
  on conflict (place_id, version, idx) do update set start = excluded.start, data = excluded.data;
  perform private.map_received(p_place, p_version);
end;
$$;

revoke all on function private.map_received(bigint, text) from public, anon, authenticated;
revoke all on function public.game_map_check(integer, bigint, text, integer, jsonb, jsonb, jsonb),
  public.game_map_terrain(integer, bigint, text, integer, integer, jsonb) from public, anon, authenticated;
grant execute on function public.game_map_check(integer, bigint, text, integer, jsonb, jsonb, jsonb),
  public.game_map_terrain(integer, bigint, text, integer, integer, jsonb) to service_role;
