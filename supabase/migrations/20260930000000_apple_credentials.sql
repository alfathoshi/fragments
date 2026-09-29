-- Fragments: server-side Apple credential storage for account-deletion revocation.
--
-- Sign in with Apple only yields a short-lived authorization code on the
-- client. Revoking Apple's authorization later requires the Apple refresh
-- token, which can only be obtained with the Apple private key (server-side).
-- This table holds that refresh token so `delete-account` can revoke it.
--
-- Access: RLS is enabled with NO policies, so anon/authenticated keys can
-- neither read nor write rows. Only the service-role key (Edge Functions)
-- can access this table. The iOS app must NEVER read from it.

create table if not exists public.apple_credentials (
  user_id uuid primary key references auth.users (id) on delete cascade,
  refresh_token text not null,
  updated_at timestamptz not null default now()
);

alter table public.apple_credentials enable row level security;

-- Intentionally no policies: default-deny for all client keys.
-- service_role bypasses RLS and is the sole accessor (Edge Functions only).
