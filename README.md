# 5BIRR — Phase 1

Location-based multi-sector marketplace (products, food, shops, services,
hotels, transportation). Users pay no platform fee; providers pay a
configurable 5 Birr/month subscription (starting one month after
registration) plus a configurable 5 Birr fee per completed transaction.

This Phase 1 delivers the hard-to-reproduce backend foundation: schema, RLS,
atomic ride claiming, idempotent wallet/fee logic, order state machine,
provider approval workflow, and the Flutter/Supabase project skeleton.

## File tree

```
supabase/
  migrations/
    0001_core_schema.sql      # tables, enums, indexes, PostGIS
    0002_rls_policies.sql     # row level security, has_role()/is_admin()
    0003_functions.sql        # claim_ride, fee deduction, order FSM, approvals
    0004_seed.sql              # categories seed + admin bootstrap notes
  functions/                   # Edge Functions (Deno)
    _shared/client.ts
    ride-claim/index.ts
    wallet-deduct-fee/index.ts
    provider-approval/index.ts
    order-transition/index.ts
    subscription-process/index.ts
  tests/
    ride_claim_race_test.sql   # concurrency + idempotency test harness
lib/                            # Flutter app skeleton
  core/config/env.dart
  core/services/supabase_service.dart
  features/auth/admin_gate.dart
  features/vehicle/ride_repository.dart
  features/{user,provider,vehicle,admin}/   # placeholders for Phase 2
n8n/README.md                  # workflow specs
pubspec.yaml
.env.example
.gitignore
```

## Setup

### 1. Supabase project
```bash
supabase init            # if not already a supabase project
supabase link --project-ref YOUR_PROJECT_REF
supabase db push          # applies migrations 0001-0004 in order
```
Or manually via SQL editor in order: 0001 → 0002 → 0003 → 0004.

Enable PostGIS extension is handled by migration 0001 (`create extension postgis`).

### 2. Storage buckets (private)
```bash
supabase storage create user-documents --no-public
supabase storage create payment-proofs --no-public
supabase storage create product-images  # public read is fine for listing images
supabase storage create vehicle-images
```
Access sensitive buckets (`user-documents`, `payment-proofs`) only via
signed URLs generated server-side (Edge Function or admin client) — never
mark them public.

### 3. Dev admin bootstrap
```bash
supabase auth admin create-user \
  --email admin@5birr.dev \
  --password "$DEV_ADMIN_SEED_PASSWORD"
# then, using the returned UUID:
psql "$DATABASE_URL" -c "insert into user_roles (user_id, role) values ('<uuid>','ADMIN');"
psql "$DATABASE_URL" -c "insert into profiles (id, full_name, status) values ('<uuid>','Dev Admin','APPROVED');"
```
The `77777` value in the original spec is a **dev-only UI convenience**
(tap the logo 5x to reveal the admin login route) — it is not a real
credential and must never be embedded in shipped code. Real admin
authorization is enforced entirely by `has_role('ADMIN')` in RLS/functions.

### 4. Edge Functions
```bash
supabase functions deploy ride-claim
supabase functions deploy wallet-deduct-fee
supabase functions deploy provider-approval
supabase functions deploy order-transition
supabase functions deploy subscription-process
supabase secrets set N8N_SHARED_SECRET=your-long-random-string
```

### 5. Flutter
```bash
cp .env.example .env      # fill in real values, keep out of git
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
  --dart-define=GOOGLE_MAPS_API_KEY=$GOOGLE_MAPS_API_KEY
```

### 6. Tests
```bash
psql "$DATABASE_URL" -f supabase/tests/ride_claim_race_test.sql
```
This verifies: (a) only one of two concurrent `claim_ride()` calls on the
same ride succeeds, and (b) `deduct_transaction_fee()` never double-charges
on retry with the same idempotency key.

### 7. GitHub
```bash
git init
git add .
git commit -m "5BIRR Phase 1: schema, RLS, wallet/fee, ride claim, order FSM, Flutter skeleton"
git remote add origin <your-repo-url>
git push -u origin main
```
`.gitignore` already excludes `.env` and build artifacts. No secrets are
committed — `.env.example` has placeholders only.

