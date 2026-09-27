create index if not exists commands_game_idx on public.commands (game_id);
create index if not exists game_staff_user_idx on public.game_staff (user_id);
create index if not exists maps_game_idx on public.maps (game_id);
