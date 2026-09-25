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
    'id', p.id, 'kind', p.kind, 'target', p.target_user::text, 'admin', p.admin_user::text,
    'server', pl.last_server)), '[]'::jsonb)
  into out_cmds
  from picked p left join public.players pl on pl.user_id = p.target_user;
  return out_cmds;
end;
$$;
revoke all on function private.take_commands(bigint[]) from public, anon, authenticated;
