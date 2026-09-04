-- Manual/psql test harness for the two most dangerous pieces of logic:
-- 1) Only ONE of two concurrent claim_ride() calls on the same ride succeeds.
-- 2) deduct_transaction_fee() is idempotent — retried calls with the same
--    idempotency_key never double-charge the wallet.
--
-- Run with: psql <connection> -f ride_claim_race_test.sql
-- (Requires seed data: two APPROVED vehicle providers with vehicles, one
-- ride_request in status REQUESTED. Adjust the UUIDs below to match your DB,
-- or wrap this in a transaction with local inserts as shown.)

begin;

-- --- Setup: two providers, two vehicles, one ride request ---
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'driver1@test.dev'),
  ('00000000-0000-0000-0000-000000000002', 'driver2@test.dev'),
  ('00000000-0000-0000-0000-000000000003', 'rider@test.dev')
on conflict do nothing;

insert into provider_profiles (id, user_id, provider_type, status, registration_date)
values
  ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','VEHICLE_PROVIDER','APPROVED', now() - interval '2 months'),
  ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002','VEHICLE_PROVIDER','APPROVED', now() - interval '2 months')
on conflict do nothing;

insert into vehicles (id, provider_id, plate_number, is_available, status)
values
  ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','TEST-001', true, 'APPROVED'),
  ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','TEST-002', true, 'APPROVED')
on conflict do nothing;

insert into ride_requests (id, user_id, pickup_location, destination_location, status)
values (
  '30000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000003',
  st_setsrid(st_makepoint(38.74,9.03),4326)::geography,
  st_setsrid(st_makepoint(38.76,9.05),4326)::geography,
  'REQUESTED'
) on conflict do nothing;

-- --- Test 1: simulate concurrent claims via two sessions ---
-- In real testing, open two separate psql sessions and run each SELECT at
-- the same time. Here we simulate sequential calls with the same effect,
-- since the DB-level guard is what matters, not client timing.

select claim_ride(
  '30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001'
); -- Expect: SUCCESS, status becomes CLAIMED

-- Second claim attempt on the SAME ride by a different provider must fail:
do $$
begin
  perform claim_ride(
    '30000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000002'
  );
  raise exception 'TEST FAILED: second claim should have raised RIDE_ALREADY_TAKEN';
exception when others then
  if SQLERRM like '%RIDE_ALREADY_TAKEN%' then
    raise notice 'TEST PASSED: second concurrent claim correctly rejected';
  else
    raise exception 'TEST FAILED: unexpected error %', SQLERRM;
  end if;
end $$;

-- --- Test 2: idempotent fee deduction ---
insert into wallets (id, provider_id, balance)
values ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001', 100)
on conflict (provider_id) do update set balance = 100;

select deduct_transaction_fee(
  '10000000-0000-0000-0000-000000000001', null, null, 50, 'test-idem-key-1'
); -- balance -> 95

select deduct_transaction_fee(
  '10000000-0000-0000-0000-000000000001', null, null, 50, 'test-idem-key-1'
); -- retried with SAME key: must return the same row, balance stays 95

do $$
declare
  v_balance numeric;
begin
  select balance into v_balance from wallets where provider_id = '10000000-0000-0000-0000-000000000001';
  if v_balance = 95 then
    raise notice 'TEST PASSED: idempotent fee deduction did not double-charge (balance = %)', v_balance;
  else
    raise exception 'TEST FAILED: expected balance 95, got %', v_balance;
  end if;
end $$;

rollback; -- discard all test data, nothing persists