---

## Phase 2 handoff

### What's complete
- **Database**: full normalized schema (`0001`) — profiles, roles, provider
  profiles, documents, categories/subcategories, vehicles, products, orders,
  ride requests, wallets, subscriptions, reviews, favorites, notifications,
  admin/audit tables. PostGIS geography columns + GIST indexes for location.
  Full-text search (`tsvector`) + trigram index on products.
- **RLS**: enabled on every table. `has_role()`/`is_admin()`/
  `owns_provider_profile()` helper functions. Strict ownership enforced on
  products/vehicles (Provider A cannot touch Provider B's rows). Wallets and
  fees have **no** direct write policy for end users — writes only via
  SECURITY DEFINER functions invoked from Edge Functions.
- **Atomic ride claim**: `claim_ride()` — conditional `UPDATE ... WHERE
  status = 'REQUESTED'` plus a partial unique index guarantees exactly one
  winner under concurrency. Tested in `ride_claim_race_test.sql`.
- **Wallet/fee engine**: `deduct_transaction_fee()` and
  `deduct_subscription_fee()`, both idempotent via a unique
  `idempotency_key` on `wallet_transactions`. Configurable fee amounts read
  from `system_settings` (defaults: 5 Birr / 5 Birr).
- **Order state machine**: `transition_order_status()` enforces a whitelist
  of legal transitions and blocks entry to `APPROVED` unless a verified
  payment proof exists when required. Fee auto-charged on `STARTED`.
- **Provider approval workflow**: `approve_provider()` /
  `reject_provider()` — creates wallet + subscription row on approval,
  writes `approval_history` (never overwrites), sends notifications.
- **Edge Functions**: `ride-claim`, `wallet-deduct-fee`, `provider-approval`,
  `order-transition`, `subscription-process` (n8n-triggered, shared-secret
  auth). All re-validate caller identity/role server-side — the Flutter
  client's claimed role is never trusted.
- **n8n architecture**: documented workflows for subscription billing,
  low-wallet sweeps, registration/approval notifications, inactivity, and
  weekly rankings (`n8n/README.md`).
- **Flutter skeleton**: `Env`/`SupabaseService` (env-driven config, no
  hard-coded secrets), `AdminGate` (5-tap logo reveal — cosmetic only),
  `RideRepository` example calling the `ride-claim` function. `pubspec.yaml`
  with Supabase, Maps, Geolocator, FCM, go_router, Riverpod.

### What remains for Phase 2
- Flutter screens/navigation for the full flow listed in spec §40 (splash,
  role selection, signup forms, dashboards, search, product/provider detail,
  order flow, ride flow, wallet UI, notifications, admin panel UI).
- Full admin panel UI (approve/reject queues, category CRUD, analytics
  dashboards per spec §10/§29).
- Search Edge Function/RPC combining full-text + geo radius + ranking
  signals (index and `tsvector` are ready; ranking query itself is next).
- Storage signed-URL helper functions for documents/payment proofs.
- FCM push delivery wiring (topic/token management table).
- Google Maps screens: pickup/destination picker, live tracking, ETA calc.
- Play Store production build config (signing, package ID, permissions
  manifest, privacy policy).
- Additional order-type-specific state machines if hotel/food/service need
  divergent flows beyond the generic one shipped here.
- n8n workflow JSON exports (currently specified as docs; import-ready JSON
  is a fast Phase 2 task once the n8n instance URL is fixed).

### How to continue without rebuilding
- Migrations are sequential (`0001`-`0004`) — add `0005_*.sql` onward; never
  edit shipped migrations once applied to a real environment.
- All new privileged mutations should follow the same pattern: a SQL
  SECURITY DEFINER function + a thin Edge Function wrapper that validates
  the caller before invoking it via the service-role client.
- `system_settings` is the single source of truth for fee/business-rule
  values — read from it, don't hard-code new constants.
- TODOs are intentionally not scattered as comments; the "what remains"
  list above is the authoritative Phase 2 backlog.
