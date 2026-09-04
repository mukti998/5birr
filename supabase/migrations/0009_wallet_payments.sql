-- 5BIRR — Wallet & Payment System
-- Migration 0009_wallet_payments.sql
-- Adds payment methods, wallet recharge requests, and extends enums.

-- =========================================================
-- 1. EXTEND ENUMS
-- =========================================================

-- Extend wallet_txn_type with RECHARGE and ADMIN_CASH
ALTER TYPE wallet_txn_type ADD VALUE IF NOT EXISTS 'RECHARGE' BEFORE 'WITHDRAWAL';
ALTER TYPE wallet_txn_type ADD VALUE IF NOT EXISTS 'ADMIN_CASH' BEFORE 'ADJUSTMENT';

-- =========================================================
-- 2. PAYMENT METHODS (admin-configured)
-- =========================================================

create table if not exists payment_methods (
  id uuid primary key default uuid_generate_v4(),
  name text not null,               -- 'Telebirr', 'CBE Birr', 'Bank Transfer', etc.
  account_name text,                 -- receiver/account name
  account_number text,               -- phone, account number, etc.
  instructions text,                 -- how-to-pay instructions
  logo_storage_path text,            -- optional logo image
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_payment_methods_active on payment_methods(is_active) where is_active = true;

-- =========================================================
-- 3. WALLET RECHARGE REQUESTS
-- =========================================================

create type recharge_status as enum ('PENDING','APPROVED','REJECTED');

create table if not exists wallet_recharge_requests (
  id uuid primary key default uuid_generate_v4(),
  provider_id uuid not null references provider_profiles(id) on delete cascade,
  wallet_id uuid not null references wallets(id) on delete cascade,
  payment_method_id uuid references payment_methods(id),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'ETB',
  payment_reference text,            -- transaction/ref number from provider
  screenshot_storage_path text,      -- private bucket path
  status recharge_status not null default 'PENDING',
  rejection_reason text,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_recharge_requests_provider on wallet_recharge_requests(provider_id);
create index idx_recharge_requests_status on wallet_recharge_requests(status);
create index idx_recharge_requests_wallet on wallet_recharge_requests(wallet_id);

-- =========================================================
-- 4. ADMIN CASH RECHARGE / ADJUSTMENT LOG
--    Extends the existing audit_logs for financial actions.
--    We also add a dedicated admin_wallet_actions table
--    for clear financial audit trail.
-- =========================================================

create table if not exists admin_wallet_actions (
  id uuid primary key default uuid_generate_v4(),
  admin_id uuid not null references auth.users(id),
  provider_id uuid not null references provider_profiles(id),
  wallet_id uuid not null references wallets(id),
  action_type text not null check (action_type in ('CASH_RECHARGE','ADJUSTMENT_CREDIT','ADJUSTMENT_DEBIT')),
  amount numeric(12,2) not null check (amount > 0),
  reason text not null,
  balance_before numeric(12,2) not null,
  balance_after numeric(12,2) not null,
  created_at timestamptz not null default now()
);

create index idx_admin_wallet_actions_admin on admin_wallet_actions(admin_id);
create index idx_admin_wallet_actions_provider on admin_wallet_actions(provider_id);

-- =========================================================
-- 5. ENABLE RLS
-- =========================================================

alter table payment_methods enable row level security;
alter table wallet_recharge_requests enable row level security;
alter table admin_wallet_actions enable row level security;

-- payment_methods: admin full, authenticated read active
create policy payment_methods_admin_all on payment_methods for all
  using (is_admin()) with check (is_admin());
create policy payment_methods_read_active on payment_methods for select
  using (is_active = true or is_admin());

-- wallet_recharge_requests: provider can insert/select own, admin full
create policy recharge_requests_provider_insert on wallet_recharge_requests for insert
  with check (
    provider_id in (
      select id from provider_profiles where user_id = auth.uid()
    )
  );
create policy recharge_requests_provider_read_own on wallet_recharge_requests for select
  using (
    provider_id in (
      select id from provider_profiles where user_id = auth.uid()
    )
  );
create policy recharge_requests_admin_all on wallet_recharge_requests for all
  using (is_admin()) with check (is_admin());

-- admin_wallet_actions: admin only
create policy admin_wallet_actions_admin_only on admin_wallet_actions for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- 6. UPDATED_AT TRIGGERS
-- =========================================================

create trigger trg_payment_methods_updated before update on payment_methods
  for each row execute function set_updated_at();
create trigger trg_recharge_requests_updated before update on wallet_recharge_requests
  for each row execute function set_updated_at();

-- =========================================================
-- 7. WALLET RECHARGE CREDIT FUNCTION (SECURITY DEFINER)
--    Atomically credits wallet when admin approves recharge.
--    Idempotent: checks recharge request status before acting.
-- =========================================================

create or replace function approve_wallet_recharge(
  p_recharge_id uuid,
  p_admin_id uuid
) returns wallet_recharge_requests
language plpgsql
security definer
as $$
declare
  v_recharge wallet_recharge_requests;
  v_wallet wallets;
  v_txn wallet_transactions;
begin
  -- Verify admin
  if not exists (
    select 1 from user_roles where user_id = p_admin_id and role = 'ADMIN'
  ) then
    raise exception 'ONLY_ADMINISTRATORS_CAN_APPROVE_RECHARGES';
  end if;

  -- Lock the recharge row
  select * into v_recharge from wallet_recharge_requests
    where id = p_recharge_id for update;

  if v_recharge.id is null then
    raise exception 'RECHARGE_REQUEST_NOT_FOUND';
  end if;

  -- Idempotency: already approved
  if v_recharge.status = 'APPROVED' then
    return v_recharge;
  end if;

  -- Must be PENDING
  if v_recharge.status != 'PENDING' then
    raise exception 'RECHARGE_REQUEST_IS_NOT_PENDING';
  end if;

  -- Lock wallet
  select * into v_wallet from wallets
    where id = v_recharge.wallet_id for update;

  if v_wallet.id is null then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  -- Credit wallet
  update wallets
  set balance = balance + v_recharge.amount,
      updated_at = now()
  where id = v_wallet.id
  returning * into v_wallet;

  -- Record wallet transaction
  insert into wallet_transactions (
    wallet_id, provider_id, transaction_type,
    gross_amount, platform_fee, net_amount,
    balance_after, status, idempotency_key
  ) values (
    v_wallet.id, v_recharge.provider_id, 'RECHARGE',
    v_recharge.amount, 0, v_recharge.amount,
    v_wallet.balance, 'COMPLETED',
    'recharge:' || v_recharge.id::text
  ) returning * into v_txn;

  -- Mark recharge as approved
  update wallet_recharge_requests
  set status = 'APPROVED',
      approved_by = p_admin_id,
      approved_at = now(),
      updated_at = now()
  where id = p_recharge_id
  returning * into v_recharge;

  -- Notify provider
  insert into notifications (user_id, type, title, body)
  select pp.user_id, 'APPROVAL', 'Recharge Approved',
         v_recharge.amount::text || ' ETB has been credited to your wallet.'
  from provider_profiles pp where pp.id = v_recharge.provider_id;

  -- Audit log
  insert into audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  values (p_admin_id, 'WALLET_RECHARGE_APPROVED', 'wallets', v_wallet.id,
          jsonb_build_object('recharge_id', p_recharge_id, 'amount', v_recharge.amount,
                             'provider_id', v_recharge.provider_id));

  return v_recharge;
end;
$$;

-- =========================================================
-- 8. WALLET RECHARGE REJECT FUNCTION
-- =========================================================

create or replace function reject_wallet_recharge(
  p_recharge_id uuid,
  p_admin_id uuid,
  p_reason text
) returns wallet_recharge_requests
language plpgsql
security definer
as $$
declare
  v_recharge wallet_recharge_requests;
begin
  if not exists (
    select 1 from user_roles where user_id = p_admin_id and role = 'ADMIN'
  ) then
    raise exception 'ONLY_ADMINISTRATORS_CAN_REJECT_RECHARGES';
  end if;

  select * into v_recharge from wallet_recharge_requests
    where id = p_recharge_id for update;

  if v_recharge.id is null then
    raise exception 'RECHARGE_REQUEST_NOT_FOUND';
  end if;

  if v_recharge.status != 'PENDING' then
    raise exception 'RECHARGE_REQUEST_IS_NOT_PENDING';
  end if;

  update wallet_recharge_requests
  set status = 'REJECTED',
      rejection_reason = p_reason,
      approved_by = p_admin_id,
      approved_at = now(),
      updated_at = now()
  where id = p_recharge_id
  returning * into v_recharge;

  -- Notify provider
  insert into notifications (user_id, type, title, body)
  select pp.user_id, 'REJECTION', 'Recharge Rejected',
         'Your recharge of ' || v_recharge.amount::text || ' ETB was rejected. Reason: ' || p_reason
  from provider_profiles pp where pp.id = v_recharge.provider_id;

  insert into audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  values (p_admin_id, 'WALLET_RECHARGE_REJECTED', 'wallets',
          (select wallet_id from wallet_recharge_requests where id = p_recharge_id),
          jsonb_build_object('recharge_id', p_recharge_id, 'reason', p_reason,
                             'provider_id', v_recharge.provider_id));

  return v_recharge;
end;
$$;

-- =========================================================
-- 9. ADMIN CASH RECHARGE FUNCTION
-- =========================================================

create or replace function admin_cash_recharge(
  p_provider_id uuid,
  p_amount numeric,
  p_reason text,
  p_admin_id uuid
) returns wallets
language plpgsql
security definer
as $$
declare
  v_wallet wallets;
  v_balance_before numeric;
begin
  if not exists (
    select 1 from user_roles where user_id = p_admin_id and role = 'ADMIN'
  ) then
    raise exception 'ONLY_ADMINISTRATORS_CAN_PERFORM_CASH_RECHARGE';
  end if;

  if p_amount <= 0 then
    raise exception 'AMOUNT_MUST_BE_POSITIVE';
  end if;

  select * into v_wallet from wallets
    where provider_id = p_provider_id for update;

  if v_wallet.id is null then
    raise exception 'WALLET_NOT_FOUND_FOR_PROVIDER';
  end if;

  v_balance_before := v_wallet.balance;

  -- Credit wallet
  update wallets
  set balance = balance + p_amount, updated_at = now()
  where id = v_wallet.id
  returning * into v_wallet;

  -- Record transaction
  insert into wallet_transactions (
    wallet_id, provider_id, transaction_type,
    gross_amount, platform_fee, net_amount,
    balance_after, status, idempotency_key
  ) values (
    v_wallet.id, p_provider_id, 'ADMIN_CASH',
    p_amount, 0, p_amount,
    v_wallet.balance, 'COMPLETED',
    'admin-cash:' || p_provider_id::text || ':' || now()::text
  );

  -- Record admin action
  insert into admin_wallet_actions (
    admin_id, provider_id, wallet_id, action_type,
    amount, reason, balance_before, balance_after
  ) values (
    p_admin_id, p_provider_id, v_wallet.id, 'CASH_RECHARGE',
    p_amount, p_reason, v_balance_before, v_wallet.balance
  );

  -- Notify provider
  insert into notifications (user_id, type, title, body)
  select pp.user_id, 'APPROVAL', 'Cash Recharge',
         p_amount::text || ' ETB has been credited to your wallet (cash payment).'
  from provider_profiles pp where pp.id = p_provider_id;

  insert into audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  values (p_admin_id, 'ADMIN_CASH_RECHARGE', 'wallets', v_wallet.id,
          jsonb_build_object('provider_id', p_provider_id, 'amount', p_amount, 'reason', p_reason));

  return v_wallet;
end;
$$;

-- =========================================================
-- 10. ADMIN WALLET ADJUSTMENT FUNCTION
-- =========================================================

create or replace function admin_wallet_adjustment(
  p_provider_id uuid,
  p_amount numeric,  -- positive for credit, negative for debit
  p_reason text,
  p_admin_id uuid
) returns wallets
language plpgsql
security definer
as $$
declare
  v_wallet wallets;
  v_balance_before numeric;
  v_action_type text;
begin
  if not exists (
    select 1 from user_roles where user_id = p_admin_id and role = 'ADMIN'
  ) then
    raise exception 'ONLY_ADMINISTRATORS_CAN_ADJUST_WALLETS';
  end if;

  if p_amount = 0 then
    raise exception 'AMOUNT_CANNOT_BE_ZERO';
  end if;

  select * into v_wallet from wallets
    where provider_id = p_provider_id for update;

  if v_wallet.id is null then
    raise exception 'WALLET_NOT_FOUND_FOR_PROVIDER';
  end if;

  v_balance_before := v_wallet.balance;

  if p_amount > 0 then
    v_action_type := 'ADJUSTMENT_CREDIT';
  else
    v_action_type := 'ADJUSTMENT_DEBIT';
  end if;

  -- Prevent negative balance (unless allow_negative_wallet is true)
  if p_amount < 0 and v_wallet.balance + p_amount < 0 then
    if not (select (value #>> '{}')::boolean from system_settings where key = 'allow_negative_wallet') then
      raise exception 'INSUFFICIENT_BALANCE_FOR_DEBIT';
    end if;
  end if;

  update wallets
  set balance = balance + p_amount, updated_at = now()
  where id = v_wallet.id
  returning * into v_wallet;

  insert into wallet_transactions (
    wallet_id, provider_id, transaction_type,
    gross_amount, platform_fee, net_amount,
    balance_after, status, idempotency_key
  ) values (
    v_wallet.id, p_provider_id, 'ADJUSTMENT',
    abs(p_amount), 0, abs(p_amount),
    v_wallet.balance, 'COMPLETED',
    'adjustment:' || p_provider_id::text || ':' || now()::text
  );

  insert into admin_wallet_actions (
    admin_id, provider_id, wallet_id, action_type,
    amount, reason, balance_before, balance_after
  ) values (
    p_admin_id, p_provider_id, v_wallet.id, v_action_type,
    abs(p_amount), p_reason, v_balance_before, v_wallet.balance
  );

  insert into notifications (user_id, type, title, body)
  select pp.user_id, 'ADMIN_MESSAGE', 'Wallet Adjustment',
         'Your wallet has been adjusted by ' || p_amount::text || ' ETB. Reason: ' || p_reason
  from provider_profiles pp where pp.id = p_provider_id;

  insert into audit_logs (actor_id, event_type, entity_type, entity_id, metadata)
  values (p_admin_id, 'ADMIN_WALLET_ADJUSTMENT', 'wallets', v_wallet.id,
          jsonb_build_object('provider_id', p_provider_id, 'amount', p_amount, 'reason', p_reason));

  return v_wallet;
end;
$$;
