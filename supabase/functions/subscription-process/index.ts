// POST /subscription-process
// Called by n8n on a daily schedule (see /n8n/subscription-cron.md).
// Auth: shared secret header X-N8N-SECRET, checked against env var — this
// endpoint is NOT a user-facing endpoint and carries no user JWT.
// Finds all providers whose subscription is due today or earlier and charges
// them idempotently (unique per provider+period), then flags grace/suspension.
import { corsHeaders, getAdminClient, json } from "../_shared/client.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const secret = req.headers.get("X-N8N-SECRET");
    if (!secret || secret !== Deno.env.get("N8N_SHARED_SECRET")) {
      return json({ error: "UNAUTHORIZED" }, 401);
    }

    const admin = getAdminClient();
    const graceDays = Number((await admin
      .from("system_settings").select("value").eq("key", "subscription_grace_period_days").single()
    ).data?.value ?? 3);

    const { data: due, error } = await admin
      .from("subscriptions")
      .select("provider_id, next_due_date, status")
      .lte("next_due_date", new Date().toISOString())
      .in("status", ["ACTIVE", "DUE", "GRACE"]);

    if (error) return json({ error: error.message }, 500);

    const results = [];
    for (const sub of due ?? []) {
      const period = new Date(sub.next_due_date).toISOString().slice(0, 7); // YYYY-MM
      const { data: wallet } = await admin
        .from("wallets").select("balance").eq("provider_id", sub.provider_id).single();

      const fee = Number((await admin
        .from("system_settings").select("value").eq("key", "monthly_subscription_fee").single()
      ).data?.value ?? 5);

      if ((wallet?.balance ?? 0) >= fee) {
        const { data, error: rpcError } = await admin.rpc("deduct_subscription_fee", {
          p_provider_id: sub.provider_id,
          p_period: period,
        });
        results.push({ provider_id: sub.provider_id, charged: !rpcError, data, error: rpcError?.message });
      } else {
        // Move to grace or suspend based on how many days overdue.
        const daysOverdue = (Date.now() - new Date(sub.next_due_date).getTime()) / 86400000;
        const newStatus = daysOverdue > graceDays ? "SUSPENDED" : "GRACE";
        await admin.from("subscriptions").update({ status: newStatus }).eq("provider_id", sub.provider_id);
        if (newStatus === "SUSPENDED") {
          await admin.from("provider_profiles").update({ status: "SUSPENDED" }).eq("id", sub.provider_id);
        }
        const { data: pp } = await admin.from("provider_profiles").select("user_id").eq("id", sub.provider_id).single();
        if (pp) {
          await admin.from("notifications").insert({
            user_id: pp.user_id,
            type: "SUBSCRIPTION_DUE",
            title: newStatus === "SUSPENDED" ? "Account suspended" : "Subscription payment overdue",
            body: newStatus === "SUSPENDED"
              ? "Your account was suspended due to unpaid subscription. Recharge your wallet to reactivate."
              : "Insufficient wallet balance for subscription. Please recharge before grace period ends.",
          });
        }
        results.push({ provider_id: sub.provider_id, charged: false, status: newStatus });
      }
    }

    return json({ processed: results.length, results });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
