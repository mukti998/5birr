-- 5BIRR Phase 1 — Core Schema
-- Migration 0001_core_schema.sql
-- Run in order: 0001 -> 0002 (rls) -> 0003 (functions/triggers) -> 0004 (seed, optional)

create extension if not exists "uuid-ossp";
create extension if not exists postgis;
create extension if not exists pg_trgm;

-- =========================================================
-- ENUMS
-- =========================================================
create type app_role as enum ('USER','VEHICLE_PROVIDER','SERVICE_PROVIDER','ADMIN');
create type account_status as enum ('PENDING_APPROVAL','APPROVED','REJECTED','SUSPENDED','INACTIVE');
create type approval_action as enum ('APPROVE','REJECT','REQUEST_CORRECTION','SUSPEND','DELETE');
create type ride_status as enum ('REQUESTED','CLAIMED','DRIVER_ARRIVING','STARTED','COMPLETED','CANCELLED');
create type order_status as enum (
  'CREATED','PENDING_PROVIDER','ACCEPTED','PAYMENT_PENDING','PAYMENT_VERIFICATION',
  'APPROVED','STARTED','COMPLETED','CANCELLED','DISPUTED','REFUNDED','REJECTED'
);
create type wallet_txn_type as enum ('TRANSACTION_FEE','SUBSCRIPTION_FEE','DEPOSIT','WITHDRAWAL','ADJUSTMENT','REFUND');
create type wallet_txn_status as enum ('PENDING','COMPLETED','FAILED','REVERSED');
create type notification_type as enum (
  'REGISTRATION_RECEIVED','APPROVAL','REJECTION','CORRECTION_REQUIRED','ADMIN_MESSAGE',
  'ORDER_RECEIVED','ORDER_ACCEPTED','ORDER_REJECTED','RIDE_REQUEST','RIDE_CLAIMED','RIDE_TAKEN',
  'RIDE_STARTED','RIDE_COMPLETED','PAYMENT_REMINDER','PAYMENT_PROOF_REQUIRED','WALLET_LOW',
  'WALLET_EMPTY','SUBSCRIPTION_DUE','PROVIDER_INACTIVE','TRANSACTION_FEE_DEDUCTED','SECURITY'
);

-- =========================================================
-- SYSTEM SETTINGS (configurable business rules)
-- =========================================================
create table system_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_by uuid,
  updated_at timestamptz not null default now()
);

insert into system_settings (key, value, description) values
  ('monthly_subscription_fee', '5', 'Birr charged monthly to providers'),
  ('transaction_fee', '5', 'Birr charged per completed provider transaction'),
  ('subscription_grace_period_days', '3', 'Days after due date before restriction'),
  ('low_wallet_threshold', '15', 'Balance below this triggers low-wallet warning'),
  ('minimum_wallet_balance', '0', 'Floor for wallet balance; negative not allowed unless changed'),
  ('allow_negative_wallet', 'false', 'Whether wallet can go negative'),
  ('default_ride_search_radius_km', '5', 'Default radius for nearby ride/provider search'),
  ('payment_proof_required', 'true', 'Whether payment screenshot proof is required before protected stage'),
  ('provider_approval_required', 'true', 'Whether admin approval is required before providers go live');

-- =========================================================
-- PROFILES / ROLES
-- =========================================================
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text unique,
  email text,
  national_id text,
  status account_status not null default 'PENDING_APPROVAL',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table user_roles (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role app_role not null,
  created_at timestamptz not null default now(),
  unique (user_id, role)
);
create index idx_user_roles_user on user_roles(user_id);

create table user_documents (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_type text not null, -- 'NATIONAL_ID','DRIVING_LICENSE','TRADE_LICENSE', etc.
  storage_path text not null,  -- private bucket path, access via signed URL only
  uploaded_at timestamptz not null default now()
);
create index idx_user_documents_user on user_documents(user_id);

-- =========================================================
-- PROVIDER PROFILES
-- =========================================================
create table provider_profiles (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_type app_role not null check (provider_type in ('VEHICLE_PROVIDER','SERVICE_PROVIDER')),
  business_name text,
  owner_national_id text,
  status account_status not null default 'PENDING_APPROVAL',
  registration_date timestamptz not null default now(),
  subscription_start_date timestamptz generated always as (registration_date + interval '1 month') stored,
  category_id uuid,
  location geography(Point,4326),
  address_text text,
  service_area_radius_km numeric default 5,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider_type)
);
create index idx_provider_profiles_user on provider_profiles(user_id);
create index idx_provider_profiles_status on provider_profiles(status);
create index idx_provider_profiles_location on provider_profiles using gist(location);

