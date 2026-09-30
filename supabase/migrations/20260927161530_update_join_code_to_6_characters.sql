-- Migration: update_join_code_to_6_characters

ALTER TABLE public.rooms DROP CONSTRAINT IF EXISTS rooms_join_code_check;
ALTER TABLE public.rooms ADD CONSTRAINT rooms_join_code_check CHECK ((char_length(join_code) = 6));

CREATE OR REPLACE FUNCTION public.create_room_with_owner(
    p_id uuid,
    p_name text,
    p_emoji text default '✨',
    p_accent_color_hex text default null,
    p_created_at timestamptz default now()
)
returns public.rooms
language plpgsql
security definer
set search_path to ''
as $$
declare
    v_user_id uuid;
    v_join_code text;
    v_room public.rooms;
begin
    v_user_id := (select auth.uid());
    if v_user_id is null then
        raise exception 'Authentication required.';
    end if;

    insert into public.profiles (id, display_name)
    values (v_user_id, 'Fragment Explorer')
    on conflict (id) do nothing;

    v_join_code := upper(substring(replace(p_id::text, '-', '') from 1 for 6));

    insert into public.rooms (
        id, name, emoji, accent_color_hex, created_by, created_at, join_code
    ) values (
        p_id, p_name, coalesce(p_emoji, '✨'), p_accent_color_hex, v_user_id, coalesce(p_created_at, now()), v_join_code
    )
    returning * into v_room;

    insert into public.room_members (
        room_id, user_id, role, joined_at
    ) values (
        v_room.id, v_user_id, 'owner', v_room.created_at
    );

    return v_room;
end;
$$;

revoke all on function public.create_room_with_owner(uuid, text, text, text, timestamptz) from public, anon;
grant execute on function public.create_room_with_owner(uuid, text, text, text, timestamptz) to authenticated, service_role;

