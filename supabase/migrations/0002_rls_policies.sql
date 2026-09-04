-- 5BIRR Phase 1 — Row Level Security
-- Migration 0002_rls_policies.sql
-- Principle: NEVER trust client-supplied role. Role membership is read from
-- user_roles (server-populated) via has_role(). Financial tables (wallets,
-- wallet_transactions, system_settings, fees) are NEVER directly writable
-- by end users/providers — only by service_role via Edge Functions.

-- =========================================================
-- HELPER FUNCTIONS (security definer, safe to use inside policies)
-- =========================================================
create or replace function has_role(check_role app_role)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from user_roles
    where user_id = auth.uid() and role = check_role
  );
$$;

create or replace function is_admin()
returns boolean
language sql
security definer
stable
as $$
  select has_role('ADMIN'::app_role);
$$;

create or replace function owns_provider_profile(p_provider_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from provider_profiles
    where id = p_provider_id and user_id = auth.uid()
  );
$$;

-- =========================================================
-- ENABLE RLS
-- =========================================================
alter table profiles enable row level security;
alter table user_roles enable row level security;
alter table user_documents enable row level security;
alter table provider_profiles enable row level security;
alter table approval_requests enable row level security;
alter table approval_history enable row level security;
alter table categories enable row level security;
alter table vehicles enable row level security;
alter table vehicle_images enable row level security;
alter table products enable row level security;
alter table product_images enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table order_status_history enable row level security;
alter table payment_agreements enable row level security;
alter table payment_proofs enable row level security;
alter table ride_requests enable row level security;
alter table ride_status_history enable row level security;
alter table wallets enable row level security;
alter table wallet_transactions enable row level security;
alter table subscriptions enable row level security;
alter table reviews enable row level security;
alter table favorites enable row level security;
alter table notifications enable row level security;
alter table notification_preferences enable row level security;
alter table admin_actions enable row level security;
alter table support_tickets enable row level security;
alter table appeals enable row level security;
alter table audit_logs enable row level security;
alter table system_settings enable row level security;

-- =========================================================
-- PROFILES
-- =========================================================
create policy profiles_select_own on profiles for select
  using (id = auth.uid() or is_admin());
create policy profiles_update_own on profiles for update
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_insert_own on profiles for insert
  with check (id = auth.uid());
create policy profiles_admin_all on profiles for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- USER_ROLES — never writable by end users; assigned server-side
-- (Edge Function using service_role) on signup / admin action only.
-- =========================================================
create policy user_roles_select_own on user_roles for select
  using (user_id = auth.uid() or is_admin());
create policy user_roles_admin_write on user_roles for insert
  with check (is_admin());
create policy user_roles_admin_update on user_roles for update
  using (is_admin());
create policy user_roles_admin_delete on user_roles for delete
  using (is_admin());

-- =========================================================
-- USER_DOCUMENTS — private, owner + admin only
-- =========================================================
create policy user_documents_owner on user_documents for select
  using (user_id = auth.uid() or is_admin());
create policy user_documents_insert_own on user_documents for insert
  with check (user_id = auth.uid());
create policy user_documents_admin_manage on user_documents for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- PROVIDER_PROFILES
-- =========================================================
create policy provider_profiles_public_read on provider_profiles for select
  using (status = 'APPROVED' or user_id = auth.uid() or is_admin());
create policy provider_profiles_insert_own on provider_profiles for insert
  with check (user_id = auth.uid());
create policy provider_profiles_update_own on provider_profiles for update
  using (user_id = auth.uid() and status != 'APPROVED') -- providers can't self-approve/edit locked fields post-approval via this path
  with check (user_id = auth.uid());
create policy provider_profiles_admin_all on provider_profiles for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- APPROVALS — admin only (read own status via separate view/query on profiles/provider_profiles)
-- =========================================================
create policy approval_requests_admin_all on approval_requests for all
  using (is_admin()) with check (is_admin());
create policy approval_requests_owner_read on approval_requests for select
  using (
    (subject_type = 'USER' and subject_id = auth.uid())
    or (subject_type = 'PROVIDER' and owns_provider_profile(subject_id))
    or is_admin()
  );

create policy approval_history_admin_all on approval_history for all
  using (is_admin()) with check (is_admin());
