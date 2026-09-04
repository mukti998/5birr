-- 5BIRR Phase 2 — Security Hardening (Continued)
-- Migration 0008_security_hardening_phase2.sql
-- Fixes remaining gaps identified in the Phase 1 + Phase 2 audit.

-- =========================================================
-- 1. FIX PROVIDER RESUBMISSION
--    The trigger from 0005 blocks ALL non-admin status changes,
--    including the legitimate REJECTED -> PENDING_APPROVAL transition
--    providers need after correcting their application.
-- =========================================================

create or replace function prevent_provider_self_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Allow REJECTED -> PENDING_APPROVAL (resubmission after correction)
    if old.status = 'REJECTED' and new.status = 'PENDING_APPROVAL' then
      return new;
    end if;

    -- Block all other status changes (self-approval prevention)
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

    -- Block owner_national_id changes after initial set
    if old.owner_national_id is not null and new.owner_national_id != old.owner_national_id then
      raise exception 'OWNER_NATIONAL_ID_CANNOT_BE_CHANGED_AFTER_REGISTRATION';
    end if;
  end if;

  return new;
end;
$$;

-- =========================================================
-- 2. ATTACH MISSING NOTIFICATION INJECTION TRIGGER
--    The function was created in 0005 but never attached.
-- =========================================================

create trigger trg_notifications_security
  before insert on notifications
  for each row
  execute function prevent_notification_injection();

-- =========================================================
-- 3. AUTO-CREATE APPROVAL REQUESTS ON SIGNUP
--    Users cannot directly insert into approval_requests (RLS blocks it).
--    This trigger auto-creates the approval request when a new profile
--    is inserted, ensuring the approval workflow starts correctly.
-- =========================================================

create or replace function auto_create_user_approval_request()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into approval_requests (subject_type, subject_id, status)
  values ('USER', NEW.id, 'PENDING_APPROVAL');
  return NEW;
end;
$$;

create trigger trg_profiles_auto_approval_request
  after insert on profiles
  for each row
  execute function auto_create_user_approval_request();

-- =========================================================
-- 4. AUTO-CREATE PROVIDER APPROVAL REQUEST + ROLE
--    When a provider_profile is created, auto-create the approval
--    request and assign the role. This replaces the broken client-side
--    inserts that were blocked by RLS.
-- =========================================================

create or replace function auto_setup_provider_on_create()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Clean up any user-level approval request since provider approval
  -- supersedes it — avoids the admin seeing duplicate pending requests.
  delete from approval_requests
  where subject_type = 'USER' and subject_id = NEW.user_id;

  -- Auto-create approval request for the provider
  insert into approval_requests (subject_type, subject_id, status)
  values ('PROVIDER', NEW.id, 'PENDING_APPROVAL');

  -- Auto-assign the provider role (prevents client self-role-assignment)
  insert into user_roles (user_id, role)
  values (NEW.user_id, NEW.provider_type)
  on conflict (user_id, role) do nothing;

  return NEW;
end;
$$;

create trigger trg_provider_profiles_auto_setup
  after insert on provider_profiles
  for each row
  execute function auto_setup_provider_on_create();

-- =========================================================
-- 5. SUPPORT TICKETS — RESTRICT USER STATUS MANIPULATION
--    Users should only be able to create tickets (OPEN) and
--    close their own (CLOSED). Admin manages full lifecycle.
-- =========================================================

create or replace function prevent_support_ticket_status_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- On insert: new tickets must start as OPEN
    if TG_OP = 'INSERT' and new.status != 'OPEN' then
      raise exception 'NEW_TICKETS_MUST_START_AS_OPEN';
    end if;

    -- On update: users can only close their own tickets
    if TG_OP = 'UPDATE' and new.status != old.status and new.status != 'CLOSED' then
      raise exception 'USERS_CAN_ONLY_CLOSE_THEIR_OWN_TICKETS';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_support_tickets_security
  before insert or update on support_tickets
  for each row
  execute function prevent_support_ticket_status_escalation();

-- =========================================================
-- 6. PAYMENT AGREEMENTS — PREVENT UN-ACCEPTING
--    Once a user accepts a payment agreement, they should not
--    be able to toggle it back to unaccepted.
-- =========================================================

create or replace function prevent_payment_agreement_unaccept()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Block un-accepting an already accepted agreement
    if old.accepted = true and new.accepted = false then
      raise exception 'ACCEPTED_AGREEMENTS_CANNOT_BE_UNACCEPTED';
    end if;

    -- Auto-set accepted_at when accepting
    if new.accepted = true and (old.accepted = false or old.accepted is null) then
      new.accepted_at := now();
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_payment_agreements_security
  before update on payment_agreements
  for each row
  execute function prevent_payment_agreement_unaccept();