-- =========================================================
-- APPROVALS
-- =========================================================
create table approval_requests (
  id uuid primary key default uuid_generate_v4(),
  subject_type text not null, -- 'USER' | 'PROVIDER'
  subject_id uuid not null,   -- profiles.id or provider_profiles.id
  status account_status not null default 'PENDING_APPROVAL',
  created_at timestamptz not null default now()
);

create table approval_history (
  id uuid primary key default uuid_generate_v4(),
  approval_request_id uuid references approval_requests(id) on delete set null,
  subject_type text not null,
  subject_id uuid not null,
  action approval_action not null,
  reason text,
  performed_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index idx_approval_history_subject on approval_history(subject_type, subject_id);

-- =========================================================
-- CATEGORIES (admin-editable, no hardcoding)
-- =========================================================
create table categories (
  id uuid primary key default uuid_generate_v4(),
  parent_id uuid references categories(id) on delete cascade,
  name text not null,
  sector text not null check (sector in ('SERVICE','VEHICLE')),
  slug text not null unique,
  icon text,
  is_active boolean not null default true,
  sort_order int default 0,
  created_at timestamptz not null default now()
);
create index idx_categories_parent on categories(parent_id);
create index idx_categories_sector on categories(sector);

alter table provider_profiles
  add constraint fk_provider_category foreign key (category_id) references categories(id);

-- =========================================================
-- VEHICLES
-- =========================================================
create table vehicles (
  id uuid primary key default uuid_generate_v4(),
  provider_id uuid not null references provider_profiles(id) on delete cascade,
  category_id uuid references categories(id),
  brand text,
  model text,
  plate_number text not null,
  color text,
  capacity int,
  current_location geography(Point,4326),
  is_available boolean not null default true,
  status account_status not null default 'PENDING_APPROVAL',
  rating numeric default 0,
  rating_count int default 0,
  created_at timestamptz not null default now(),
  unique (plate_number)
);
create index idx_vehicles_provider on vehicles(provider_id);
create index idx_vehicles_location on vehicles using gist(current_location);
create index idx_vehicles_available on vehicles(is_available) where is_available = true;

create table vehicle_images (
  id uuid primary key default uuid_generate_v4(),
  vehicle_id uuid not null references vehicles(id) on delete cascade,
  storage_path text not null,
  sort_order int default 0
);

-- =========================================================
-- PRODUCTS / SERVICES
-- =========================================================
create table products (
  id uuid primary key default uuid_generate_v4(),
  provider_id uuid not null references provider_profiles(id) on delete cascade,
  category_id uuid references categories(id),
  name text not null,
  description text,
  price numeric(12,2) not null default 0,
  currency text not null default 'ETB',
  quantity int,
  is_available boolean not null default true,
  is_active boolean not null default true,
  location geography(Point,4326),
  rating numeric default 0,
  review_count int default 0,
  sales_count int default 0,
  search_vector tsvector generated always as (
    setweight(to_tsvector('simple', coalesce(name,'')), 'A') ||
    setweight(to_tsvector('simple', coalesce(description,'')), 'B')
  ) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_products_provider on products(provider_id);
create index idx_products_category on products(category_id);
create index idx_products_location on products using gist(location);
create index idx_products_search on products using gin(search_vector);
create index idx_products_trgm_name on products using gin(name gin_trgm_ops);

create table product_images (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid not null references products(id) on delete cascade,
  storage_path text not null,
  sort_order int default 0
);
create index idx_product_images_product on product_images(product_id);

-- =========================================================
-- ORDERS
-- =========================================================
create table orders (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id),
  provider_id uuid not null references provider_profiles(id),
  status order_status not null default 'CREATED',
  total_amount numeric(12,2) not null default 0,
  currency text not null default 'ETB',
  requires_payment_proof boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_orders_user on orders(user_id);
create index idx_orders_provider on orders(provider_id);
create index idx_orders_status on orders(status);

create table order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid references products(id),
  quantity int not null default 1,
  unit_price numeric(12,2) not null,
  subtotal numeric(12,2) generated always as (quantity * unit_price) stored
);
create index idx_order_items_order on order_items(order_id);

create table order_status_history (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references orders(id) on delete cascade,
  from_status order_status,
  to_status order_status not null,
  changed_by uuid references auth.users(id),
  note text,
  created_at timestamptz not null default now()
);
create index idx_order_status_history_order on order_status_history(order_id);

-- =========================================================
-- PAYMENT AGREEMENT / PROOF
-- =========================================================
create table payment_agreements (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references orders(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  accepted boolean not null default false,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (order_id)
);

create table payment_proofs (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references orders(id) on delete cascade,
  transaction_id uuid,
  storage_path text not null,
  verification_status text not null default 'PENDING' check (verification_status in ('PENDING','VERIFIED','REJECTED')),
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_payment_proofs_order on payment_proofs(order_id);

-- =========================================================
-- RIDE REQUESTS (real-time, atomic claim)
-- =========================================================
create table ride_requests (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id),
  pickup_location geography(Point,4326) not null,
  destination_location geography(Point,4326) not null,
  pickup_text text,
  destination_text text,
  vehicle_category_id uuid references categories(id),
  status ride_status not null default 'REQUESTED',
  claimed_by_provider_id uuid references provider_profiles(id),
  claimed_vehicle_id uuid references vehicles(id),
  claimed_at timestamptz,
  fare_estimate numeric(12,2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_ride_requests_status on ride_requests(status);
create index idx_ride_requests_pickup on ride_requests using gist(pickup_location);
create index idx_ride_requests_provider on ride_requests(claimed_by_provider_id);

-- Partial unique index: guarantees only one active claim per ride.
-- Combined with the atomic claim function (0003) this prevents double-claiming.
create unique index uq_ride_single_claim on ride_requests(id) where status = 'CLAIMED';

create table ride_status_history (
  id uuid primary key default uuid_generate_v4(),
  ride_request_id uuid not null references ride_requests(id) on delete cascade,
  from_status ride_status,
  to_status ride_status not null,
  changed_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- =========================================================
-- WALLET
-- =========================================================
create table wallets (
  id uuid primary key default uuid_generate_v4(),
  provider_id uuid not null unique references provider_profiles(id) on delete cascade,
  balance numeric(12,2) not null default 0,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','RESTRICTED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table wallet_transactions (
  id uuid primary key default uuid_generate_v4(),
  wallet_id uuid not null references wallets(id) on delete cascade,
  provider_id uuid not null references provider_profiles(id),
  order_id uuid references orders(id),
  ride_request_id uuid references ride_requests(id),
  transaction_type wallet_txn_type not null,
  gross_amount numeric(12,2) not null default 0,
  platform_fee numeric(12,2) not null default 0,
  net_amount numeric(12,2) not null default 0,
  balance_after numeric(12,2) not null,
  status wallet_txn_status not null default 'COMPLETED',
  idempotency_key text not null unique,
  created_at timestamptz not null default now()
);
create index idx_wallet_txn_wallet on wallet_transactions(wallet_id);
create index idx_wallet_txn_provider on wallet_transactions(provider_id);

-- =========================================================
-- SUBSCRIPTIONS
-- =========================================================
create table subscriptions (
  id uuid primary key default uuid_generate_v4(),
  provider_id uuid not null unique references provider_profiles(id) on delete cascade,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','DUE','GRACE','SUSPENDED')),
  next_due_date timestamptz not null,
  last_charged_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =========================================================
-- REVIEWS / FAVORITES
-- =========================================================
create table reviews (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id),
  target_type text not null check (target_type in ('PRODUCT','PROVIDER','VEHICLE')),
  target_id uuid not null,
  order_id uuid references orders(id), -- must reference a completed transaction
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (user_id, target_type, target_id, order_id)
);
create index idx_reviews_target on reviews(target_type, target_id);

create table favorites (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('PRODUCT','PROVIDER','VEHICLE')),
  target_id uuid not null,
  created_at timestamptz not null default now(),
  unique (user_id, target_type, target_id)
);

-- =========================================================
-- NOTIFICATIONS
-- =========================================================
create table notifications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type notification_type not null,
  title text not null,
  body text,
  data jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index idx_notifications_user on notifications(user_id, is_read);

create table notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  push_enabled boolean not null default true,
  in_app_enabled boolean not null default true
);

-- =========================================================
-- ADMIN / AUDIT
-- =========================================================
create table admin_actions (
  id uuid primary key default uuid_generate_v4(),
  admin_id uuid not null references auth.users(id),
  action text not null,
  target_type text,
  target_id uuid,
  details jsonb,
  created_at timestamptz not null default now()
);

create table support_tickets (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id),
  subject text not null,
  status text not null default 'OPEN' check (status in ('OPEN','IN_PROGRESS','RESOLVED','CLOSED')),
  created_at timestamptz not null default now()
);

create table appeals (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id),
  related_type text not null,
  related_id uuid not null,
  reason text not null,
  status text not null default 'PENDING' check (status in ('PENDING','APPROVED','DENIED')),
  reviewed_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table audit_logs (
  id uuid primary key default uuid_generate_v4(),
  actor_id uuid references auth.users(id),
  event_type text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);
create index idx_audit_logs_entity on audit_logs(entity_type, entity_id);
create index idx_audit_logs_actor on audit_logs(actor_id);
