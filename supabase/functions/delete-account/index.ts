// Fragments: delete-account Edge Function (privileged, service-role only).
//
// Permanently deletes EVERYTHING owned by the calling user. Product semantics
// are intentionally destructive:
//   - Rooms owned by the user (created_by = user) are deleted ENTIRELY,
//     including other members' fragments/media inside them.
//   - In rooms owned by others, only the user's membership, their own
//     fragments, that fragments' media rows, and those fragments' Storage
//     objects are deleted. Other users' content is untouched.
//   - No anonymization, no ownership transfer, nothing preserved.
//
// Deletion order (deterministic, child → parent; profile before auth user,
// auth user LAST):
//   1. Resolve user from JWT.
//   2. Find owned rooms.
//   3. Collect Storage paths (owned rooms: ALL media; other rooms: only the
//      user's own fragments' media) BEFORE deleting any rows.
//   4. Delete collected Storage objects (moment-media), batched.
//   5. Delete fragment_media + shared_fragments for owned rooms and for the
//      user's fragments elsewhere (explicit; does not depend on cascades).
//   6. Delete room_members for owned rooms + all of the user's memberships.
//   7. Delete owned rooms.
//   8. Delete apple_credentials row; attempt Apple revoke if a refresh token
//      and Apple secrets exist (honestly reported, never faked).
//   9. Delete profiles row.
//   10. auth.admin.deleteUser(userId) LAST.
//
// Required secrets: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// (built-in). Optional for Apple revocation: APPLE_CLIENT_ID, APPLE_TEAM_ID,
// APPLE_KEY_ID, APPLE_PRIVATE_KEY.
//
// Security: never logs tokens, codes, keys, or secrets. All steps are
// idempotent, so the client can safely retry after a failure.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
// NOTE: no djwt dependency (unresolvable by the Edge bundler). The Apple
// client_secret JWT is signed with native Web Crypto (ECDSA P-256 + SHA-256),
// standards-compliant and equivalent (raw R||S signature, base64url, numeric
// dates).

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MEDIA_BUCKET = "moment-media";
const STORAGE_BATCH_SIZE = 100;

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

// Signs an Apple client_secret JWT (ES256) with native Web Crypto:
// raw R||S signature, base64url encoding, numeric-date iat/exp, 5-minute lifetime.
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

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