-- =========================================================
-- 7. ORDER TRANSITION — ADD ROLE-BASED VALIDATION
--    Prevent actors from performing transitions that are not
--    authorized for their role. This adds defense-in-depth
--    beyond the Edge Function caller validation.
-- =========================================================

create or replace function transition_order_status(
  p_order_id uuid,
  p_new_status order_status,
  p_actor uuid,
  p_note text default null
) returns orders
language plpgsql
security definer
as $$
declare
  v_order orders;
  v_old order_status;
  v_valid boolean := false;
  v_actor_is_provider boolean := false;
  v_actor_is_admin boolean := false;
begin
  select * into v_order from orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  v_old := v_order.status;

  -- Determine actor's role for transition authorization
  select exists (
    select 1 from user_roles where user_id = p_actor and role = 'ADMIN'
  ) into v_actor_is_admin;

  select exists (
    select 1 from provider_profiles
    where id = v_order.provider_id and user_id = p_actor
  ) into v_actor_is_provider;

  -- Whitelist valid transitions with role authorization
  v_valid := case v_old
    when 'CREATED' then
      -- Only the buyer (user_id) or admin can cancel a fresh order
      p_new_status in ('PENDING_PROVIDER','CANCELLED')
      and (v_order.user_id = p_actor or v_actor_is_admin)

    when 'PENDING_PROVIDER' then
      -- Only the owning provider or admin can accept/reject
      (p_new_status in ('ACCEPTED','REJECTED')
        and (v_actor_is_provider or v_actor_is_admin))
      or (p_new_status = 'CANCELLED'
        and (v_order.user_id = p_actor or v_actor_is_admin))

    when 'ACCEPTED' then
      -- Provider moves to payment pending, or admin/buyer cancels
      (p_new_status = 'PAYMENT_PENDING' and (v_actor_is_provider or v_actor_is_admin))
      or (p_new_status = 'CANCELLED' and (v_order.user_id = p_actor or v_actor_is_admin))

    when 'PAYMENT_PENDING' then
      -- Buyer submits proof (payment_verification), or admin cancels
      (p_new_status = 'PAYMENT_VERIFICATION' and v_order.user_id = p_actor)
      or (p_new_status = 'CANCELLED' and v_actor_is_admin)

    when 'PAYMENT_VERIFICATION' then
      -- Only admin can verify or reject payment
      p_new_status in ('APPROVED','REJECTED') and v_actor_is_admin

    when 'APPROVED' then
      -- Provider or admin starts the order; buyer or admin cancels
      (p_new_status = 'STARTED' and (v_actor_is_provider or v_actor_is_admin))
      or (p_new_status = 'CANCELLED' and (v_order.user_id = p_actor or v_actor_is_admin))

    when 'STARTED' then
      -- Provider or admin completes; buyer or admin disputes/cancels
      (p_new_status = 'COMPLETED' and (v_actor_is_provider or v_actor_is_admin))
      or (p_new_status in ('DISPUTED','CANCELLED')
        and (v_order.user_id = p_actor or v_actor_is_admin))

    when 'COMPLETED' then
      -- Buyer or admin can dispute/refund
      p_new_status in ('DISPUTED','REFUNDED')
      and (v_order.user_id = p_actor or v_actor_is_admin)

    when 'DISPUTED' then
      -- Admin resolves dispute
      p_new_status in ('REFUNDED','COMPLETED') and v_actor_is_admin

    else false
  end;

  if not v_valid then
    raise exception 'INVALID_TRANSITION_%_TO_%_FOR_ACTOR', v_old, p_new_status;
  end if;

  -- Enforce payment-proof rule before entering the protected APPROVED stage.
  if p_new_status = 'APPROVED' and v_order.requires_payment_proof then
    if not exists (
      select 1 from payment_proofs
      where order_id = p_order_id and verification_status = 'VERIFIED'
    ) then
      raise exception 'PAYMENT_PROOF_REQUIRED';
    end if;
  end if;

  update orders set status = p_new_status, updated_at = now()
  where id = p_order_id
  returning * into v_order;

  insert into order_status_history (order_id, from_status, to_status, changed_by, note)
  values (p_order_id, v_old, p_new_status, p_actor, p_note);

  -- Charge the platform transaction fee exactly once on STARTED
  if p_new_status = 'STARTED' then
    perform deduct_transaction_fee(
      v_order.provider_id, p_order_id, null, v_order.total_amount,
      'order:' || p_order_id::text
    );
  end if;

  return v_order;
