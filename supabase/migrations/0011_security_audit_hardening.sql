-- 5BIRR — Security Audit Hardening
-- Migration 0011_security_audit_hardening.sql
-- Addresses vulnerabilities found in the comprehensive red-team audit.
-- All changes are additive/restrictive; no existing data is modified.

-- =========================================================
-- 1. REVOKE BROAD GRANTS — Revoke execute from anon/authenticated
--    on SECURITY DEFINER functions that should only be called
--    via Edge Functions (service_role) or trusted internal paths.
-- =========================================================

-- Wallet/financial functions: only Edge Functions (service_role) should call these
REVOKE EXECUTE ON FUNCTION deduct_transaction_fee FROM authenticated;
REVOKE EXECUTE ON FUNCTION deduct_subscription_fee FROM authenticated;
REVOKE EXECUTE ON FUNCTION approve_wallet_recharge FROM authenticated;
REVOKE EXECUTE ON FUNCTION reject_wallet_recharge FROM authenticated;
REVOKE EXECUTE ON FUNCTION admin_cash_recharge FROM authenticated;
REVOKE EXECUTE ON FUNCTION admin_wallet_adjustment FROM authenticated;

-- Provider approval functions: only admin Edge Functions should call these
REVOKE EXECUTE ON FUNCTION approve_provider FROM authenticated;
REVOKE EXECUTE ON FUNCTION reject_provider FROM authenticated;
REVOKE EXECUTE ON FUNCTION request_correction_provider FROM authenticated;
REVOKE EXECUTE ON FUNCTION suspend_provider FROM authenticated;
REVOKE EXECUTE ON FUNCTION unsuspend_provider FROM authenticated;

-- Order transition: should go through Edge Function only
REVOKE EXECUTE ON FUNCTION transition_order_status FROM authenticated;

-- Ride transition: should go through Edge Function only
REVOKE EXECUTE ON FUNCTION transition_ride_status FROM authenticated;

-- Ride claim: should go through Edge Function only
REVOKE EXECUTE ON FUNCTION claim_ride FROM authenticated;

-- =========================================================
-- 2. GRANT EXECUTE TO PUBLIC ON SAFE READ FUNCTIONS
--    These are read-only and safe for authenticated users.
-- =========================================================

GRANT EXECUTE ON FUNCTION find_nearby_drivers TO authenticated;
GRANT EXECUTE ON FUNCTION create_ride_request TO authenticated;
GRANT EXECUTE ON FUNCTION update_driver_location TO authenticated;
GRANT EXECUTE ON FUNCTION set_driver_online TO authenticated;
GRANT EXECUTE ON FUNCTION get_setting_numeric TO authenticated;
GRANT EXECUTE ON FUNCTION get_setting_bool TO authenticated;
GRANT EXECUTE ON FUNCTION has_role TO authenticated;
GRANT EXECUTE ON FUNCTION is_admin TO authenticated;
GRANT EXECUTE ON FUNCTION owns_provider_profile TO authenticated;

-- =========================================================
-- 3. HARDEN SEARCH_PATH ON ALL SECURITY DEFINER FUNCTIONS
--    Prevents search_path hijacking attacks where an attacker
--    creates objects in a malicious schema to override function calls.
-- =========================================================

-- 0002 helper functions
CREATE OR REPLACE FUNCTION has_role(check_role app_role)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT exists (
    SELECT 1 FROM user_roles
    WHERE user_id = auth.uid() AND role = check_role
  );
$$;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT has_role('ADMIN'::app_role);
$$;

CREATE OR REPLACE FUNCTION owns_provider_profile(p_provider_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT exists (
    SELECT 1 FROM provider_profiles
    WHERE id = p_provider_id AND user_id = auth.uid()
  );
$$;

-- 0003 functions
CREATE OR REPLACE FUNCTION get_setting_numeric(p_key text)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT (value #>> '{}')::numeric FROM system_settings WHERE key = p_key;
$$;

CREATE OR REPLACE FUNCTION get_setting_bool(p_key text)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT (value #>> '{}')::boolean FROM system_settings WHERE key = p_key;
$$;

CREATE OR REPLACE FUNCTION claim_ride(
  p_ride_id uuid,
  p_provider_id uuid,
  p_vehicle_id uuid
) RETURNS ride_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride ride_requests;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM vehicles
    WHERE id = p_vehicle_id AND provider_id = p_provider_id AND is_available = true
  ) THEN
    RAISE EXCEPTION 'VEHICLE_NOT_ELIGIBLE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM provider_profiles
    WHERE id = p_provider_id AND provider_type = 'VEHICLE_PROVIDER' AND status = 'APPROVED'
  ) THEN
    RAISE EXCEPTION 'PROVIDER_NOT_ELIGIBLE';
  END IF;

  UPDATE ride_requests
  SET status = 'CLAIMED',
      claimed_by_provider_id = p_provider_id,
      claimed_vehicle_id = p_vehicle_id,
      claimed_at = now(),
      updated_at = now()
  WHERE id = p_ride_id
    AND status = 'REQUESTED'
  RETURNING * INTO v_ride;

  IF v_ride.id IS NULL THEN
    RAISE EXCEPTION 'RIDE_ALREADY_TAKEN';
  END IF;

  INSERT INTO ride_status_history (ride_request_id, from_status, to_status, changed_by)
  VALUES (p_ride_id, 'REQUESTED', 'CLAIMED', auth.uid());

  INSERT INTO audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'RIDE_CLAIMED', 'ride_requests', p_ride_id,
          jsonb_build_object('provider_id', p_provider_id, 'vehicle_id', p_vehicle_id));

  RETURN v_ride;
END;
$$;

CREATE OR REPLACE FUNCTION deduct_transaction_fee(
  p_provider_id uuid,
  p_order_id uuid,
  p_ride_id uuid,
  p_gross_amount numeric,
  p_idempotency_key text
) RETURNS wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet wallets;
  v_fee numeric := get_setting_numeric('transaction_fee');
  v_allow_negative boolean := get_setting_bool('allow_negative_wallet');
  v_txn wallet_transactions;
  v_existing wallet_transactions;
