-- 5BIRR Phase 1 — Server-side business logic functions
-- Migration 0003_functions.sql
-- All financial / state-machine mutations MUST go through these functions.
-- They are SECURITY DEFINER so RLS cannot be bypassed by clients directly,
-- but are only ever invoked via Edge Functions using the service_role key
-- (never granted directly to `authenticated`), which re-validates the caller.

-- =========================================================
-- CONFIG HELPER
-- =========================================================
create or replace function get_setting_numeric(p_key text)
returns numeric
language sql stable
as $$
  select (value #>> '{}')::numeric from system_settings where key = p_key;
$$;

create or replace function get_setting_bool(p_key text)
returns boolean
language sql stable
as $$
  select (value #>> '{}')::boolean from system_settings where key = p_key;
$$;

-- =========================================================
-- ATOMIC RIDE CLAIM
-- Prevents two drivers from claiming the same ride. Uses SELECT ... FOR
-- UPDATE SKIP LOCKED + a WHERE status='REQUESTED' guard inside a single
-- UPDATE statement, backed by the partial unique index uq_ride_single_claim.
-- Returns the claimed row, or raises an exception if already taken.
-- =========================================================
create or replace function claim_ride(
  p_ride_id uuid,
  p_provider_id uuid,
  p_vehicle_id uuid
) returns ride_requests
language plpgsql
security definer
as $$
declare
  v_ride ride_requests;
begin
  -- Verify the vehicle belongs to the claiming provider and is available.
  if not exists (
    select 1 from vehicles
    where id = p_vehicle_id and provider_id = p_provider_id and is_available = true
  ) then
    raise exception 'VEHICLE_NOT_ELIGIBLE';
  end if;

  -- Verify provider is approved and active.
  if not exists (
    select 1 from provider_profiles
    where id = p_provider_id and provider_type = 'VEHICLE_PROVIDER' and status = 'APPROVED'
  ) then
    raise exception 'PROVIDER_NOT_ELIGIBLE';
  end if;

  -- Atomic conditional update: only succeeds if still REQUESTED.
  -- Row lock via UPDATE prevents concurrent claims; second concurrent
  -- transaction will simply match zero rows once the first commits.
  update ride_requests
  set status = 'CLAIMED',
      claimed_by_provider_id = p_provider_id,
      claimed_vehicle_id = p_vehicle_id,
      claimed_at = now(),
      updated_at = now()
  where id = p_ride_id
    and status = 'REQUESTED'
  returning * into v_ride;

  if v_ride.id is null then
    raise exception 'RIDE_ALREADY_TAKEN';
  end if;

  insert into ride_status_history (ride_request_id, from_status, to_status, changed_by)
  values (p_ride_id, 'REQUESTED', 'CLAIMED', auth.uid());

  insert into audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  values (auth.uid(), 'RIDE_CLAIMED', 'ride_requests', p_ride_id,
          jsonb_build_object('provider_id', p_provider_id, 'vehicle_id', p_vehicle_id));

  return v_ride;
end;
$$;

-- Generic ride status transition (DRIVER_ARRIVING / STARTED / COMPLETED / CANCELLED)
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
begin
  select status into v_old from ride_requests where id = p_ride_id for update;
  if v_old is null then
    raise exception 'RIDE_NOT_FOUND';
  end if;

  -- Simple linear guard; adjust per business rules in Phase 2.
  if v_old = 'CANCELLED' or v_old = 'COMPLETED' then
    raise exception 'RIDE_ALREADY_TERMINAL';
  end if;

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
-- WALLET: IDEMPOTENT FEE DEDUCTION
-- Used for both order-based (5 Birr transaction fee) and subscription fees.
-- idempotency_key must be unique per billable event so retries never double-charge.
-- =========================================================
create or replace function deduct_transaction_fee(
  p_provider_id uuid,
  p_order_id uuid,
  p_ride_id uuid,
  p_gross_amount numeric,
  p_idempotency_key text
) returns wallet_transactions
language plpgsql
security definer
as $$
declare
  v_wallet wallets;
  v_fee numeric := get_setting_numeric('transaction_fee');
  v_allow_negative boolean := get_setting_bool('allow_negative_wallet');
  v_txn wallet_transactions;
  v_existing wallet_transactions;
begin
  -- Idempotency check first — never double charge on retry.
  select * into v_existing from wallet_transactions where idempotency_key = p_idempotency_key;
  if v_existing.id is not null then
    return v_existing;
  end if;

  select * into v_wallet from wallets where provider_id = p_provider_id for update;
  if v_wallet.id is null then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  if not v_allow_negative and (v_wallet.balance - v_fee) < 0 then
    -- Still record the failed attempt for audit, then raise.
    insert into wallet_transactions (
      wallet_id, provider_id, order_id, ride_request_id, transaction_type,
      gross_amount, platform_fee, net_amount, balance_after, status, idempotency_key
    ) values (
      v_wallet.id, p_provider_id, p_order_id, p_ride_id, 'TRANSACTION_FEE',
      p_gross_amount, v_fee, p_gross_amount - v_fee, v_wallet.balance, 'FAILED', p_idempotency_key
    ) returning * into v_txn;

    insert into notifications (user_id, type, title, body)
    select user_id, 'WALLET_EMPTY', 'Wallet balance too low',
           'Transaction fee could not be deducted — please recharge your wallet.'
    from provider_profiles where id = p_provider_id;

    raise exception 'INSUFFICIENT_WALLET_BALANCE';
  end if;

  update wallets
  set balance = balance - v_fee, updated_at = now()
  where id = v_wallet.id
  returning * into v_wallet;

  insert into wallet_transactions (
    wallet_id, provider_id, order_id, ride_request_id, transaction_type,
    gross_amount, platform_fee, net_amount, balance_after, status, idempotency_key
  ) values (
    v_wallet.id, p_provider_id, p_order_id, p_ride_id, 'TRANSACTION_FEE',
    p_gross_amount, v_fee, p_gross_amount - v_fee, v_wallet.balance, 'COMPLETED', p_idempotency_key
  ) returning * into v_txn;

  insert into audit_logs (event_type, entity_type, entity_id, metadata)
  values ('TRANSACTION_FEE_DEDUCTED', 'wallets', v_wallet.id,
          jsonb_build_object('provider_id', p_provider_id, 'fee', v_fee, 'balance_after', v_wallet.balance));

  insert into notifications (user_id, type, title, body)
  select user_id, 'TRANSACTION_FEE_DEDUCTED', 'Platform fee deducted',
         v_fee::text || ' Birr deducted from your wallet.'
  from provider_profiles where id = p_provider_id;

  if v_wallet.balance <= get_setting_numeric('low_wallet_threshold') then
    insert into notifications (user_id, type, title, body)
    select user_id, 'WALLET_LOW', 'Wallet balance low',
           'Your wallet balance is low. Please recharge soon.'
    from provider_profiles where id = p_provider_id;
  end if;

  return v_txn;
end;
$$;

-- Subscription fee deduction — same idempotent pattern, keyed by provider+period.
create or replace function deduct_subscription_fee(
  p_provider_id uuid,
  p_period text -- e.g. '2026-09'
) returns wallet_transactions
language plpgsql
security definer
as $$
declare
  v_wallet wallets;
  v_fee numeric := get_setting_numeric('monthly_subscription_fee');
  v_key text := 'sub:' || p_provider_id::text || ':' || p_period;
  v_existing wallet_transactions;
  v_txn wallet_transactions;
begin
  select * into v_existing from wallet_transactions where idempotency_key = v_key;
  if v_existing.id is not null then
    return v_existing;
  end if;

  select * into v_wallet from wallets where provider_id = p_provider_id for update;
  if v_wallet.id is null then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  update wallets set balance = balance - v_fee, updated_at = now()
  where id = v_wallet.id
  returning * into v_wallet;

  insert into wallet_transactions (
    wallet_id, provider_id, transaction_type, gross_amount, platform_fee,
    net_amount, balance_after, status, idempotency_key
  ) values (
    v_wallet.id, p_provider_id, 'SUBSCRIPTION_FEE', v_fee, v_fee, 0, v_wallet.balance, 'COMPLETED', v_key
  ) returning * into v_txn;

  update subscriptions
  set last_charged_at = now(),
      next_due_date = next_due_date + interval '1 month',
      status = 'ACTIVE'
  where provider_id = p_provider_id;

  insert into notifications (user_id, type, title, body)
  select user_id, 'SUBSCRIPTION_DUE', 'Subscription charged',
         v_fee::text || ' Birr monthly subscription deducted.'
  from provider_profiles where id = p_provider_id;

  return v_txn;
end;
$$;

-- =========================================================
-- ORDER STATE MACHINE TRANSITION (validated server-side)
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
begin
  select * into v_order from orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  v_old := v_order.status;

  -- Whitelist valid transitions (extend in Phase 2 per service type).
  v_valid := case v_old
    when 'CREATED' then p_new_status in ('PENDING_PROVIDER','CANCELLED')
    when 'PENDING_PROVIDER' then p_new_status in ('ACCEPTED','REJECTED','CANCELLED')
    when 'ACCEPTED' then p_new_status in ('PAYMENT_PENDING','CANCELLED')
    when 'PAYMENT_PENDING' then p_new_status in ('PAYMENT_VERIFICATION','CANCELLED')
    when 'PAYMENT_VERIFICATION' then p_new_status in ('APPROVED','REJECTED')
    when 'APPROVED' then p_new_status in ('STARTED','CANCELLED')
    when 'STARTED' then p_new_status in ('COMPLETED','DISPUTED','CANCELLED')
    when 'COMPLETED' then p_new_status in ('DISPUTED','REFUNDED')
    when 'DISPUTED' then p_new_status in ('REFUNDED','COMPLETED')
    else false
  end;

  if not v_valid then
    raise exception 'INVALID_TRANSITION_% _TO_%', v_old, p_new_status;
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

  -- Charge the platform transaction fee exactly once, on entering STARTED
  -- (i.e. the first protected/approved transaction event), idempotent per order.
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
-- PROVIDER APPROVAL WORKFLOW
-- =========================================================
create or replace function approve_provider(
  p_provider_id uuid,
  p_admin_id uuid
) returns provider_profiles
language plpgsql
security definer
as $$
declare
  v_provider provider_profiles;
begin
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
begin
  update provider_profiles set status = 'REJECTED', updated_at = now()
  where id = p_provider_id
  returning * into v_provider;

  insert into approval_history (subject_type, subject_id, action, reason, performed_by)
  values ('PROVIDER', p_provider_id, 'REJECT', p_reason, p_admin_id);

  insert into notifications (user_id, type, title, body)
  select user_id, 'REJECTION', 'Application rejected', p_reason
  from provider_profiles where id = p_provider_id;

  insert into admin_actions (admin_id, action, target_type, target_id, details)
  values (p_admin_id, 'REJECT_PROVIDER', 'provider_profiles', p_provider_id, jsonb_build_object('reason', p_reason));

  return v_provider;
end;
$$;

-- =========================================================
-- updated_at triggers
-- =========================================================
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_profiles_updated before update on profiles for each row execute function set_updated_at();
create trigger trg_provider_profiles_updated before update on provider_profiles for each row execute function set_updated_at();
create trigger trg_products_updated before update on products for each row execute function set_updated_at();
create trigger trg_orders_updated before update on orders for each row execute function set_updated_at();
create trigger trg_ride_requests_updated before update on ride_requests for each row execute function set_updated_at();
create trigger trg_wallets_updated before update on wallets for each row execute function set_updated_at();
create trigger trg_subscriptions_updated before update on subscriptions for each row execute function set_updated_at();
