# n8n Integration — 5BIRR

n8n handles **notification/scheduling orchestration only**. All financial
mutations happen inside Postgres SECURITY DEFINER functions or Edge
Functions, never inside n8n itself, per the spec's requirement that critical
financial integrity not depend on n8n.

## Auth pattern
Every webhook n8n calls on Supabase Edge Functions must send:
```
X-N8N-SECRET: <N8N_SHARED_SECRET>
```
Edge Functions validate this header against the `N8N_SHARED_SECRET` env var.
n8n itself should be triggered by its own internal Cron/Schedule nodes, not
exposed publicly without auth.

## Workflow 1 — Daily Subscription Processing
- Trigger: Cron, daily at 02:00 local time.
- HTTP Request node → `POST {SUPABASE_URL}/functions/v1/subscription-process`
  with header `X-N8N-SECRET`.
- The function itself finds all due subscriptions, charges idempotently,
  applies grace/suspension, and writes notifications. n8n just needs to
  fire it and log the JSON response.

## Workflow 2 — Low/Zero Wallet Watch
- Trigger: Cron, every 6 hours.
- Query `wallet_transactions` / `wallets` via Supabase REST (service role)
  for balances under `low_wallet_threshold`.
- For each: notification is already written by `deduct_transaction_fee()`
  when the threshold is crossed — this workflow is a secondary sweep/digest,
  e.g. daily summary email/SMS to providers who are still low after 24h.

## Workflow 3 — New Registration / Approval Notifications
- Trigger: Supabase Database Webhook (Postgres `INSERT` on
  `approval_requests`, or `notifications` table insert) → n8n Webhook node.
- Route by `type` column to the right channel: push (FCM), SMS, or email.

## Workflow 4 — Provider Inactivity Sweep
- Trigger: Cron, daily.
- Find providers with no orders/rides in N days (configurable) → flag via
  `notifications` insert + optional admin_actions log entry for review.

## Workflow 5 — Weekly Best-Performer Calculation
- Trigger: Cron, weekly.
- Aggregate `orders`/`ride_requests` completed in the window, rank by
  provider, write results to a `weekly_rankings` table (Phase 2) or directly
  update a `is_featured`/`rank` column consumed by the search/discovery
  Edge Function.

## Secrets
Store `N8N_SHARED_SECRET` and Supabase service role key inside n8n's
credential store — never inline in workflow JSON that gets exported/shared.
