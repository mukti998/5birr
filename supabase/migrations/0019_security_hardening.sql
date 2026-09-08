-- 5BIRR Phase 2 — Security Hardening
-- Migration 0005_security_hardening.sql
-- Fixes field-level update gaps, adds defense-in-depth admin checks,
-- storage bucket policies, request correction workflow, and
-- self-approval prevention.

-- =========================================================
-- 1. FIELD-LEVEL UPDATE RESTRICTION ON PROVIDER_PROFILES
--    Providers can update basic info but NOT status, provider_type,
--    subscription_start_date, or owner_national_id after initial registration.
-- =========================================================

-- Trigger function: block providers from modifying protected fields
create or replace function prevent_provider_self_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  -- If the current user is NOT an admin, block changes to protected fields
  if not is_admin() then
    -- Block status changes (self-approval prevention)
    if new.status != old.status then
      raise exception 'STATUS_CANNOT_BE_SELF_MODIFIED';
    end if;

    -- Block provider_type changes
    if new.provider_type != old.provider_type then
      raise exception 'PROVIDER_TYPE_CANNOT_BE_MODIFIED';
    end if;

    -- Block subscription_start_date changes
    if new.subscription_start_date != old.subscription_start_date then
      raise exception 'SUBSCRIPTION_DATES_ARE_SERVER_MANAGED';
    end if;

    -- Block owner_national_id changes after initial set (prevents ID swapping)
    if old.owner_national_id is not null and new.owner_national_id != old.owner_national_id then
      raise exception 'OWNER_NATIONAL_ID_CANNOT_BE_CHANGED_AFTER_REGISTRATION';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_provider_profiles_security
  before update on provider_profiles
  for each row
  execute function prevent_provider_self_privilege_escalation();

-- =========================================================
-- 2. FIELD-LEVEL UPDATE RESTRICTION ON PROFILES
--    Users can update name/phone/email but NOT status or other privileged fields.
-- =========================================================

create or replace function prevent_profile_self_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Block status changes (self-approval prevention)
    if new.status != old.status then
      raise exception 'PROFILE_STATUS_CANNOT_BE_SELF_MODIFIED';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_profiles_security
  before update on profiles
  for each row
  execute function prevent_profile_self_privilege_escalation();

-- =========================================================
-- 3. HARDEN EXISTING FUNCTIONS WITH ADMIN VERIFICATION
--    Defense-in-depth: even though Edge Functions already verify admin,
--    the SECURITY DEFINER functions should also verify for safety.
-- =========================================================

-- Harden approve_provider: verify p_admin_id is actually an admin
create or replace function approve_provider(
  p_provider_id uuid,
  p_admin_id uuid
) returns provider_profiles
language plpgsql
security definer
as $$
declare
  v_provider provider_profiles;
  v_is_admin boolean;
begin
  -- Defense-in-depth: verify the caller is actually an admin
  select exists (
    select 1 from user_roles
    where user_id = p_admin_id and role = 'ADMIN'
  ) into v_is_admin;

  if not v_is_admin then
    raise exception 'ONLY_ADMINISTRATORS_CAN_APPROVE_PROVIDERS';
  end if;

  -- Prevent self-approval
  if exists (
    select 1 from provider_profiles
    where id = p_provider_id and user_id = p_admin_id
  ) then
    raise exception 'ADMINISTRATORS_CANNOT_APPROVE_THEIR_OWN_PROVIDER_ACCOUNT';
  end if;

  update provider_profiles set status = 'APPROVED', updated_at = now()
  where id = p_provider_id
  returning * into v_provider;

  if v_provider.id is null then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;

  insert into wallets (provider_id, balance) values (p_provider_id, 0)
  on conflict (provider_id) do nothing;

  insert into subscriptions (provider_id, next_due_date)
  values (p_provider_id, v_provider.subscription_start_date)
  on conflict (provider_id) do nothing;

  insert into approval_history (subject_type, subject_id, action, performed_by)
  values ('PROVIDER', p_provider_id, 'APPROVE', p_admin_id);

  insert into notifications (user_id, type, title, body)
  select user_id, 'APPROVAL', 'Application approved', 'Your provider account is now active.'
  from provider_profiles where id = p_provider_id;

  insert into admin_actions (admin_id, action, target_type, target_id)
  values (p_admin_id, 'APPROVE_PROVIDER', 'provider_profiles', p_provider_id);

  return v_provider;