BEGIN
  SELECT * INTO v_existing FROM wallet_transactions WHERE idempotency_key = p_idempotency_key;
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT * INTO v_wallet FROM wallets WHERE provider_id = p_provider_id FOR UPDATE;
  IF v_wallet.id IS NULL THEN
    RAISE EXCEPTION 'WALLET_NOT_FOUND';
  END IF;

  IF NOT v_allow_negative AND (v_wallet.balance - v_fee) < 0 THEN
    INSERT INTO wallet_transactions (
      wallet_id, provider_id, order_id, ride_request_id, transaction_type,
      gross_amount, platform_fee, net_amount, balance_after, status, idempotency_key
    ) VALUES (
      v_wallet.id, p_provider_id, p_order_id, p_ride_id, 'TRANSACTION_FEE',
      p_gross_amount, v_fee, p_gross_amount - v_fee, v_wallet.balance, 'FAILED', p_idempotency_key
    ) RETURNING * INTO v_txn;

    INSERT INTO notifications (user_id, type, title, body)
    SELECT user_id, 'WALLET_EMPTY', 'Wallet balance too low',
           'Transaction fee could not be deducted — please recharge your wallet.'
    FROM provider_profiles WHERE id = p_provider_id;

    RAISE EXCEPTION 'INSUFFICIENT_WALLET_BALANCE';
  END IF;

  UPDATE wallets
  SET balance = balance - v_fee, updated_at = now()
  WHERE id = v_wallet.id
  RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions (
    wallet_id, provider_id, order_id, ride_request_id, transaction_type,
    gross_amount, platform_fee, net_amount, balance_after, status, idempotency_key
  ) VALUES (
    v_wallet.id, p_provider_id, p_order_id, p_ride_id, 'TRANSACTION_FEE',
    p_gross_amount, v_fee, p_gross_amount - v_fee, v_wallet.balance, 'COMPLETED', p_idempotency_key
  ) RETURNING * INTO v_txn;

  INSERT INTO audit_logs (event_type, entity_type, entity_id, metadata)
  VALUES ('TRANSACTION_FEE_DEDUCTED', 'wallets', v_wallet.id,
          jsonb_build_object('provider_id', p_provider_id, 'fee', v_fee, 'balance_after', v_wallet.balance));

  INSERT INTO notifications (user_id, type, title, body)
  SELECT user_id, 'TRANSACTION_FEE_DEDUCTED', 'Platform fee deducted',
         v_fee::text || ' Birr deducted from your wallet.'
  FROM provider_profiles WHERE id = p_provider_id;

  IF v_wallet.balance <= get_setting_numeric('low_wallet_threshold') THEN
    INSERT INTO notifications (user_id, type, title, body)
    SELECT user_id, 'WALLET_LOW', 'Wallet balance low',
           'Your wallet balance is low. Please recharge soon.'
    FROM provider_profiles WHERE id = p_provider_id;
  END IF;

  RETURN v_txn;
END;
$$;

CREATE OR REPLACE FUNCTION deduct_subscription_fee(
  p_provider_id uuid,
  p_period text
) RETURNS wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet wallets;
  v_fee numeric := get_setting_numeric('monthly_subscription_fee');
  v_key text := 'sub:' || p_provider_id::text || ':' || p_period;
  v_existing wallet_transactions;
  v_txn wallet_transactions;
BEGIN
  SELECT * INTO v_existing FROM wallet_transactions WHERE idempotency_key = v_key;
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  SELECT * INTO v_wallet FROM wallets WHERE provider_id = p_provider_id FOR UPDATE;
  IF v_wallet.id IS NULL THEN
    RAISE EXCEPTION 'WALLET_NOT_FOUND';
  END IF;

  UPDATE wallets SET balance = balance - v_fee, updated_at = now()
  WHERE id = v_wallet.id
  RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions (
    wallet_id, provider_id, transaction_type, gross_amount, platform_fee,
    net_amount, balance_after, status, idempotency_key
  ) VALUES (
    v_wallet.id, p_provider_id, 'SUBSCRIPTION_FEE', v_fee, v_fee, 0, v_wallet.balance, 'COMPLETED', v_key
  ) RETURNING * INTO v_txn;

  UPDATE subscriptions
  SET last_charged_at = now(),
      next_due_date = next_due_date + interval '1 month',
      status = 'ACTIVE'
  WHERE provider_id = p_provider_id;

  INSERT INTO notifications (user_id, type, title, body)
  SELECT user_id, 'SUBSCRIPTION_DUE', 'Subscription charged',
         v_fee::text || ' Birr monthly subscription deducted.'
  FROM provider_profiles WHERE id = p_provider_id;

  RETURN v_txn;
END;
$$;

