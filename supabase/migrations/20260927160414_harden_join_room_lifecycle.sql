CREATE OR REPLACE FUNCTION public.join_room_by_code(p_code text)
 RETURNS rooms
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user_id uuid;
    v_room public.rooms;
begin
    v_user_id := (select auth.uid());
    if v_user_id is null then
        raise exception 'Authentication required.';
    end if;

    select * into v_room
    from public.rooms
    where join_code = upper(trim(p_code));

    if v_room.id is null then
        raise exception 'Room not found for code %', p_code;
    end if;

    if v_room.is_archived then
        raise exception 'Room is archived.';
    end if;

    if v_room.is_ended then
        raise exception 'Room has ended.';
    end if;

    insert into public.profiles (id, display_name)
    values (v_user_id, 'Fragment Explorer')
    on conflict (id) do nothing;

    insert into public.room_members (room_id, user_id, role, joined_at)
    values (v_room.id, v_user_id, 'member', now())
    on conflict (room_id, user_id) do nothing;

    return v_room;
end;
$function$;

REVOKE ALL ON FUNCTION public.join_room_by_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_room_by_code(text) TO authenticated, service_role;
