-- Enable necessary extensions
create extension if not exists "uuid-ossp";

-- ============================================================================
-- 1. ENUMS
-- ============================================================================
do $$ begin
    create type public.room_role as enum ('owner', 'member', 'viewer');
exception
    when duplicate_object then null;
end $$;

do $$ begin
    create type public.fragment_media_type as enum ('photo', 'video', 'audio', 'note');
exception
    when duplicate_object then null;
end $$;

-- ============================================================================
-- 2. PROFILES TABLE & TRIGGERS
-- ============================================================================
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null default 'Fragment Explorer',
    avatar_storage_path text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Public user profiles linked directly to Supabase Auth.';
comment on column public.profiles.avatar_storage_path is 'Stable bucket path for profile avatar if uploaded.';

create or replace function public.handle_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists on_profiles_updated on public.profiles;
create trigger on_profiles_updated
    before update on public.profiles
    for each row
    execute function public.handle_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(
            new.raw_user_meta_data->>'full_name',
            new.raw_user_meta_data->>'name',
            'Fragment Explorer'
        )
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();

-- ============================================================================
-- 3. ROOMS TABLE
-- ============================================================================
create table if not exists public.rooms (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(trim(name)) > 0),
    emoji text not null default '✨',
    accent_color_hex text,
    created_by uuid not null references public.profiles(id) on delete restrict,
    created_at timestamptz not null default now(),
    is_ended boolean not null default false,
    is_archived boolean not null default false,
    final_title text,
    final_category text default 'Life',
    join_code text not null unique check (char_length(join_code) = 8)
);

comment on table public.rooms is 'Collaborative Shared Moment rooms.';
comment on column public.rooms.join_code is 'Deterministic 8-character uppercase code for direct room join.';

create index if not exists rooms_created_by_idx on public.rooms (created_by);
create index if not exists rooms_join_code_idx on public.rooms (join_code);
create index if not exists rooms_created_at_idx on public.rooms (created_at desc);