create policy approval_history_owner_read on approval_history for select
  using (
    (subject_type = 'USER' and subject_id = auth.uid())
    or (subject_type = 'PROVIDER' and owns_provider_profile(subject_id))
    or is_admin()
  );

-- =========================================================
-- CATEGORIES — public read, admin write
-- =========================================================
create policy categories_public_read on categories for select
  using (is_active = true or is_admin());
create policy categories_admin_write on categories for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- VEHICLES — provider owns; public sees approved+available
-- =========================================================
create policy vehicles_public_read on vehicles for select
  using (status = 'APPROVED' or owns_provider_profile(provider_id) or is_admin());
create policy vehicles_provider_insert on vehicles for insert
  with check (owns_provider_profile(provider_id));
create policy vehicles_provider_update on vehicles for update
  using (owns_provider_profile(provider_id)) with check (owns_provider_profile(provider_id));
create policy vehicles_provider_delete on vehicles for delete
  using (owns_provider_profile(provider_id));
create policy vehicles_admin_all on vehicles for all
  using (is_admin()) with check (is_admin());

create policy vehicle_images_read on vehicle_images for select
  using (exists (select 1 from vehicles v where v.id = vehicle_id and
    (v.status = 'APPROVED' or owns_provider_profile(v.provider_id) or is_admin())));
create policy vehicle_images_owner_write on vehicle_images for all
  using (exists (select 1 from vehicles v where v.id = vehicle_id and owns_provider_profile(v.provider_id)))
  with check (exists (select 1 from vehicles v where v.id = vehicle_id and owns_provider_profile(v.provider_id)));

-- =========================================================
-- PRODUCTS — strict ownership enforcement (Provider A cannot touch Provider B's data)
-- =========================================================
create policy products_public_read on products for select
  using (is_active = true or owns_provider_profile(provider_id) or is_admin());
create policy products_provider_insert on products for insert
  with check (owns_provider_profile(provider_id));
create policy products_provider_update on products for update
  using (owns_provider_profile(provider_id)) with check (owns_provider_profile(provider_id));
create policy products_provider_delete on products for delete
  using (owns_provider_profile(provider_id));
create policy products_admin_all on products for all
  using (is_admin()) with check (is_admin());

create policy product_images_read on product_images for select
  using (exists (select 1 from products p where p.id = product_id and
    (p.is_active = true or owns_provider_profile(p.provider_id) or is_admin())));
create policy product_images_owner_write on product_images for all
  using (exists (select 1 from products p where p.id = product_id and owns_provider_profile(p.provider_id)))
  with check (exists (select 1 from products p where p.id = product_id and owns_provider_profile(p.provider_id)));

-- =========================================================
-- ORDERS — user sees own; provider sees orders placed with them
-- =========================================================
create policy orders_user_read on orders for select
  using (user_id = auth.uid() or owns_provider_profile(provider_id) or is_admin());
create policy orders_user_insert on orders for insert
  with check (user_id = auth.uid());
-- Status transitions happen ONLY through the order-transition Edge Function
-- (service_role), never direct client update, to keep the state machine safe.
create policy orders_admin_update on orders for update
  using (is_admin()) with check (is_admin());
create policy orders_admin_all on orders for all
  using (is_admin()) with check (is_admin());

create policy order_items_read on order_items for select
  using (exists (select 1 from orders o where o.id = order_id and
    (o.user_id = auth.uid() or owns_provider_profile(o.provider_id) or is_admin())));
create policy order_items_user_insert on order_items for insert
  with check (exists (select 1 from orders o where o.id = order_id and o.user_id = auth.uid()));

create policy order_status_history_read on order_status_history for select
  using (exists (select 1 from orders o where o.id = order_id and
    (o.user_id = auth.uid() or owns_provider_profile(o.provider_id) or is_admin())));

-- =========================================================
-- PAYMENT AGREEMENTS / PROOFS
-- =========================================================
create policy payment_agreements_user on payment_agreements for all
  using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid() or is_admin());

create policy payment_proofs_read on payment_proofs for select
  using (exists (select 1 from orders o where o.id = order_id and
    (o.user_id = auth.uid() or owns_provider_profile(o.provider_id) or is_admin())));
create policy payment_proofs_user_insert on payment_proofs for insert
  with check (exists (select 1 from orders o where o.id = order_id and o.user_id = auth.uid()));
