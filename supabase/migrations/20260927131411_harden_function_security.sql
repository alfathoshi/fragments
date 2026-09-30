-- Fix search_path on extract_room_id_from_path
create or replace function public.extract_room_id_from_path(name text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
    parts text[];
begin
    parts := string_to_array(name, '/');
    if parts[1] = 'rooms' and parts[2] is not null then
        return parts[2]::uuid;
    end if;
    return null;
exception
    when others then
        return null;
end;
$$;

-- Revoke default public execution from internal trigger functions
revoke execute on function public.handle_updated_at() from PUBLIC, anon, authenticated;
revoke execute on function public.handle_new_user() from PUBLIC, anon, authenticated;

-- Revoke anon execution from room RPC functions
revoke execute on function public.create_room_with_owner(uuid, text, text, text, timestamptz) from PUBLIC, anon;
revoke execute on function public.join_room_by_code(text) from PUBLIC, anon;

-- Grant execution to authenticated for intentional RPCs
grant execute on function public.create_room_with_owner(uuid, text, text, text, timestamptz) to authenticated;
grant execute on function public.join_room_by_code(text) to authenticated;