end;
$$;

-- =========================================================
-- 8. RIDE STATUS TRANSITION — ADD ROLE-BASED VALIDATION
--    Ensure only the claiming provider, the ride owner, or admin
--    can perform ride status transitions.
-- =========================================================

create or replace function transition_ride_status(
  p_ride_id uuid,
  p_new_status ride_status,
  p_actor uuid
) returns ride_requests
language plpgsql
security definer
as $$
declare
  v_ride ride_requests;
  v_old ride_status;
  v_actor_is_admin boolean := false;
  v_actor_is_claiming_provider boolean := false;
begin
  select * into v_ride from ride_requests where id = p_ride_id for update;
  if v_ride.id is null then
    raise exception 'RIDE_NOT_FOUND';
  end if;

  v_old := v_ride.status;

  if v_old = 'CANCELLED' or v_old = 'COMPLETED' then
    raise exception 'RIDE_ALREADY_TERMINAL';
  end if;

  -- Determine actor authorization
  select exists (
    select 1 from user_roles where user_id = p_actor and role = 'ADMIN'
  ) into v_actor_is_admin;

  if v_ride.claimed_by_provider_id is not null then
    select exists (
      select 1 from provider_profiles
      where id = v_ride.claimed_by_provider_id and user_id = p_actor
    ) into v_actor_is_claiming_provider;
  end if;

  -- Validate transition authorization
  case v_old
    when 'REQUESTED' then
      -- Only the rider can cancel before claim; provider claim goes through claim_ride()
      if p_new_status != 'CANCELLED' then
        raise exception 'ONLY_CANCELLATION_ALLOWED_FROM_REQUESTED_USE_CLAIM_RIDE';
      end if;
      if v_ride.user_id != p_actor and not v_actor_is_admin then
        raise exception 'ONLY_RIDER_OR_ADMIN_CAN_CANCEL_BEFORE_CLAIM';
      end if;

    when 'CLAIMED' then
      -- Claiming provider can transition to DRIVER_ARRIVING; rider/admin can cancel
      if p_new_status = 'CANCELLED' then
        if v_ride.user_id != p_actor and not v_actor_is_admin then
          raise exception 'ONLY_RIDER_OR_ADMIN_CAN_CANCEL_CLAIMED_RIDE';
        end if;
      elsif not v_actor_is_claiming_provider and not v_actor_is_admin then
        raise exception 'ONLY_CLAIMING_PROVIDER_OR_ADMIN_CAN_PROGRESS_RIDE';
      end if;

    when 'DRIVER_ARRIVING' then
      -- Claiming provider progresses to STARTED; rider/admin can cancel
      if p_new_status = 'CANCELLED' then
        if v_ride.user_id != p_actor and not v_actor_is_admin then
          raise exception 'ONLY_RIDER_OR_ADMIN_CAN_CANCEL';
        end if;
      elsif not v_actor_is_claiming_provider and not v_actor_is_admin then
        raise exception 'ONLY_CLAIMING_PROVIDER_OR_ADMIN_CAN_PROGRESS_RIDE';
      end if;

    when 'STARTED' then
      -- Claiming provider completes; rider/admin can dispute or cancel
      if p_new_status in ('COMPLETED') then
        if not v_actor_is_claiming_provider and not v_actor_is_admin then
          raise exception 'ONLY_CLAIMING_PROVIDER_OR_ADMIN_CAN_COMPLETE_RIDE';
        end if;
      elsif p_new_status = 'CANCELLED' then
        if v_ride.user_id != p_actor and not v_actor_is_admin then
          raise exception 'ONLY_RIDER_OR_ADMIN_CAN_CANCEL';
        end if;
      end if;

    else
      raise exception 'UNEXPECTED_RIDE_STATUS_%', v_old;
  end case;

  update ride_requests
  set status = p_new_status, updated_at = now()
  where id = p_ride_id
  returning * into v_ride;

  insert into ride_status_history (ride_request_id, from_status, to_status, changed_by)
  values (p_ride_id, v_old, p_new_status, p_actor);

  -- Completed rides trigger the platform transaction fee.
  if p_new_status = 'COMPLETED' then
    perform deduct_transaction_fee(
      v_ride.claimed_by_provider_id,
      null,
      p_ride_id,
      coalesce(v_ride.fare_estimate, 0),
      'ride:' || p_ride_id::text
    );
  end if;

  return v_ride;
end;
$$;

