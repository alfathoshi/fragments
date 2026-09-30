-- Fragments: secure random room join codes.
--
-- Replaces the deterministic join_code derivation
-- (upper(first 6 hex chars of the room UUID)) with cryptographically secure
-- random codes, enforced by the pre-existing UNIQUE constraint.
--
-- Baseline: recovered production definitions (Sep 27 migrations), preserved
-- exactly except for join-code generation. In particular:
-- - rooms has NO updated_at column: the backfill mutates join_code only.
-- - rooms_join_code_key UNIQUE(join_code) already exists and is preserved;
--   no redundant index is created.
-- - join_room_by_code is NOT touched (already secure once codes are random).
-- - create_room_with_owner keeps its exact signature, DEFAULTs,
--   SECURITY DEFINER, SET search_path TO '', auth/profile/owner behavior,
--   and grants. Only the join-code line becomes CSPRNG + bounded retry.
--
-- Safe to re-run: DDL uses IF NOT EXISTS / OR REPLACE; the backfill retries
-- on unique_violation and runs in the migration transaction (atomic: any
-- failure rolls back every rotation).

-- 0. CSPRNG source.
create extension if not exists pgcrypto;

-- 1. Unbiased random join-code generator (server-side only).
--
-- Alphabet: 30 uppercase alphanumerics excluding visually ambiguous
--   O / 0, I / 1, S / 5  ->  ABCDEFGHJKLMNPQRTUVWXYZ2346789
-- Mapping: rejection sampling. Byte values 0..239 accepted (240 = 30 * 8),
--   240..255 rejected and redrawn, so each symbol has exactly 8/240
--   probability. A naive `byte % 30` would bias the first 16 symbols.
-- No room_id, UUID, timestamp, counter, or metadata is used as input.
--
-- NOTE on search_path: pgcrypto lives in the `extensions` schema on Supabase
-- but in `public` on vanilla installs, so the path lists both (pg_catalog is
-- always implicit). A bare '' path would make gen_random_bytes unresolvable.
-- (Unquoted comma-separated identifiers: a single-quoted string would be one
-- schema name containing a comma.)
create or replace function public.generate_room_join_code()
returns text
language plpgsql
set search_path to public, extensions
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRTUVWXYZ2346789';
  result text := '';
  b int;
begin
  while length(result) < 6 loop
    b := get_byte(gen_random_bytes(1), 0);
    if b < 240 then
      result := result || substr(alphabet, (b % 30) + 1, 1);
    end if;
  end loop;
  return result;
end;
$$;

revoke all on function public.generate_room_join_code() from public, anon, authenticated;
grant execute on function public.generate_room_join_code() to service_role;
-- NOTE: no GRANT to anon/authenticated. Generation stays server-side only;
-- it is invoked by the SECURITY DEFINER create function and by this
-- migration's backfill, both running with owner privileges.

-- 2. Ensure rooms.join_code exists (defensive; present with NOT NULL on dev).
do $$
begin
  if to_regclass('public.rooms') is not null
     and not exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'rooms' and column_name = 'join_code'
     ) then
    alter table public.rooms add column join_code text;
  end if;
end;
$$;

-- 3. Preserve the existing uniqueness enforcement (rooms_join_code_key).
-- Create a UNIQUE index ONLY if no unique constraint/index on join_code exists.
do $$
declare
  v_att smallint;
begin
  if to_regclass('public.rooms') is null then
    raise notice 'rooms table missing: skipping uniqueness check';
    return;
  end if;
  select attnum into v_att
    from pg_attribute
   where attrelid = 'public.rooms'::regclass and attname = 'join_code';
  if exists (
    select 1 from pg_index
     where indrelid = 'public.rooms'::regclass
       and indisunique and indnatts = 1 and indkey[0] = v_att
  ) then
    raise notice 'UNIQUE enforcement on rooms(join_code) already present: preserved, nothing created';
  else
    create unique index rooms_join_code_unique on public.rooms (join_code);
  end if;
end;
$$;

-- 4. Regenerate EVERY existing join_code while UNIQUE stays enforced.
-- Single-column UPDATE per row with EXCEPTION WHEN unique_violation retry.
-- Mutates join_code ONLY. No other column, table, or Storage object is touched.
do $$
declare
  r record;
  attempts int;
  new_code text;
begin
  if to_regclass('public.rooms') is null then
    raise notice 'rooms table missing: skipping join_code backfill';
    return;
  end if;

  for r in select id from public.rooms order by id loop
    attempts := 0;
    loop
      attempts := attempts + 1;
      if attempts > 20 then
        raise exception 'could not generate unique join code for room %', r.id;
      end if;
      new_code := public.generate_room_join_code();
      begin
        update public.rooms set join_code = new_code where id = r.id;
        exit;
      exception when unique_violation then
        -- Collision with an existing code: retry with fresh randomness.
      end;
    end loop;
  end loop;
end;
$$;

-- 5. Enforce NOT NULL after every row holds a random code (no-op on dev).
do $$
begin
  if to_regclass('public.rooms') is not null then
    alter table public.rooms alter column join_code set not null;
  end if;
end;
$$;

-- 6. Replace the stale column comment (referenced deterministic 8-char codes).
comment on column public.rooms.join_code is
  'Random 6-character user-facing room join credential, independent from the room UUID.';

-- 7. Secure create_room_with_owner. Identical to the recovered production
-- version except join-code generation: CSPRNG value with bounded retry on
-- join_code unique_violation. A room primary-key collision re-raises the
-- original duplicate-key error (duplicate IDs keep failing as before);
-- only join-code collisions retry. UNIQUE remains the final authority.
create or replace function public.create_room_with_owner(
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
    v_attempts int := 0;
begin
    v_user_id := (select auth.uid());
    if v_user_id is null then
        raise exception 'Authentication required.';
    end if;

    insert into public.profiles (id, display_name)
    values (v_user_id, 'Fragment Explorer')
    on conflict (id) do nothing;

    loop
        v_attempts := v_attempts + 1;
        if v_attempts > 10 then
            raise exception 'Could not generate a unique join code. Please try again.';
        end if;
        v_join_code := public.generate_room_join_code();
        begin
            insert into public.rooms (
                id, name, emoji, accent_color_hex, created_by, created_at, join_code
            ) values (
                p_id, p_name, coalesce(p_emoji, '✨'), p_accent_color_hex, v_user_id, coalesce(p_created_at, now()), v_join_code
            )
            returning * into v_room;
            exit;
        exception when unique_violation then
            if exists (select 1 from public.rooms where id = p_id) then
                raise;
            end if;
            -- else: join_code collision — retry with a fresh random code.
        end;
    end loop;

    insert into public.room_members (
        room_id, user_id, role, joined_at
    ) values (
        v_room.id, v_user_id, 'owner', v_room.created_at
    );

    return v_room;
end;
$$;

-- Grants preserved via CREATE OR REPLACE (authenticated + service_role;
-- PUBLIC/anon revoked by the earlier hardening migration). No GRANT here,
-- so privileges cannot widen.
-- join_room_by_code is intentionally NOT recreated: its upper(trim())
-- lookup, archived/ended guards, idempotent membership insert, and grants
-- are already correct for random codes.