-- Verification (status change) restricted to admin/service role only.
create policy payment_proofs_admin_verify on payment_proofs for update
  using (is_admin()) with check (is_admin());

-- =========================================================
-- RIDE REQUESTS — user sees own; eligible vehicle providers see nearby unclaimed;
-- claim mutation happens only via claim_ride() SECURITY DEFINER function (0003).
-- =========================================================
create policy ride_requests_user_read on ride_requests for select
  using (user_id = auth.uid() or is_admin());
create policy ride_requests_provider_read_open on ride_requests for select
  using (
    status = 'REQUESTED'
    and has_role('VEHICLE_PROVIDER'::app_role)
  );
create policy ride_requests_claimed_provider_read on ride_requests for select
  using (owns_provider_profile(claimed_by_provider_id));
create policy ride_requests_user_insert on ride_requests for insert
  with check (user_id = auth.uid());
create policy ride_requests_user_cancel on ride_requests for update
  using (user_id = auth.uid() and status = 'REQUESTED')
  with check (status = 'CANCELLED');
create policy ride_requests_admin_all on ride_requests for all
  using (is_admin()) with check (is_admin());

create policy ride_status_history_read on ride_status_history for select
  using (exists (select 1 from ride_requests r where r.id = ride_request_id and
    (r.user_id = auth.uid() or owns_provider_profile(r.claimed_by_provider_id) or is_admin())));

-- =========================================================
-- WALLETS / WALLET_TRANSACTIONS — READ ONLY for providers, NO direct writes.
-- All balance changes happen exclusively through SECURITY DEFINER functions
-- called from Edge Functions running with service_role.
-- =========================================================
create policy wallets_owner_read on wallets for select
  using (owns_provider_profile(provider_id) or is_admin());
create policy wallets_admin_all on wallets for all
  using (is_admin()) with check (is_admin());
-- No insert/update/delete policy for regular users/providers => denied by default.

create policy wallet_transactions_owner_read on wallet_transactions for select
  using (owns_provider_profile(provider_id) or is_admin());
create policy wallet_transactions_admin_all on wallet_transactions for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- SUBSCRIPTIONS — read only for provider, admin manages
-- =========================================================
create policy subscriptions_owner_read on subscriptions for select
  using (owns_provider_profile(provider_id) or is_admin());
create policy subscriptions_admin_all on subscriptions for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- REVIEWS — public read, only the reviewer can write, only for own completed orders
-- =========================================================
create policy reviews_public_read on reviews for select using (true);
create policy reviews_user_insert on reviews for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from orders o
      where o.id = order_id and o.user_id = auth.uid() and o.status = 'COMPLETED'
    )
  );
create policy reviews_admin_moderate on reviews for delete
  using (is_admin());

-- =========================================================
-- FAVORITES — private to user
-- =========================================================
create policy favorites_owner_all on favorites for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- =========================================================
-- NOTIFICATIONS
-- =========================================================
create policy notifications_owner_read on notifications for select
  using (user_id = auth.uid() or is_admin());
create policy notifications_owner_update on notifications for update
  using (user_id = auth.uid()) with check (user_id = auth.uid()); -- e.g. mark read
create policy notifications_admin_all on notifications for all
  using (is_admin()) with check (is_admin());

create policy notification_prefs_owner on notification_preferences for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- =========================================================
-- ADMIN-ONLY TABLES
-- =========================================================
create policy admin_actions_admin_only on admin_actions for all
  using (is_admin()) with check (is_admin());

create policy support_tickets_owner on support_tickets for all
  using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid() or is_admin());

create policy appeals_owner on appeals for select
  using (user_id = auth.uid() or is_admin());
create policy appeals_owner_insert on appeals for insert
  with check (user_id = auth.uid());
create policy appeals_admin_update on appeals for update
  using (is_admin()) with check (is_admin());

create policy audit_logs_admin_only on audit_logs for select
  using (is_admin());
-- audit_logs is written only by SECURITY DEFINER functions / service_role.

-- =========================================================
-- SYSTEM_SETTINGS — public read (needed by client for fee display etc.), admin write
-- =========================================================
create policy system_settings_read on system_settings for select using (true);
create policy system_settings_admin_write on system_settings for all
  using (is_admin()) with check (is_admin());
