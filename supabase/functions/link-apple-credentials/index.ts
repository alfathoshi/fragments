// Fragments: link-apple-credentials Edge Function.
//
// Exchanges a Sign in with Apple authorization code for tokens and stores the
// Apple refresh token server-side so a future account deletion can revoke the
// Apple authorization. Called fire-and-forget after sign-in; it must NEVER
// fail sign-in.
//
// Required secrets (Supabase Dashboard → Edge Functions → Secrets):
//   APPLE_CLIENT_ID    - Services ID (or App bundle ID for native exchange)
//   APPLE_TEAM_ID      - 10-char Apple Team ID
//   APPLE_KEY_ID       - Sign in with Apple private key ID
//   APPLE_PRIVATE_KEY  - ES256 .p8 private key contents (PEM, newlines intact)
//
// Built-in: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY.
//
// Security: never logs codes, tokens, keys, or secrets. The refresh token is
// written only to public.apple_credentials (service-role only, no client RLS
// policies) and never returned to the client.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// NOTE: no djwt dependency. The pinned esm.sh djwt build is unresolvable by
// the Supabase Edge bundler, so the Apple client_secret JWT is signed with
// native Web Crypto (ECDSA P-256 + SHA-256) below — standards-compliant and
// equivalent (raw R||S signature, base64url, numeric dates).

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function base64UrlEncode(data: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < data.length; i += chunkSize) {
    binary += String.fromCharCode(...data.subarray(i, i + chunkSize));
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

// Signs an Apple client_secret JWT (ES256) with native Web Crypto.
// Equivalent to the previous djwt implementation: raw R||S signature,
// base64url encoding, numeric-date iat/exp, 5-minute lifetime.
async function createAppleClientSecret(
  teamId: string,
  keyId: string,
  clientId: string,
  privateKey: CryptoKey,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const encoder = new TextEncoder();
  const signingInput =
    `${base64UrlEncode(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyId })))}.` +
    `${base64UrlEncode(encoder.encode(JSON.stringify({
      iss: teamId,
      iat: now,
      exp: now + 300,
      aud: "https://appleid.apple.com",
      sub: clientId,
    })))}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    encoder.encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

// Imports an ES256 PKCS#8 PEM private key for client_secret signing.
async function importApplePrivateKey(pem: string): Promise<CryptoKey> {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", raw, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { success: false, error: "method_not_allowed" });
  }

  // 1. Authenticate the caller via their Supabase JWT.
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json(500, { success: false, error: "server_misconfigured" });
  }
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return json(401, { success: false, error: "unauthorized" });
  }

  // 2. Parse body (authorization code only; never logged).
  let authorizationCode = "";
  try {
    const body = await req.json();
    authorizationCode = typeof body?.authorization_code === "string" ? body.authorization_code : "";
  } catch {
    return json(400, { success: false, error: "invalid_body" });
  }
  if (!authorizationCode) {
    return json(400, { success: false, error: "missing_authorization_code" });
  }

  // 3. Build the Apple client_secret (ES256 JWT, 5-minute lifetime).
  const clientId = Deno.env.get("APPLE_CLIENT_ID") ?? "";
  const teamId = Deno.env.get("APPLE_TEAM_ID") ?? "";
  const keyId = Deno.env.get("APPLE_KEY_ID") ?? "";
  const privateKeyPem = Deno.env.get("APPLE_PRIVATE_KEY") ?? "";
  if (!clientId || !teamId || !keyId || !privateKeyPem) {
    return json(501, { success: false, error: "apple_not_configured", linked: false });
  }
  let clientSecret: string;
  try {
    const key = await importApplePrivateKey(privateKeyPem);
    clientSecret = await createAppleClientSecret(teamId, keyId, clientId, key);
  } catch {
    return json(500, { success: false, error: "apple_key_error", linked: false });
  }

  // 4. Exchange the authorization code for tokens.
  const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code: authorizationCode,
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!tokenRes.ok) {
    return json(502, { success: false, error: "apple_exchange_failed", linked: false });
  }
  const tokens = await tokenRes.json();
  const refreshToken = typeof tokens?.refresh_token === "string" ? tokens.refresh_token : "";
  if (!refreshToken) {
    return json(502, { success: false, error: "apple_no_refresh_token", linked: false });
  }

  // 5. Persist the refresh token server-side only. Never returned.
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const { error: upsertError } = await admin
    .from("apple_credentials")
    .upsert({ user_id: user.id, refresh_token: refreshToken, updated_at: new Date().toISOString() }, { onConflict: "user_id" });
  if (upsertError) {
    return json(500, { success: false, error: "credential_store_failed", linked: false });
  }
  return json(200, { success: true, linked: true });
});