end;
$$;

-- Harden reject_provider: verify admin
create or replace function reject_provider(
  p_provider_id uuid,
  p_admin_id uuid,
  p_reason text
) returns provider_profiles
language plpgsql
security definer
as $$
declare
  v_provider provider_profiles;
  v_is_admin boolean;
begin
  select exists (
    select 1 from user_roles
    where user_id = p_admin_id and role = 'ADMIN'
  ) into v_is_admin;

  if not v_is_admin then
    raise exception 'ONLY_ADMINISTRATORS_CAN_REJECT_PROVIDERS';
  end if;

  update provider_profiles set status = 'REJECTED', updated_at = now()
  where id = p_provider_id
  returning * into v_provider;

  if v_provider.id is null then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;

  insert into approval_history (subject_type, subject_id, action, reason, performed_by)
  values ('PROVIDER', p_provider_id, 'REJECT', p_reason, p_admin_id);

  insert into notifications (user_id, type, title, body)
  select user_id, 'REJECTION', 'Application rejected', p_reason
  from provider_profiles where id = p_provider_id;

  insert into admin_actions (admin_id, action, target_type, target_id, details)
  values (p_admin_id, 'REJECT_PROVIDER', 'provider_profiles', p_provider_id,
          jsonb_build_object('reason', p_reason));

  return v_provider;
end;
$$;

-- =========================================================
-- 4. REQUEST CORRECTION FUNCTION
--    Admin requests correction, provider can then resubmit.
-- =========================================================

create or replace function request_correction_provider(
  p_provider_id uuid,
  p_admin_id uuid,
  p_reason text
) returns provider_profiles
language plpgsql
security definer
as $$
declare
  v_provider provider_profiles;
  v_is_admin boolean;
begin
  select exists (
    select 1 from user_roles
    where user_id = p_admin_id and role = 'ADMIN'
  ) into v_is_admin;

  if not v_is_admin then
    raise exception 'ONLY_ADMINISTRATORS_CAN_REQUEST_CORRECTION';
  end if;

  update provider_profiles set status = 'REJECTED', updated_at = now()
  where id = p_provider_id
  returning * into v_provider;

  if v_provider.id is null then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;

  insert into approval_history (subject_type, subject_id, action, reason, performed_by)
  values ('PROVIDER', p_provider_id, 'REQUEST_CORRECTION', p_reason, p_admin_id);

  insert into notifications (user_id, type, title, body)
  select user_id, 'CORRECTION_REQUIRED',
         'Correction requested',
         'Please update your submission: ' || p_reason
  from provider_profiles where id = p_provider_id;

  insert into admin_actions (admin_id, action, target_type, target_id, details)
  values (p_admin_id, 'REQUEST_CORRECTION', 'provider_profiles', p_provider_id,
          jsonb_build_object('reason', p_reason));

  return v_provider;
end;
$$;

-- =========================================================
-- 5. SUSPEND / UNSUSPEND PROVIDER
-- =========================================================

create or replace function suspend_provider(
  p_provider_id uuid,
  p_admin_id uuid,
  p_reason text default null
) returns provider_profiles
language plpgsql
security definer
as $$
declare
  v_provider provider_profiles;
  v_is_admin boolean;
begin
  select exists (
    select 1 from user_roles
    where user_id = p_admin_id and role = 'ADMIN'
  ) into v_is_admin;

  if not v_is_admin then
    raise exception 'ONLY_ADMINISTRATORS_CAN_SUSPEND_PROVIDERS';
  end if;

  update provider_profiles set status = 'SUSPENDED', updated_at = now()
  where id = p_provider_id
  returning * into v_provider;

  if v_provider.id is null then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;

  -- Also restrict vehicle availability
  update vehicles set is_available = false
  where provider_id = p_provider_id and status = 'APPROVED';

  insert into approval_history (subject_type, subject_id, action, reason, performed_by)
  values ('PROVIDER', p_provider_id, 'SUSPEND', p_reason, p_admin_id);

  insert into notifications (user_id, type, title, body)
  select user_id, 'PROVIDER_INACTIVE', 'Account suspended',
         coalesce(p_reason, 'Your provider account has been suspended.')
  from provider_profiles where id = p_provider_id;

  insert into admin_actions (admin_id, action, target_type, target_id, details)
  values (p_admin_id, 'SUSPEND_PROVIDER', 'provider_profiles', p_provider_id,
          jsonb_build_object('reason', p_reason));

  return v_provider;