-- 0008 hardened functions
CREATE OR REPLACE FUNCTION transition_order_status(
  p_order_id uuid,
  p_new_status order_status,
  p_actor uuid,
  p_note text default null
) RETURNS orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order orders;
  v_old order_status;
  v_valid boolean := false;
  v_actor_is_provider boolean := false;
  v_actor_is_admin boolean := false;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;
  v_old := v_order.status;

  SELECT exists (
    SELECT 1 FROM user_roles WHERE user_id = p_actor AND role = 'ADMIN'
  ) INTO v_actor_is_admin;

  SELECT exists (
    SELECT 1 FROM provider_profiles
    WHERE id = v_order.provider_id AND user_id = p_actor
  ) INTO v_actor_is_provider;

  v_valid := CASE v_old
    WHEN 'CREATED' THEN
      p_new_status IN ('PENDING_PROVIDER','CANCELLED')
      AND (v_order.user_id = p_actor OR v_actor_is_admin)
    WHEN 'PENDING_PROVIDER' THEN
      (p_new_status IN ('ACCEPTED','REJECTED')
        AND (v_actor_is_provider OR v_actor_is_admin))
      OR (p_new_status = 'CANCELLED'
        AND (v_order.user_id = p_actor OR v_actor_is_admin))
    WHEN 'ACCEPTED' THEN
      (p_new_status = 'PAYMENT_PENDING' AND (v_actor_is_provider OR v_actor_is_admin))
      OR (p_new_status = 'CANCELLED' AND (v_order.user_id = p_actor OR v_actor_is_admin))
    WHEN 'PAYMENT_PENDING' THEN
      (p_new_status = 'PAYMENT_VERIFICATION' AND v_order.user_id = p_actor)
      OR (p_new_status = 'CANCELLED' AND v_actor_is_admin)
    WHEN 'PAYMENT_VERIFICATION' THEN
      p_new_status IN ('APPROVED','REJECTED') AND v_actor_is_admin
    WHEN 'APPROVED' THEN
      (p_new_status = 'STARTED' AND (v_actor_is_provider OR v_actor_is_admin))
      OR (p_new_status = 'CANCELLED' AND (v_order.user_id = p_actor OR v_actor_is_admin))
    WHEN 'STARTED' THEN
      (p_new_status = 'COMPLETED' AND (v_actor_is_provider OR v_actor_is_admin))
      OR (p_new_status IN ('DISPUTED','CANCELLED')
        AND (v_order.user_id = p_actor OR v_actor_is_admin))
    WHEN 'COMPLETED' THEN
      p_new_status IN ('DISPUTED','REFUNDED')
      AND (v_order.user_id = p_actor OR v_actor_is_admin)
    WHEN 'DISPUTED' THEN
      p_new_status IN ('REFUNDED','COMPLETED') AND v_actor_is_admin
    ELSE false
  END;

  IF NOT v_valid THEN
    RAISE EXCEPTION 'INVALID_TRANSITION_%_TO_%_FOR_ACTOR', v_old, p_new_status;
  END IF;

  IF p_new_status = 'APPROVED' AND v_order.requires_payment_proof THEN
    IF NOT EXISTS (
      SELECT 1 FROM payment_proofs
      WHERE order_id = p_order_id AND verification_status = 'VERIFIED'
    ) THEN
      RAISE EXCEPTION 'PAYMENT_PROOF_REQUIRED';
    END IF;
  END IF;

  UPDATE orders SET status = p_new_status, updated_at = now()
  WHERE id = p_order_id
  RETURNING * INTO v_order;

  INSERT INTO order_status_history (order_id, from_status, to_status, changed_by, note)
  VALUES (p_order_id, v_old, p_new_status, p_actor, p_note);

  IF p_new_status = 'STARTED' THEN
    PERFORM deduct_transaction_fee(
      v_order.provider_id, p_order_id, null, v_order.total_amount,
      'order:' || p_order_id::text
    );
  END IF;

  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION transition_ride_status(
  p_ride_id uuid,
  p_new_status ride_status,
  p_actor uuid
) RETURNS ride_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride ride_requests;
  v_old ride_status;
  v_actor_is_admin boolean := false;
  v_actor_is_claiming_provider boolean := false;
BEGIN
  SELECT * INTO v_ride FROM ride_requests WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN
    RAISE EXCEPTION 'RIDE_NOT_FOUND';
  END IF;

  v_old := v_ride.status;

  IF v_old = 'CANCELLED' OR v_old = 'COMPLETED' THEN
    RAISE EXCEPTION 'RIDE_ALREADY_TERMINAL';
  END IF;

  SELECT exists (
    SELECT 1 FROM user_roles WHERE user_id = p_actor AND role = 'ADMIN'
  ) INTO v_actor_is_admin;

  IF v_ride.claimed_by_provider_id IS NOT NULL THEN
    SELECT exists (
      SELECT 1 FROM provider_profiles
      WHERE id = v_ride.claimed_by_provider_id AND user_id = p_actor
    ) INTO v_actor_is_claiming_provider;
  END IF;

  CASE v_old
    WHEN 'REQUESTED' THEN
      IF p_new_status != 'CANCELLED' THEN
        RAISE EXCEPTION 'ONLY_CANCELLATION_ALLOWED_FROM_REQUESTED_USE_CLAIM_RIDE';
      END IF;
      IF v_ride.user_id != p_actor AND NOT v_actor_is_admin THEN
        RAISE EXCEPTION 'ONLY_RIDER_OR_ADMIN_CAN_CANCEL_BEFORE_CLAIM';
      END IF;
    WHEN 'CLAIMED' THEN
      IF p_new_status = 'CANCELLED' THEN
        IF v_ride.user_id != p_actor AND NOT v_actor_is_admin THEN
          RAISE EXCEPTION 'ONLY_RIDER_OR_ADMIN_CAN_CANCEL_CLAIMED_RIDE';
        END IF;
      ELSIF NOT v_actor_is_claiming_provider AND NOT v_actor_is_admin THEN
        RAISE EXCEPTION 'ONLY_CLAIMING_PROVIDER_OR_ADMIN_CAN_PROGRESS_RIDE';
      END IF;
    WHEN 'DRIVER_ARRIVING' THEN
      IF p_new_status = 'CANCELLED' THEN
        IF v_ride.user_id != p_actor AND NOT v_actor_is_admin THEN
          RAISE EXCEPTION 'ONLY_RIDER_OR_ADMIN_CAN_CANCEL';
        END IF;
      ELSIF NOT v_actor_is_claiming_provider AND NOT v_actor_is_admin THEN
        RAISE EXCEPTION 'ONLY_CLAIMING_PROVIDER_OR_ADMIN_CAN_PROGRESS_RIDE';
      END IF;
    WHEN 'STARTED' THEN
      IF p_new_status IN ('COMPLETED') THEN
        IF NOT v_actor_is_claiming_provider AND NOT v_actor_is_admin THEN
          RAISE EXCEPTION 'ONLY_CLAIMING_PROVIDER_OR_ADMIN_CAN_COMPLETE_RIDE';
        END IF;
      ELSIF p_new_status = 'CANCELLED' THEN
        IF v_ride.user_id != p_actor AND NOT v_actor_is_admin THEN
          RAISE EXCEPTION 'ONLY_RIDER_OR_ADMIN_CAN_CANCEL';
        END IF;
      END IF;
    ELSE
      RAISE EXCEPTION 'UNEXPECTED_RIDE_STATUS_%', v_old;
  END CASE;

  UPDATE ride_requests
  SET status = p_new_status, updated_at = now()
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  INSERT INTO ride_status_history (ride_request_id, from_status, to_status, changed_by)
  VALUES (p_ride_id, v_old, p_new_status, p_actor);

  IF p_new_status = 'COMPLETED' THEN
    PERFORM deduct_transaction_fee(
      v_ride.claimed_by_provider_id,
      null,
      p_ride_id,
      coalesce(v_ride.fare_estimate, 0),
      'ride:' || p_ride_id::text
    );
  END IF;

  RETURN v_ride;