-- ============================================================================
-- 4. ROOM_MEMBERS TABLE
-- ============================================================================
create table if not exists public.room_members (
    id uuid primary key default gen_random_uuid(),
    room_id uuid not null references public.rooms(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    role public.room_role not null default 'member',
    joined_at timestamptz not null default now(),
    constraint unique_room_membership unique (room_id, user_id)
);

comment on table public.room_members is 'Membership records linking profiles to rooms with defined roles.';

create index if not exists room_members_room_id_idx on public.room_members (room_id);
create index if not exists room_members_user_id_idx on public.room_members (user_id);
create index if not exists room_members_room_user_idx on public.room_members (room_id, user_id);

-- ============================================================================
-- 5. SHARED_FRAGMENTS TABLE
-- ============================================================================
create table if not exists public.shared_fragments (
    id uuid primary key default gen_random_uuid(),
    room_id uuid not null references public.rooms(id) on delete cascade,
    author_id uuid not null references public.profiles(id) on delete restrict,
    author_name text not null,
    type public.fragment_media_type not null,
    title text not null,
    subtitle text,
    text text,
    media_symbol text,
    location text,
    duration text,
    audio_waveform double precision[] not null default '{}',
    accent_color_hex text,
    phi double precision not null default 0.08,
    theta double precision not null default 0.35,
    radius_factor double precision not null default 1.0,
    created_at timestamptz not null default now()
);

comment on table public.shared_fragments is 'Fragments captured within a room, including spherical 3D canvas coordinates.';

create index if not exists shared_fragments_room_id_created_at_idx on public.shared_fragments (room_id, created_at asc, id asc);
create index if not exists shared_fragments_author_id_idx on public.shared_fragments (author_id);

-- ============================================================================
-- 6. FRAGMENT_MEDIA TABLE
-- ============================================================================
create table if not exists public.fragment_media (
    id uuid primary key default gen_random_uuid(),
    fragment_id uuid not null unique references public.shared_fragments(id) on delete cascade,
    room_id uuid not null references public.rooms(id) on delete cascade,
    storage_path text not null unique,
    file_extension text not null,
    file_size bigint,
    mime_type text,
    created_at timestamptz not null default now()
);

comment on table public.fragment_media is 'Decoupled media storage references pointing to storage paths (agnostic to storage provider).';

create index if not exists fragment_media_fragment_id_idx on public.fragment_media (fragment_id);
create index if not exists fragment_media_room_id_idx on public.fragment_media (room_id);
create index if not exists fragment_media_storage_path_idx on public.fragment_media (storage_path);

-- ============================================================================
-- 7. HELPER FUNCTIONS & RPC
-- ============================================================================
create or replace function public.is_member_of_room(p_room_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
    select exists (
        select 1
        from public.room_members
        where room_id = p_room_id
          and user_id = p_user_id
    );
$$;

create or replace function public.is_owner_of_room(p_room_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
    select exists (
        select 1
        from public.room_members
        where room_id = p_room_id
          and user_id = p_user_id
          and role = 'owner'
    );
$$;

create or replace function public.create_room_with_owner(
    p_id uuid,
    p_name text,
    p_emoji text,
    p_accent_color_hex text,
    p_created_at timestamptz
)
returns public.rooms
language plpgsql
security definer
set search_path = ''
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

    v_join_code := upper(substring(replace(p_id::text, '-', '') from 1 for 8));

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

create or replace function public.join_room_by_code(p_code text)
returns public.rooms
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid;
    v_room public.rooms;
begin
    v_user_id := (select auth.uid());
    if v_user_id is null then
        raise exception 'Authentication required.';
    end if;

    insert into public.profiles (id, display_name)
    values (v_user_id, 'Fragment Explorer')
    on conflict (id) do nothing;

    select * into v_room
    from public.rooms
    where join_code = upper(trim(p_code));

    if v_room.id is null then
        raise exception 'Room not found for code %', p_code;
    end if;

    insert into public.room_members (room_id, user_id, role, joined_at)
    values (v_room.id, v_user_id, 'member', now())
    on conflict (room_id, user_id) do nothing;

    return v_room;
end;
$$;

grant execute on function public.create_room_with_owner(uuid, text, text, text, timestamptz) to authenticated;
grant execute on function public.join_room_by_code(text) to authenticated;

-- ============================================================================
-- 8. ROW LEVEL SECURITY POLICIES
-- ============================================================================
alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.shared_fragments enable row level security;
alter table public.fragment_media enable row level security;

-- PROFILES
drop policy if exists "profiles_select_policy" on public.profiles;
create policy "profiles_select_policy"
    on public.profiles
    for select
    to authenticated
    using (true);

drop policy if exists "profiles_update_policy" on public.profiles;
create policy "profiles_update_policy"
    on public.profiles
    for update
    to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

-- ROOMS
drop policy if exists "rooms_select_policy" on public.rooms;
create policy "rooms_select_policy"
    on public.rooms
    for select
    to authenticated
    using (
        public.is_member_of_room(id, (select auth.uid()))
    );

drop policy if exists "rooms_insert_policy" on public.rooms;
create policy "rooms_insert_policy"
    on public.rooms
    for insert
    to authenticated
    with check (
        created_by = (select auth.uid())
    );

drop policy if exists "rooms_update_policy" on public.rooms;
create policy "rooms_update_policy"
    on public.rooms
    for update
    to authenticated
    using (
        public.is_owner_of_room(id, (select auth.uid()))
    )
    with check (
        public.is_owner_of_room(id, (select auth.uid()))
    );

drop policy if exists "rooms_delete_policy" on public.rooms;
create policy "rooms_delete_policy"
    on public.rooms
    for delete
    to authenticated
    using (
        public.is_owner_of_room(id, (select auth.uid()))
    );

-- ROOM_MEMBERS
drop policy if exists "room_members_select_policy" on public.room_members;
create policy "room_members_select_policy"
    on public.room_members
    for select
    to authenticated
    using (
        public.is_member_of_room(room_id, (select auth.uid()))
    );

drop policy if exists "room_members_insert_policy" on public.room_members;

drop policy if exists "room_members_delete_policy" on public.room_members;
create policy "room_members_delete_policy"
    on public.room_members
    for delete
    to authenticated
    using (
        user_id = (select auth.uid())
        or public.is_owner_of_room(room_id, (select auth.uid()))
    );

-- SHARED_FRAGMENTS
drop policy if exists "shared_fragments_select_policy" on public.shared_fragments;
create policy "shared_fragments_select_policy"
    on public.shared_fragments
    for select
    to authenticated
    using (
        public.is_member_of_room(room_id, (select auth.uid()))
    );

drop policy if exists "shared_fragments_insert_policy" on public.shared_fragments;
create policy "shared_fragments_insert_policy"
    on public.shared_fragments
    for insert
    to authenticated
    with check (
        author_id = (select auth.uid())
        and public.is_member_of_room(room_id, (select auth.uid()))
    );

drop policy if exists "shared_fragments_delete_policy" on public.shared_fragments;
create policy "shared_fragments_delete_policy"
    on public.shared_fragments
    for delete
    to authenticated
    using (
        author_id = (select auth.uid())
        or public.is_owner_of_room(room_id, (select auth.uid()))
    );

-- FRAGMENT_MEDIA
drop policy if exists "fragment_media_select_policy" on public.fragment_media;
create policy "fragment_media_select_policy"
    on public.fragment_media
    for select
    to authenticated
    using (
        public.is_member_of_room(room_id, (select auth.uid()))
    );

drop policy if exists "fragment_media_insert_policy" on public.fragment_media;
create policy "fragment_media_insert_policy"
    on public.fragment_media
    for insert
    to authenticated
    with check (
        public.is_member_of_room(room_id, (select auth.uid()))
        and exists (
            select 1 from public.shared_fragments
            where id = fragment_id
              and author_id = (select auth.uid())
        )
    );

drop policy if exists "fragment_media_delete_policy" on public.fragment_media;
create policy "fragment_media_delete_policy"
    on public.fragment_media
    for delete
    to authenticated
    using (
        public.is_owner_of_room(room_id, (select auth.uid()))
        or exists (
            select 1 from public.shared_fragments
            where id = fragment_id
              and author_id = (select auth.uid())
        )
    );

-- ============================================================================
-- 9. STORAGE BUCKET & POLICIES
-- ============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'moment-media',
    'moment-media',
    false,
    104857600,
    array['image/jpeg', 'image/png', 'image/heic', 'video/quicktime', 'video/mp4', 'audio/m4a', 'audio/x-m4a']
)
on conflict (id) do update set
    public = false,
    file_size_limit = 104857600;

create or replace function public.extract_room_id_from_path(name text)
returns uuid
language plpgsql
immutable
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

drop policy if exists "moment_media_select_policy" on storage.objects;
create policy "moment_media_select_policy"
    on storage.objects
    for select
    to authenticated
    using (
        bucket_id = 'moment-media'
        and public.is_member_of_room(
            public.extract_room_id_from_path(name),
            (select auth.uid())
        )
    );

drop policy if exists "moment_media_insert_policy" on storage.objects;
create policy "moment_media_insert_policy"
    on storage.objects
    for insert
    to authenticated
    with check (
        bucket_id = 'moment-media'
        and public.is_member_of_room(
            public.extract_room_id_from_path(name),
            (select auth.uid())
        )
    );

drop policy if exists "moment_media_delete_policy" on storage.objects;
create policy "moment_media_delete_policy"
    on storage.objects
    for delete
    to authenticated
    using (
        bucket_id = 'moment-media'
        and (
            public.is_owner_of_room(
                public.extract_room_id_from_path(name),
                (select auth.uid())
            )
            or (select auth.uid()) = owner
        )
    );

-- ============================================================================
-- 10. REALTIME CONFIGURATION
-- ============================================================================
alter table public.rooms replica identity full;
alter table public.room_members replica identity full;
alter table public.shared_fragments replica identity full;
alter table public.fragment_media replica identity full;

do $$ begin
    alter publication supabase_realtime add table public.rooms;
exception when others then null; end $$;

do $$ begin
    alter publication supabase_realtime add table public.room_members;
exception when others then null; end $$;

do $$ begin
    alter publication supabase_realtime add table public.shared_fragments;
exception when others then null; end $$;

do $$ begin
    alter publication supabase_realtime add table public.fragment_media;
exception when others then null; end $$;