function importApplePrivateKey(pem: string): Promise<CryptoKey> {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", raw, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { success: false, error: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json(500, { success: false, error: "server_misconfigured" });
  }

  // Step 1 — resolve the caller from their JWT. The caller can only ever
  // delete their own account: userId comes from the validated token, never
  // from the request body.
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return json(401, { success: false, error: "unauthorized" });
  }
  const userId = user.id;

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const fail = (step: string, detail: string) =>
    json(500, { success: false, error: "deletion_failed", failed_step: step, detail });

  // Step 2 — owned rooms.
  const { data: ownedRooms, error: ownedError } = await admin
    .from("rooms")
    .select("id")
    .eq("created_by", userId);
  if (ownedError) return fail("list_owned_rooms", ownedError.message);
  const ownedRoomIds = (ownedRooms ?? []).map((r) => r.id as string);

  // Step 3 — collect Storage paths BEFORE deleting any rows.
  const storagePaths = new Set<string>();
  if (ownedRoomIds.length > 0) {
    const { data: ownedMedia, error: ownedMediaError } = await admin
      .from("fragment_media")
      .select("storage_path")
      .in("room_id", ownedRoomIds);
    if (ownedMediaError) return fail("collect_owned_media", ownedMediaError.message);
    for (const row of ownedMedia ?? []) {
      if (row.storage_path) storagePaths.add(row.storage_path as string);
    }
  }
  // Media of the user's own fragments in rooms owned by others.
  const { data: ownFragments, error: ownFragmentsError } = await admin
    .from("shared_fragments")
    .select("id, room_id")
    .eq("author_id", userId);
  if (ownFragmentsError) return fail("list_own_fragments", ownFragmentsError.message);
  const ownFragmentIds = (ownFragments ?? []).map((f) => f.id as string);
  if (ownFragmentIds.length > 0) {
    const { data: ownMedia, error: ownMediaError } = await admin
      .from("fragment_media")
      .select("storage_path")
      .in("fragment_id", ownFragmentIds);
    if (ownMediaError) return fail("collect_own_media", ownMediaError.message);
    for (const row of ownMedia ?? []) {
      if (row.storage_path) storagePaths.add(row.storage_path as string);
    }
  }

  // Step 4 — delete Storage objects first (external to Postgres, so a failure
  // here aborts before any relational mutation; the client retries cleanly).
  const paths = [...storagePaths];
  let storageRemoved = 0;
  const storageFailures: string[] = [];
  for (const batch of chunk(paths, STORAGE_BATCH_SIZE)) {
    const { data: removed, error: removeError } = await admin.storage.from(MEDIA_BUCKET).remove(batch);
    if (removeError) {
      storageFailures.push(removeError.message);
    } else {
      storageRemoved += (removed ?? []).length;
    }
  }
  if (storageFailures.length > 0) {
    return fail("delete_storage", storageFailures.join("; "));
  }

  // Step 5 — delete fragment_media + shared_fragments (explicit child→parent;
  // never depends on cascade behavior).
  if (ownedRoomIds.length > 0) {
    const { error } = await admin.from("fragment_media").delete().in("room_id", ownedRoomIds);
    if (error) return fail("delete_owned_media_rows", error.message);
    const { error: fragError } = await admin.from("shared_fragments").delete().in("room_id", ownedRoomIds);
    if (fragError) return fail("delete_owned_fragments", fragError.message);
  }
  if (ownFragmentIds.length > 0) {
    const { error } = await admin.from("fragment_media").delete().in("fragment_id", ownFragmentIds);
    if (error) return fail("delete_own_media_rows", error.message);
    const { error: fragError } = await admin.from("shared_fragments").delete().in("id", ownFragmentIds);
    if (fragError) return fail("delete_own_fragments", fragError.message);
  }

  // Step 6 — memberships: all members of owned rooms, plus every remaining
  // membership of the user elsewhere.
  if (ownedRoomIds.length > 0) {
    const { error } = await admin.from("room_members").delete().in("room_id", ownedRoomIds);
    if (error) return fail("delete_owned_memberships", error.message);
  }
  {
    const { error } = await admin.from("room_members").delete().eq("user_id", userId);
    if (error) return fail("delete_own_memberships", error.message);
  }

  // Step 7 — delete owned rooms (nothing references them anymore).
  if (ownedRoomIds.length > 0) {
    const { error } = await admin.from("rooms").delete().in("id", ownedRoomIds);
    if (error) return fail("delete_owned_rooms", error.message);
  }

  // Step 8 — Apple authorization revocation (best effort, honestly reported).
  let appleRevoked = false;
  let appleReason = "no_stored_apple_credential";
  const { data: appleRow } = await admin
    .from("apple_credentials")
    .select("refresh_token")
    .eq("user_id", userId)
    .maybeSingle();
  const appleRefreshToken = (appleRow?.refresh_token as string | undefined) ?? "";
  const clientId = Deno.env.get("APPLE_CLIENT_ID") ?? "";
  const teamId = Deno.env.get("APPLE_TEAM_ID") ?? "";
  const keyId = Deno.env.get("APPLE_KEY_ID") ?? "";
  const privateKeyPem = Deno.env.get("APPLE_PRIVATE_KEY") ?? "";
  if (appleRefreshToken && clientId && teamId && keyId && privateKeyPem) {
    try {
      const key = await importApplePrivateKey(privateKeyPem);
      const clientSecret = await createAppleClientSecret(teamId, keyId, clientId, key);
      const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: clientSecret,
          token: appleRefreshToken,
          token_type_hint: "refresh_token",
        }),
      });
      if (revokeRes.ok) {
        appleRevoked = true;
        appleReason = "revoked";
      } else {
        appleReason = `apple_revoke_rejected:${revokeRes.status}`;
      }
    } catch {
      appleReason = "apple_revoke_error";
    }
  } else if (appleRefreshToken) {
    appleReason = "apple_not_configured";
  }
  // The stored credential is deleted regardless of revoke outcome.
  await admin.from("apple_credentials").delete().eq("user_id", userId);

  // Step 9 — profile (all references resolved above; RESTRICT-safe).
  {
    const { error } = await admin.from("profiles").delete().eq("id", userId);
    if (error) return fail("delete_profile", error.message);
  }

  // Step 10 — auth user LAST.
  {
    const { error } = await admin.auth.admin.deleteUser(userId);
    if (error) return fail("delete_auth_user", error.message);
  }

  return json(200, {
    success: true,
    deleted: {
      owned_rooms: ownedRoomIds.length,
      own_fragments_elsewhere: ownFragmentIds.filter((id) =>
        !ownedRoomIds.includes((ownFragments ?? []).find((f) => f.id === id)?.room_id as string)
      ).length,
      storage_objects: storageRemoved,
    },
    storage: { removed: storageRemoved, failed: 0 },
    apple: { revoked: appleRevoked, reason: appleReason },
  });
});