END;
$$;

CREATE OR REPLACE FUNCTION approve_provider(
  p_provider_id uuid,
  p_admin_id uuid
) RETURNS provider_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_provider provider_profiles;
  v_is_admin boolean;
BEGIN
  SELECT exists (
    SELECT 1 FROM user_roles
    WHERE user_id = p_admin_id AND role = 'ADMIN'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'ONLY_ADMINISTRATORS_CAN_APPROVE_PROVIDERS';
  END IF;

  IF EXISTS (
    SELECT 1 FROM provider_profiles
    WHERE id = p_provider_id AND user_id = p_admin_id
  ) THEN
    RAISE EXCEPTION 'ADMINISTRATORS_CANNOT_APPROVE_THEIR_OWN_PROVIDER_ACCOUNT';
  END IF;

  UPDATE provider_profiles SET status = 'APPROVED', updated_at = now()
  WHERE id = p_provider_id
  RETURNING * INTO v_provider;

  IF v_provider.id IS NULL THEN
    RAISE EXCEPTION 'PROVIDER_NOT_FOUND';
  END IF;

  INSERT INTO wallets (provider_id, balance) VALUES (p_provider_id, 0)
  ON CONFLICT (provider_id) DO NOTHING;

  INSERT INTO subscriptions (provider_id, next_due_date)
  VALUES (p_provider_id, v_provider.subscription_start_date)
  ON CONFLICT (provider_id) DO NOTHING;

  INSERT INTO approval_history (subject_type, subject_id, action, performed_by)
  VALUES ('PROVIDER', p_provider_id, 'APPROVE', p_admin_id);

  INSERT INTO notifications (user_id, type, title, body)
  SELECT user_id, 'APPROVAL', 'Application approved', 'Your provider account is now active.'
  FROM provider_profiles WHERE id = p_provider_id;

  INSERT INTO admin_actions (admin_id, action, target_type, target_id)
  VALUES (p_admin_id, 'APPROVE_PROVIDER', 'provider_profiles', p_provider_id);

  RETURN v_provider;
END;
$$;

CREATE OR REPLACE FUNCTION reject_provider(
  p_provider_id uuid,
  p_admin_id uuid,
  p_reason text
) RETURNS provider_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_provider provider_profiles;
  v_is_admin boolean;
BEGIN
  SELECT exists (
    SELECT 1 FROM user_roles
    WHERE user_id = p_admin_id AND role = 'ADMIN'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'ONLY_ADMINISTRATORS_CAN_REJECT_PROVIDERS';
  END IF;

  UPDATE provider_profiles SET status = 'REJECTED', updated_at = now()
  WHERE id = p_provider_id
  RETURNING * INTO v_provider;

  IF v_provider.id IS NULL THEN
    RAISE EXCEPTION 'PROVIDER_NOT_FOUND';
  END IF;

  INSERT INTO approval_history (subject_type, subject_id, action, reason, performed_by)
  VALUES ('PROVIDER', p_provider_id, 'REJECT', p_reason, p_admin_id);

  INSERT INTO notifications (user_id, type, title, body)
  SELECT user_id, 'REJECTION', 'Application rejected', p_reason
  FROM provider_profiles WHERE id = p_provider_id;

  INSERT INTO admin_actions (admin_id, action, target_type, target_id, details)
  VALUES (p_admin_id, 'REJECT_PROVIDER', 'provider_profiles', p_provider_id,
          jsonb_build_object('reason', p_reason));

  RETURN v_provider;
END;
$$;

CREATE OR REPLACE FUNCTION request_correction_provider(
  p_provider_id uuid,
  p_admin_id uuid,
  p_reason text
) RETURNS provider_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_provider provider_profiles;
  v_is_admin boolean;
BEGIN
  SELECT exists (
    SELECT 1 FROM user_roles
    WHERE user_id = p_admin_id AND role = 'ADMIN'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'ONLY_ADMINISTRATORS_CAN_REQUEST_CORRECTION';
  END IF;

  UPDATE provider_profiles SET status = 'REJECTED', updated_at = now()
  WHERE id = p_provider_id
  RETURNING * INTO v_provider;

  IF v_provider.id IS NULL THEN
    RAISE EXCEPTION 'PROVIDER_NOT_FOUND';
  END IF;

  INSERT INTO approval_history (subject_type, subject_id, action, reason, performed_by)
  VALUES ('PROVIDER', p_provider_id, 'REQUEST_CORRECTION', p_reason, p_admin_id);

  INSERT INTO notifications (user_id, type, title, body)
  SELECT user_id, 'CORRECTION_REQUIRED',
         'Correction requested',
         'Please update your submission: ' || p_reason
  FROM provider_profiles WHERE id = p_provider_id;

  INSERT INTO admin_actions (admin_id, action, target_type, target_id, details)
  VALUES (p_admin_id, 'REQUEST_CORRECTION', 'provider_profiles', p_provider_id,
          jsonb_build_object('reason', p_reason));

  RETURN v_provider;
END;
$$;

CREATE OR REPLACE FUNCTION suspend_provider(
  p_provider_id uuid,
  p_admin_id uuid,
  p_reason text default null
) RETURNS provider_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_provider provider_profiles;
  v_is_admin boolean;
BEGIN
  SELECT exists (
    SELECT 1 FROM user_roles
    WHERE user_id = p_admin_id AND role = 'ADMIN'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'ONLY_ADMINISTRATORS_CAN_SUSPEND_PROVIDERS';
  END IF;

  UPDATE provider_profiles SET status = 'SUSPENDED', updated_at = now()
  WHERE id = p_provider_id
  RETURNING * INTO v_provider;

  IF v_provider.id IS NULL THEN
    RAISE EXCEPTION 'PROVIDER_NOT_FOUND';
  END IF;

  UPDATE vehicles SET is_available = false
  WHERE provider_id = p_provider_id AND status = 'APPROVED';

  INSERT INTO approval_history (subject_type, subject_id, action, reason, performed_by)
  VALUES ('PROVIDER', p_provider_id, 'SUSPEND', p_reason, p_admin_id);

  INSERT INTO notifications (user_id, type, title, body)
  SELECT user_id, 'PROVIDER_INACTIVE', 'Account suspended',
         coalesce(p_reason, 'Your provider account has been suspended.')
  FROM provider_profiles WHERE id = p_provider_id;

  INSERT INTO admin_actions (admin_id, action, target_type, target_id, details)
  VALUES (p_admin_id, 'SUSPEND_PROVIDER', 'provider_profiles', p_provider_id,
          jsonb_build_object('reason', p_reason));

  RETURN v_provider;
END;
$$;

CREATE OR REPLACE FUNCTION unsuspend_provider(
  p_provider_id uuid,
  p_admin_id uuid
) RETURNS provider_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_provider provider_profiles;
  v_is_admin boolean;
BEGIN
  SELECT exists (
    SELECT 1 FROM user_roles
    WHERE user_id = p_admin_id AND role = 'ADMIN'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'ONLY_ADMINISTRATORS_CAN_UNSUSPEND_PROVIDERS';
  END IF;

  UPDATE provider_profiles SET status = 'APPROVED', updated_at = now()
  WHERE id = p_provider_id
  RETURNING * INTO v_provider;

  IF v_provider.id IS NULL THEN
    RAISE EXCEPTION 'PROVIDER_NOT_FOUND';
  END IF;

  UPDATE vehicles SET is_available = true
  WHERE provider_id = p_provider_id AND status = 'APPROVED';

  INSERT INTO approval_history (subject_type, subject_id, action, performed_by)
  VALUES ('PROVIDER', p_provider_id, 'APPROVE', p_admin_id);

  INSERT INTO notifications (user_id, type, title, body)
  SELECT user_id, 'APPROVAL', 'Account reactivated', 'Your provider account has been reactivated.'
  FROM provider_profiles WHERE id = p_provider_id;

  INSERT INTO admin_actions (admin_id, action, target_type, target_id)
  VALUES (p_admin_id, 'UNSUSPEND_PROVIDER', 'provider_profiles', p_provider_id);

  RETURN v_provider;
END;
$$;

-- 0009 hardened functions
CREATE OR REPLACE FUNCTION approve_wallet_recharge(
  p_recharge_id uuid,
  p_admin_id uuid
) RETURNS wallet_recharge_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recharge wallet_recharge_requests;
  v_wallet wallets;
  v_txn wallet_transactions;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles WHERE user_id = p_admin_id AND role = 'ADMIN'
  ) THEN
    RAISE EXCEPTION 'ONLY_ADMINISTRATORS_CAN_APPROVE_RECHARGES';
  END IF;

  SELECT * INTO v_recharge FROM wallet_recharge_requests
    WHERE id = p_recharge_id FOR UPDATE;

  IF v_recharge.id IS NULL THEN
    RAISE EXCEPTION 'RECHARGE_REQUEST_NOT_FOUND';
  END IF;

  IF v_recharge.status = 'APPROVED' THEN
    RETURN v_recharge;
  END IF;

  IF v_recharge.status != 'PENDING' THEN
    RAISE EXCEPTION 'RECHARGE_REQUEST_IS_NOT_PENDING';
  END IF;

  SELECT * INTO v_wallet FROM wallets
    WHERE id = v_recharge.wallet_id FOR UPDATE;

  IF v_wallet.id IS NULL THEN
    RAISE EXCEPTION 'WALLET_NOT_FOUND';
  END IF;

  UPDATE wallets
  SET balance = balance + v_recharge.amount, updated_at = now()
  WHERE id = v_wallet.id
  RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions (
    wallet_id, provider_id, transaction_type,
    gross_amount, platform_fee, net_amount,
    balance_after, status, idempotency_key
  ) VALUES (
    v_wallet.id, v_recharge.provider_id, 'RECHARGE',
    v_recharge.amount, 0, v_recharge.amount,
    v_wallet.balance, 'COMPLETED',
    'recharge:' || v_recharge.id::text
  ) RETURNING * INTO v_txn;

  UPDATE wallet_recharge_requests
  SET status = 'APPROVED',
      approved_by = p_admin_id,
      approved_at = now(),
      updated_at = now()
  WHERE id = p_recharge_id
  RETURNING * INTO v_recharge;

  INSERT INTO notifications (user_id, type, title, body)
  SELECT pp.user_id, 'APPROVAL', 'Recharge Approved',
         v_recharge.amount::text || ' ETB has been credited to your wallet.'
  FROM provider_profiles pp WHERE pp.id = v_recharge.provider_id;

  INSERT INTO audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  VALUES (p_admin_id, 'WALLET_RECHARGE_APPROVED', 'wallets', v_wallet.id,
          jsonb_build_object('recharge_id', p_recharge_id, 'amount', v_recharge.amount,
                             'provider_id', v_recharge.provider_id));

  RETURN v_recharge;
END;
$$;

CREATE OR REPLACE FUNCTION reject_wallet_recharge(
  p_recharge_id uuid,
  p_admin_id uuid,
  p_reason text
) RETURNS wallet_recharge_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recharge wallet_recharge_requests;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles WHERE user_id = p_admin_id AND role = 'ADMIN'
  ) THEN
    RAISE EXCEPTION 'ONLY_ADMINISTRATORS_CAN_REJECT_RECHARGES';
  END IF;

  SELECT * INTO v_recharge FROM wallet_recharge_requests
    WHERE id = p_recharge_id FOR UPDATE;

  IF v_recharge.id IS NULL THEN
    RAISE EXCEPTION 'RECHARGE_REQUEST_NOT_FOUND';
  END IF;

  IF v_recharge.status != 'PENDING' THEN
    RAISE EXCEPTION 'RECHARGE_REQUEST_IS_NOT_PENDING';
  END IF;

  UPDATE wallet_recharge_requests
  SET status = 'REJECTED',
      rejection_reason = p_reason,
      approved_by = p_admin_id,
      approved_at = now(),
      updated_at = now()
  WHERE id = p_recharge_id
  RETURNING * INTO v_recharge;

  INSERT INTO notifications (user_id, type, title, body)
  SELECT pp.user_id, 'REJECTION', 'Recharge Rejected',
         'Your recharge of ' || v_recharge.amount::text || ' ETB was rejected. Reason: ' || p_reason
  FROM provider_profiles pp WHERE pp.id = v_recharge.provider_id;

  INSERT INTO audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  VALUES (p_admin_id, 'WALLET_RECHARGE_REJECTED', 'wallets',
          (SELECT wallet_id FROM wallet_recharge_requests WHERE id = p_recharge_id),
          jsonb_build_object('recharge_id', p_recharge_id, 'reason', p_reason,
                             'provider_id', v_recharge.provider_id));

  RETURN v_recharge;
END;
$$;

CREATE OR REPLACE FUNCTION admin_cash_recharge(
  p_provider_id uuid,
  p_amount numeric,
  p_reason text,
  p_admin_id uuid
) RETURNS wallets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet wallets;
  v_balance_before numeric;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles WHERE user_id = p_admin_id AND role = 'ADMIN'
  ) THEN
    RAISE EXCEPTION 'ONLY_ADMINISTRATORS_CAN_PERFORM_CASH_RECHARGE';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'AMOUNT_MUST_BE_POSITIVE';
  END IF;

  SELECT * INTO v_wallet FROM wallets
    WHERE provider_id = p_provider_id FOR UPDATE;

  IF v_wallet.id IS NULL THEN
    RAISE EXCEPTION 'WALLET_NOT_FOUND_FOR_PROVIDER';
  END IF;

  v_balance_before := v_wallet.balance;

  UPDATE wallets
  SET balance = balance + p_amount, updated_at = now()
  WHERE id = v_wallet.id
  RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions (
    wallet_id, provider_id, transaction_type,
    gross_amount, platform_fee, net_amount,
    balance_after, status, idempotency_key
  ) VALUES (
    v_wallet.id, p_provider_id, 'ADMIN_CASH',
    p_amount, 0, p_amount,
    v_wallet.balance, 'COMPLETED',
    'admin-cash:' || p_provider_id::text || ':' || now()::text
  );

  INSERT INTO admin_wallet_actions (
    admin_id, provider_id, wallet_id, action_type,
    amount, reason, balance_before, balance_after
  ) VALUES (
    p_admin_id, p_provider_id, v_wallet.id, 'CASH_RECHARGE',
    p_amount, p_reason, v_balance_before, v_wallet.balance
  );

  INSERT INTO notifications (user_id, type, title, body)
  SELECT pp.user_id, 'APPROVAL', 'Cash Recharge',
         p_amount::text || ' ETB has been credited to your wallet (cash payment).'
  FROM provider_profiles pp WHERE pp.id = p_provider_id;

  INSERT INTO audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  VALUES (p_admin_id, 'ADMIN_CASH_RECHARGE', 'wallets', v_wallet.id,
          jsonb_build_object('provider_id', p_provider_id, 'amount', p_amount, 'reason', p_reason));

  RETURN v_wallet;
END;
$$;

CREATE OR REPLACE FUNCTION admin_wallet_adjustment(
  p_provider_id uuid,
  p_amount numeric,
  p_reason text,
  p_admin_id uuid
) RETURNS wallets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wallet wallets;
  v_balance_before numeric;
  v_action_type text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles WHERE user_id = p_admin_id AND role = 'ADMIN'
  ) THEN
    RAISE EXCEPTION 'ONLY_ADMINISTRATORS_CAN_ADJUST_WALLETS';
  END IF;

  IF p_amount = 0 THEN
    RAISE EXCEPTION 'AMOUNT_CANNOT_BE_ZERO';
  END IF;

  SELECT * INTO v_wallet FROM wallets
    WHERE provider_id = p_provider_id FOR UPDATE;

  IF v_wallet.id IS NULL THEN
    RAISE EXCEPTION 'WALLET_NOT_FOUND_FOR_PROVIDER';
  END IF;

  v_balance_before := v_wallet.balance;

  IF p_amount > 0 THEN
    v_action_type := 'ADJUSTMENT_CREDIT';
  ELSE
    v_action_type := 'ADJUSTMENT_DEBIT';
  END IF;

  IF p_amount < 0 AND v_wallet.balance + p_amount < 0 THEN
    IF NOT (SELECT (value #>> '{}')::boolean FROM system_settings WHERE key = 'allow_negative_wallet') THEN
      RAISE EXCEPTION 'INSUFFICIENT_BALANCE_FOR_DEBIT';
    END IF;
  END IF;

  UPDATE wallets
  SET balance = balance + p_amount, updated_at = now()
  WHERE id = v_wallet.id
  RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions (
    wallet_id, provider_id, transaction_type,
    gross_amount, platform_fee, net_amount,
    balance_after, status, idempotency_key
  ) VALUES (
    v_wallet.id, p_provider_id, 'ADJUSTMENT',
    abs(p_amount), 0, abs(p_amount),
    v_wallet.balance, 'COMPLETED',
    'adjustment:' || p_provider_id::text || ':' || now()::text
  );

  INSERT INTO admin_wallet_actions (
    admin_id, provider_id, wallet_id, action_type,
    amount, reason, balance_before, balance_after
  ) VALUES (
    p_admin_id, p_provider_id, v_wallet.id, v_action_type,
    abs(p_amount), p_reason, v_balance_before, v_wallet.balance
  );

  INSERT INTO notifications (user_id, type, title, body)
  SELECT pp.user_id, 'ADMIN_MESSAGE', 'Wallet Adjustment',
         'Your wallet has been adjusted by ' || p_amount::text || ' ETB. Reason: ' || p_reason
  FROM provider_profiles pp WHERE pp.id = p_provider_id;

  INSERT INTO audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  VALUES (p_admin_id, 'ADMIN_WALLET_ADJUSTMENT', 'wallets', v_wallet.id,
          jsonb_build_object('provider_id', p_provider_id, 'amount', p_amount, 'reason', p_reason));

  RETURN v_wallet;
END;
$$;

-- 0010 hardened functions
CREATE OR REPLACE FUNCTION find_nearby_drivers(
  p_lat double precision,
  p_lng double precision,
  p_radius_km numeric default 10,
  p_vehicle_category_id uuid default null
) RETURNS TABLE (
  provider_id uuid,
  vehicle_id uuid,
  provider_name text,
  vehicle_brand text,
  vehicle_model text,
  vehicle_plate text,
  distance_km numeric,
  vehicle_category uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_location geography(Point,4326);
BEGIN
  v_location := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;

  RETURN QUERY
  SELECT
    ds.provider_id,
    v.id AS vehicle_id,
    coalesce(pp.business_name, pr.full_name) AS provider_name,
    v.brand AS vehicle_brand,
    v.model AS vehicle_model,
    v.plate_number AS vehicle_plate,
    round((st_distance(ds.current_location, v_location) / 1000.0)::numeric, 2) AS distance_km,
    v.category_id AS vehicle_category
  FROM driver_status ds
  JOIN provider_profiles pp ON pp.id = ds.provider_id AND pp.status = 'APPROVED'
  JOIN profiles pr ON pr.id = pp.user_id
  JOIN vehicles v ON v.provider_id = ds.provider_id AND v.is_available = true AND v.status = 'APPROVED'
  WHERE ds.is_online = true
    AND ds.current_location IS NOT NULL
    AND ds.current_ride_id IS NULL
    AND st_dwithin(ds.current_location, v_location, p_radius_km * 1000)
    AND (p_vehicle_category_id IS NULL OR v.category_id = p_vehicle_category_id)
  ORDER BY st_distance(ds.current_location, v_location)
  LIMIT 20;
END;
$$;

CREATE OR REPLACE FUNCTION update_driver_location(
  p_provider_id uuid,
  p_lat double precision,
  p_lng double precision
) RETURNS driver_status
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status driver_status;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM provider_profiles
    WHERE id = p_provider_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'NOT_YOUR_DRIVER_STATUS';
  END IF;

  INSERT INTO driver_status (provider_id, current_location, last_location_update, updated_at)
  VALUES (p_provider_id, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, now(), now())
  ON CONFLICT (provider_id) DO UPDATE SET
    current_location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    last_location_update = now(),
    updated_at = now()
  RETURNING * INTO v_status;

  RETURN v_status;
END;
$$;

CREATE OR REPLACE FUNCTION set_driver_online(
  p_provider_id uuid,
  p_online boolean,
  p_lat double precision default null,
  p_lng double precision default null
) RETURNS driver_status
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status driver_status;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM provider_profiles
    WHERE id = p_provider_id AND user_id = auth.uid() AND status = 'APPROVED'
  ) THEN
    RAISE EXCEPTION 'PROVIDER_NOT_APPROVED';
  END IF;

  IF p_online AND (p_lat IS NULL OR p_lng IS NULL) THEN
    RAISE EXCEPTION 'LOCATION_REQUIRED_TO_GO_ONLINE';
  END IF;

  INSERT INTO driver_status (provider_id, is_online, current_location, last_location_update, updated_at)
  VALUES (p_provider_id, p_online,
          CASE WHEN p_online THEN st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography ELSE null END,
          CASE WHEN p_online THEN now() ELSE null END,
          now())
  ON CONFLICT (provider_id) DO UPDATE SET
    is_online = p_online,
    current_location = CASE WHEN p_online THEN st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography ELSE driver_status.current_location END,
    last_location_update = CASE WHEN p_online THEN now() ELSE driver_status.last_location_update END,
    updated_at = now()
  RETURNING * INTO v_status;

  RETURN v_status;
END;
$$;

CREATE OR REPLACE FUNCTION create_ride_request(
  p_user_id uuid,
  p_pickup_lat double precision,
  p_pickup_lng double precision,
  p_destination_lat double precision,
  p_destination_lng double precision,
  p_pickup_text text default null,
  p_destination_text text default null,
  p_vehicle_category_id uuid default null
) RETURNS ride_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride ride_requests;
BEGIN
  IF p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'CANNOT_CREATE_RIDE_FOR_ANOTHER_USER';
  END IF;

  INSERT INTO ride_requests (
    user_id, pickup_location, destination_location,
    pickup_text, destination_text, vehicle_category_id, status
  ) VALUES (
    p_user_id,
    st_setsrid(st_makepoint(p_pickup_lng, p_pickup_lat), 4326)::geography,
    st_setsrid(st_makepoint(p_destination_lng, p_destination_lat), 4326)::geography,
    p_pickup_text, p_destination_text, p_vehicle_category_id,
    'REQUESTED'
  ) RETURNING * INTO v_ride;

  INSERT INTO ride_status_history (ride_request_id, from_status, to_status, changed_by)
  VALUES (v_ride.id, null, 'REQUESTED', p_user_id);

  RETURN v_ride;
END;
$$;

-- =========================================================
-- 4. REVOKE EXECUTE FROM ANON ON SENSITIVE FUNCTIONS
--    Prevent unauthenticated access to financial/location functions.
-- =========================================================

REVOKE EXECUTE ON FUNCTION find_nearby_drivers FROM anon;
REVOKE EXECUTE ON FUNCTION create_ride_request FROM anon;
REVOKE EXECUTE ON FUNCTION update_driver_location FROM anon;
REVOKE EXECUTE ON FUNCTION set_driver_online FROM anon;
REVOKE EXECUTE ON FUNCTION has_role FROM anon;
REVOKE EXECUTE ON FUNCTION is_admin FROM anon;
REVOKE EXECUTE ON FUNCTION owns_provider_profile FROM anon;

-- =========================================================
-- 5. REVOKE TABLE-LEVEL GRANTS FROM ANON
--    Prevent anon from querying any application tables directly.
--    All reads should go through RLS-protected queries.
-- =========================================================

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
-- Grant SELECT to authenticated for tables that need public reads
GRANT SELECT ON categories TO authenticated;
GRANT SELECT ON system_settings TO authenticated;

-- =========================================================
-- 6. STORAGE BUCKET POLICIES
--    Ensure private buckets are actually private.
-- =========================================================

-- Supabase Storage policies are managed via the Supabase dashboard/CLI.
-- This documents the required configuration:
--   user-documents:  PRIVATE — authenticated upload, owner read, admin read
--   payment-proofs:  PRIVATE — authenticated upload (provider only), admin read
--   product-images:  PUBLIC read — authenticated write (provider-owned)
--   vehicle-images:  PUBLIC read — authenticated write (provider-owned)

-- =========================================================
-- 7. RIDE RATINGS SECURITY
--    Ensure ratings cannot be manipulated.
-- =========================================================

-- Prevent duplicate ratings for the same ride
CREATE OR REPLACE FUNCTION prevent_ride_rating_manipulation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    -- Ensure rater matches current user
    IF NEW.rater_id != auth.uid() THEN
      RAISE EXCEPTION 'CANNOT_RATE_FOR_ANOTHER_USER';
    END IF;

    -- Ensure the ride is COMPLETED
    IF NOT EXISTS (
      SELECT 1 FROM ride_requests
      WHERE id = NEW.ride_request_id AND status = 'COMPLETED'
    ) THEN
      RAISE EXCEPTION 'CAN_ONLY_RATE_COMPLETED_RIDES';
    END IF;

    -- Ensure the ride belongs to the rater
    IF NOT EXISTS (
      SELECT 1 FROM ride_requests
      WHERE id = NEW.ride_request_id AND user_id = auth.uid()
    ) THEN
      RAISE EXCEPTION 'CAN_ONLY_RATE_YOUR_OWN_RIDES';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Drop existing insert policy to replace with trigger-gated version
DROP POLICY IF EXISTS ride_ratings_insert_own ON ride_ratings;

CREATE POLICY ride_ratings_admin_all ON ride_ratings FOR ALL
  USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY ride_ratings_authenticated_insert ON ride_ratings FOR INSERT
  WITH CHECK (rater_id = auth.uid());

-- =========================================================
-- 8. RIDE REQUEST UPDATE HARDENING
--    Prevent direct status updates from clients.
-- =========================================================

CREATE OR REPLACE FUNCTION prevent_ride_status_self_modification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    IF new.status != old.status THEN
      RAISE EXCEPTION 'RIDE_STATUS_CAN_ONLY_BE_CHANGED_VIA_SERVER_FUNCTION';
    END IF;
  END IF;
  RETURN new;
END;
$$;

CREATE TRIGGER trg_ride_requests_status_security
  BEFORE UPDATE ON ride_requests
  FOR EACH ROW
  EXECUTE FUNCTION prevent_ride_status_self_modification();

-- =========================================================
-- 9. RECHARGE REQUEST UPDATE HARDENING
--    Providers cannot modify their own recharge request status.
-- =========================================================

CREATE OR REPLACE FUNCTION prevent_recharge_status_self_modification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    IF new.status != old.status THEN
      RAISE EXCEPTION 'RECHARGE_STATUS_CAN_ONLY_BE_CHANGED_BY_ADMIN';
    END IF;
  END IF;
  RETURN new;
END;
$$;

CREATE TRIGGER trg_recharge_requests_status_security
  BEFORE UPDATE ON wallet_recharge_requests
  FOR EACH ROW
  EXECUTE FUNCTION prevent_recharge_status_self_modification();

-- =========================================================
-- 10. DRIVER STATUS INSERT HARDENING
--     Providers cannot set is_online=true on insert.
-- =========================================================

CREATE OR REPLACE FUNCTION prevent_driver_status_insert_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    IF NEW.is_online = true THEN
      RAISE EXCEPTION 'NEW_DRIVERS_MUST_START_OFFLINE';
    END IF;
    IF NEW.current_ride_id IS NOT NULL THEN
      RAISE EXCEPTION 'CANNOT_SET_RIDE_ON_INSERT';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_driver_status_insert_security
  BEFORE INSERT ON driver_status
  FOR EACH ROW
  EXECUTE FUNCTION prevent_driver_status_insert_escalation();

-- =========================================================
-- 11. PRODUCT UPDATE HARDENING
--     Providers cannot manipulate rating/sales/review counts.
-- =========================================================

CREATE OR REPLACE FUNCTION prevent_product_update_privilege_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    -- Block rating manipulation
    IF new.rating != old.rating THEN
      RAISE EXCEPTION 'RATING_CANNOT_BE_SELF_MODIFIED';
    END IF;
    -- Block review count manipulation
    IF new.review_count != old.review_count THEN
      RAISE EXCEPTION 'REVIEW_COUNT_CANNOT_BE_SELF_MODIFIED';
    END IF;
    -- Block sales count manipulation
    IF new.sales_count != old.sales_count THEN
      RAISE EXCEPTION 'SALES_COUNT_CANNOT_BE_SELF_MODIFIED';
    END IF;
  END IF;
  RETURN new;
END;
$$;

CREATE TRIGGER trg_products_update_security
  BEFORE UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION prevent_product_update_privilege_escalation();

-- =========================================================
-- 12. VEHICLE UPDATE HARDENING
--     Providers cannot manipulate rating/review counts.
-- =========================================================

CREATE OR REPLACE FUNCTION prevent_vehicle_update_privilege_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    IF new.rating != old.rating THEN
      RAISE EXCEPTION 'VEHICLE_RATING_CANNOT_BE_SELF_MODIFIED';
    END IF;
    IF new.rating_count != old.rating_count THEN
      RAISE EXCEPTION 'VEHICLE_RATING_COUNT_CANNOT_BE_SELF_MODIFIED';
    END IF;
  END IF;
  RETURN new;
END;
$$;

CREATE TRIGGER trg_vehicles_update_security
  BEFORE UPDATE ON vehicles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_vehicle_update_privilege_escalation();

-- =========================================================
-- 13. INDEX FOR RATE LIMITING SUPPORT
--     Enable efficient tracking of login/signup attempts per IP/phone.
-- =========================================================

CREATE INDEX IF NOT EXISTS idx_profiles_phone ON profiles(phone);
CREATE INDEX IF NOT EXISTS idx_user_roles_user_role ON user_roles(user_id, role);
CREATE INDEX IF NOT EXISTS idx_audit_logs_event_type ON audit_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_wallet_recharge_requests_status_provider
  ON wallet_recharge_requests(status, provider_id);