-- =========================================================
-- 9. VEHICLE INSERT HARDENING
--     Ensure vehicles can only be created with PENDING_APPROVAL status.
--     The provider cannot self-approve on insert.
-- =========================================================

create or replace function prevent_vehicle_insert_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    if new.status != 'PENDING_APPROVAL' then
      raise exception 'VEHICLE_MUST_START_AS_PENDING_APPROVAL';
    end if;
    if new.is_available != false then
      raise exception 'NEW_VEHICLES_ARE_NOT_AVAILABLE_UNTIL_APPROVED';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_vehicles_insert_security
  before insert on vehicles
  for each row
  execute function prevent_vehicle_insert_privilege_escalation();

-- =========================================================
-- 10. PRODUCT INSERT HARDENING
--      Providers cannot insert products with manipulated ratings
--      or sales counts.
-- =========================================================

create or replace function prevent_product_insert_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Force server-managed fields to safe defaults on insert
    new.rating := 0;
    new.review_count := 0;
    new.sales_count := 0;
  end if;
  return new;
end;
$$;

create trigger trg_products_insert_security
  before insert on products
  for each row
  execute function prevent_product_insert_privilege_escalation();

-- =========================================================
-- 11. REVIEW INSERT HARDENING
--      Ensure reviews cannot be inserted with manipulated data.
-- =========================================================

create or replace function prevent_review_insert_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Ensure user_id matches the current user
    if new.user_id != auth.uid() then
      raise exception 'CANNOT_CREATE_REVIEW_FOR_ANOTHER_USER';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_reviews_insert_security
  before insert on reviews
  for each row
  execute function prevent_review_insert_privilege_escalation();

-- =========================================================
-- 12. ORDER INSERT HARDENING
--      Ensure orders cannot be created with manipulated fields.
-- =========================================================

create or replace function prevent_order_insert_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Force status to CREATED on insert (cannot bypass initial state)
    if new.status != 'CREATED' then
      raise exception 'ORDERS_MUST_START_AS_CREATED';
    end if;
    -- Ensure user_id matches the current user
    if new.user_id != auth.uid() then
      raise exception 'CANNOT_CREATE_ORDER_FOR_ANOTHER_USER';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_orders_insert_security
  before insert on orders
  for each row
  execute function prevent_order_insert_privilege_escalation();

-- =========================================================
-- 13. RIDE REQUEST INSERT HARDENING
--      Ensure ride requests cannot be created with manipulated fields.
-- =========================================================

create or replace function prevent_ride_insert_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Force status to REQUESTED on insert
    if new.status != 'REQUESTED' then
      raise exception 'RIDE_REQUESTS_MUST_START_AS_REQUESTED';
    end if;
    -- Ensure user_id matches the current user
    if new.user_id != auth.uid() then
      raise exception 'CANNOT_CREATE_RIDE_REQUEST_FOR_ANOTHER_USER';
    end if;
    -- Prevent pre-filling claim fields
    if new.claimed_by_provider_id is not null then
      raise exception 'CLAIM_FIELDS_CANNOT_BE_SET_ON_INSERT';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_ride_requests_insert_security
  before insert on ride_requests
  for each row
  execute function prevent_ride_insert_privilege_escalation();

-- =========================================================
-- 14. PROVIDER PROFILE INSERT HARDENING
--      Ensure provider profiles cannot be created with manipulated fields.
-- =========================================================

create or replace function prevent_provider_insert_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Force status to PENDING_APPROVAL on insert
    if new.status != 'PENDING_APPROVAL' then
      raise exception 'PROVIDER_PROFILES_MUST_START_AS_PENDING_APPROVAL';
    end if;
    -- Ensure user_id matches the current user
    if new.user_id != auth.uid() then
      raise exception 'CANNOT_CREATE_PROVIDER_PROFILE_FOR_ANOTHER_USER';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_provider_profiles_insert_security
  before insert on provider_profiles
  for each row
  execute function prevent_provider_insert_privilege_escalation();

-- =========================================================
-- 15. PROFILE INSERT HARDENING
--      Ensure profiles cannot be created with manipulated status.
-- =========================================================

create or replace function prevent_profile_insert_privilege_escalation()
returns trigger
language plpgsql
security definer
as $$
begin
  if not is_admin() then
    -- Force status to PENDING_APPROVAL on insert
    if new.status != 'PENDING_APPROVAL' then
      raise exception 'PROFILES_MUST_START_AS_PENDING_APPROVAL';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_profiles_insert_security
  before insert on profiles
  for each row
  execute function prevent_profile_insert_privilege_escalation();
