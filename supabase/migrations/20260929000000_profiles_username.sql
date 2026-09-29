-- Fragments: add unique usernames to profiles.
--
-- Run this migration in the Supabase SQL editor (or via `supabase db push`).
-- It is additive only: no existing columns, rows, or RLS policies are changed.
--
-- What it does:
-- 1. Adds profiles.username (nullable, so existing users are unaffected).
-- 2. Enforces global uniqueness with a partial unique index (multiple NULLs
--    allowed, so users without a username never conflict).
-- 3. Adds a SECURITY DEFINER helper for availability checks so the app does
--    NOT need broad SELECT on other users' profile rows (RLS stays tight).

alter table public.profiles
  add column if not exists username text;

-- Normalization contract with the iOS client (UsernameValidator):
-- trimmed, lowercased, 3-20 chars, [a-z0-9_]. The CHECK below mirrors it so
-- invalid values are rejected even if a client bypasses validation.
alter table public.profiles
  drop constraint if exists profiles_username_format;
alter table public.profiles
  add constraint profiles_username_format
  check (username is null or username ~ '^[a-z0-9_]{3,20}$');

create unique index if not exists profiles_username_unique
  on public.profiles (username)
  where username is not null;

-- Availability check that reveals nothing except a boolean.
-- Runs with the owner's privileges, so no profiles SELECT policy change is
-- required for other users' rows.
create or replace function public.is_username_available(p_username text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles where username = p_username
  );
$$;

-- NOTE: username writes go through the SAME own-row upsert policy that
-- already permits display_name updates (the app upserts only
-- { id = auth.uid(), username = ... }). If that policy is ever tightened,
-- grant UPDATE(username) / INSERT(id, username) to the owner row accordingly.
-- A conflicting upsert surfaces HTTP 409 to PostgREST, which the iOS client
-- maps to "username already taken" without overwriting anyone.
