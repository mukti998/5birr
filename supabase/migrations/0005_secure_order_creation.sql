-- 0005_secure_order_creation.sql
--
-- Adds:
--   1. create_order_secure() — SECURITY DEFINER function that atomically
--      inserts an order + its order_items. Called only from the
--      `order-create` Edge Function, which has already validated the
--      caller's identity and computed server-authoritative prices/total.
--   2. cart_items table — minimal persistent cart, referenced in the
--      5BIRR audit report (section 32/49) as not yet implemented.
--
-- Apply with: supabase db push  (or via your existing migration pipeline)

-- ============================================================================
-- 1. Secure, atomic order creation
-- ============================================================================

create or replace function create_order_secure(
  p_user_id uuid,
  p_provider_id uuid,
  p_items jsonb,          -- [{ product_id, quantity, unit_price }]
  p_total_amount numeric,
  p_currency text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_item jsonb;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'p_items must be a non-empty array';
  end if;

  insert into orders (
    id, user_id, provider_id, status, total_amount, currency,
    requires_payment_proof, created_at
  )
  values (
    gen_random_uuid(), p_user_id, p_provider_id, 'CREATED', p_total_amount,
    coalesce(p_currency, 'ETB'), true, now()
  )
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into order_items (id, order_id, product_id, quantity, unit_price)
    values (
      gen_random_uuid(),
      v_order_id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::int,
      (v_item->>'unit_price')::numeric
    );
  end loop;

  insert into order_status_history (id, order_id, from_status, to_status, changed_by, note)
  values (gen_random_uuid(), v_order_id, null, 'CREATED', p_user_id, p_note);

  return (
    select to_jsonb(o) from orders o where o.id = v_order_id
  );
end;
$$;

-- Only callable via the service-role key (Edge Function), never directly by
-- authenticated/anon clients.
revoke execute on function create_order_secure(uuid, uuid, jsonb, numeric, text, text)
  from public, anon, authenticated;
grant execute on function create_order_secure(uuid, uuid, jsonb, numeric, text, text)
  to service_role;

-- ============================================================================
-- 2. Cart items (foundation for the checkout flow that calls order-create)
-- ============================================================================

create table if not exists cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  quantity int not null check (quantity > 0),
  added_at timestamptz not null default now(),
  unique (user_id, product_id)
);

alter table cart_items enable row level security;

create policy "Users manage their own cart"
  on cart_items
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