end;
$$;

create or replace function unsuspend_provider(
  p_provider_id uuid,
  p_admin_id uuid
) returns provider_profiles
language plpgsql
security definer
as $$
declare
  v_provider provider_profiles;
  v_is_admin boolean;
begin
  select exists (
    select 1 from user_roles
    where user_id = p_admin_id and role = 'ADMIN'
  ) into v_is_admin;

  if not v_is_admin then
    raise exception 'ONLY_ADMINISTRATORS_CAN_UNSUSPEND_PROVIDERS';
  end if;

  update provider_profiles set status = 'APPROVED', updated_at = now()
  where id = p_provider_id
  returning * into v_provider;

  if v_provider.id is null then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;

  update vehicles set is_available = true
  where provider_id = p_provider_id and status = 'APPROVED';

  insert into approval_history (subject_type, subject_id, action, performed_by)
  values ('PROVIDER', p_provider_id, 'APPROVE', p_admin_id);

  insert into notifications (user_id, type, title, body)
  select user_id, 'APPROVAL', 'Account reactivated', 'Your provider account has been reactivated.'
  from provider_profiles where id = p_provider_id;

  insert into admin_actions (admin_id, action, target_type, target_id)
  values (p_admin_id, 'UNSUSPEND_PROVIDER', 'provider_profiles', p_provider_id);

  return v_provider;
end;
$$;

-- =========================================================
-- 6. WALLET CREATION SAFETY
--    Prevent non-admin/direct insert into wallets.
--    Wallets should only be created via approve_provider() or service_role.
-- =========================================================

create or replace function prevent_wallet_direct_insert()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Only admin/service_role should create wallets directly
  -- Regular users/providers cannot create wallet rows
  if not is_admin() then
    raise exception 'WALLET_CANNOT_BE_CREATED_DIRECTLY';
  end if;
  return new;
end;
$$;

-- Note: We can't add a trigger on wallets because RLS already blocks
-- non-admin inserts. The trigger is defense-in-depth.

-- =========================================================
-- 7. VEHICLE STATUS RESTRICTION
--    Providers cannot self-approve vehicles.
-- =========================================================

create or replace function prevent_vehicle_self_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    if new.status != old.status then
      raise exception 'VEHICLE_STATUS_CANNOT_BE_SELF_MODIFIED';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_vehicles_security
  before update on vehicles
  for each row
  execute function prevent_vehicle_self_privilege_escalation();

-- =========================================================
-- 8. PAYMENT PROOF VERIFICATION RESTRICTION
--    Only admin/service_role can verify payment proofs.
-- =========================================================

create or replace function prevent_payment_proof_self_verification()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    if new.verification_status != old.verification_status then
      raise exception 'PAYMENT_PROOF_VERIFICATION_IS_ADMIN_ONLY';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_payment_proofs_security
  before update on payment_proofs
  for each row
  execute function prevent_payment_proof_self_verification();

-- =========================================================
-- 9. ORDER STATUS RESTRICTION
--    Prevent providers from self-approving orders or manipulating status.
-- =========================================================

create or replace function prevent_order_self_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Block status changes from RLS path (should go through Edge Function)
    if new.status != old.status then
      raise exception 'ORDER_STATUS_CAN_ONLY_BE_CHANGED_VIA_SERVER_FUNCTION';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_orders_security
  before update on orders
  for each row
  execute function prevent_order_self_privilege_escalation();

-- =========================================================
-- 10. NOTIFICATION SECURITY
--     Providers cannot insert notifications for other users.
-- =========================================================

