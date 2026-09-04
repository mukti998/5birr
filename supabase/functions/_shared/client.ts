// Shared helper for Supabase Edge Functions (Deno runtime).
// Two clients:
//  - userClient: acts AS the calling user (respects RLS) — used to verify identity/role.
//  - adminClient: service_role — used ONLY to call SECURITY DEFINER functions
//    after we've validated the caller ourselves. Never forward service_role to the client.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export function getAdminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } }
  );
}

export function getUserClient(authHeader: string) {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } }
  );
}

export async function requireUser(req: Request) {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) throw new Response("Missing Authorization header", { status: 401 });
  const userClient = getUserClient(authHeader);
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) throw new Response("Invalid session", { status: 401 });
  return { user: data.user, userClient };
}

export async function requireRole(req: Request, role: string) {
  const { user, userClient } = await requireUser(req);
  const admin = getAdminClient();
  const { data: roles } = await admin.from("user_roles").select("role").eq("user_id", user.id);
  const has = (roles ?? []).some((r: { role: string }) => r.role === role);
  if (!has) throw new Response(JSON.stringify({ error: `ROLE_REQUIRED:${role}` }), { status: 403 });
  return { user, userClient };
}

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