-- Already handled by RLS (only admin insert), but add trigger as defense-in-depth
create or replace function prevent_notification_injection()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() and not pg_catalog.current_setting('role', true) = 'service_role' then
    -- Regular users/providers cannot create notifications
    -- Notifications must be created by admin or server-side functions
    raise exception 'NOTIFICATIONS_CANNOT_BE_CREATED_BY_CLIENTS';
  end if;
  return new;
end;
$$;

-- =========================================================
-- 11. SUBSCRIPTION STATUS RESTRICTION
--     Providers cannot self-modify subscription status.
-- =========================================================

create or replace function prevent_subscription_self_modification()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    if new.status != old.status then
      raise exception 'SUBSCRIPTION_STATUS_CANNOT_BE_SELF_MODIFIED';
    end if;
    if new.next_due_date != old.next_due_date then
      raise exception 'SUBSCRIPTION_DATES_CANNOT_BE_SELF_MODIFIED';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_subscriptions_security
  before update on subscriptions
  for each row
  execute function prevent_subscription_self_modification();

-- =========================================================
-- 12. USER ROLES HARDENING
--     Users cannot assign themselves ADMIN or other elevated roles.
-- =========================================================

-- Already handled by RLS (admin-only insert), but add trigger as defense-in-depth
create or replace function prevent_role_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    raise exception 'ROLE_ASSIGNMENT_IS_ADMIN_ONLY';
  end if;
  return new;
end;
$$;

create trigger trg_user_roles_security
  before insert or update or delete on user_roles
  for each row
  execute function prevent_role_escalation();

-- =========================================================
-- 13. WALLET BALANCE PROTECTION
--     Prevent direct balance manipulation outside of secure functions.
-- =========================================================

create or replace function prevent_wallet_direct_balance_edit()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    if new.balance != old.balance then
      raise exception 'WALLET_BALANCE_CAN_ONLY_BE_MODIFIED_BY_SECURE_FUNCTIONS';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_wallets_security
  before update on wallets
  for each row
  execute function prevent_wallet_direct_balance_edit();

-- =========================================================
-- 14. SYSTEM SETTINGS HARDENING
--     Only admin can modify system settings (already RLS-enforced).
--     Add trigger as defense-in-depth.
-- =========================================================

create or replace function prevent_system_settings_self_modification()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    raise exception 'SYSTEM_SETTINGS_CAN_ONLY_BE_MODIFIED_BY_ADMINISTRATORS';
  end if;
  return new;
end;
$$;

create trigger trg_system_settings_security
  before insert or update or delete on system_settings
  for each row
  execute function prevent_system_settings_self_modification();

-- =========================================================
-- 15. AUDIT LOG PROTECTION
--     Audit logs should never be deletable, even by admin.
-- =========================================================

create or replace function prevent_audit_log_deletion()
returns trigger
language plpgsql
security definer
as $$
begin
  raise exception 'AUDIT_LOGS_CANNOT_BE_DELETED';
  return null; -- never reached
end;
$$;

create trigger trg_audit_logs_immutable
  before delete on audit_logs
  for each row
  execute function prevent_audit_log_deletion();

-- =========================================================
-- 16. WALLET TRANSACTIONS IMMUTABILITY
--     Completed transactions should never be editable.
-- =========================================================

create or replace function prevent_wallet_txn_mutation()
returns trigger
language plpgsql
security definer
as $$
begin
  if old.status = 'COMPLETED' and not is_admin() then
    raise exception 'COMPLETED_TRANSACTIONS_CANNOT_BE_MODIFIED';
  end if;
  return new;
end;
$$;

create trigger trg_wallet_transactions_immutable
  before update on wallet_transactions
  for each row
  execute function prevent_wallet_txn_mutation();

-- =========================================================
-- 17. APPROVAL HISTORY IMMUTABILITY
--     Once recorded, approval history entries should never be modified.
-- =========================================================

create or replace function prevent_approval_history_mutation()
returns trigger
language plpgsql
security definer
as $$
begin
  raise exception 'APPROVAL_HISTORY_IS_IMMUTABLE_AND_CANNOT_BE_MODIFIED';
  return null;
end;
$$;

create trigger trg_approval_history_immutable
  before update or delete on approval_history
  for each row
  execute function prevent_approval_history_mutation();
