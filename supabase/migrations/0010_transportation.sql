-- 5BIRR — Transportation System
-- Migration 0010_transportation.sql

-- =========================================================
-- 1. DRIVER ONLINE STATUS
-- =========================================================

create table if not exists driver_status (
  provider_id uuid primary key references provider_profiles(id) on delete cascade,
  is_online boolean not null default false,
  current_location geography(Point,4326),
  last_location_update timestamptz,
  current_ride_id uuid references ride_requests(id),
  updated_at timestamptz not null default now()
);

create index idx_driver_status_online on driver_status(is_online) where is_online = true;
create index idx_driver_status_location on driver_status using gist(current_location);

alter table driver_status enable row level security;

-- Provider can read/update their own status
create policy driver_status_own on driver_status for all
  using (provider_id in (
    select id from provider_profiles where user_id = auth.uid()
  )) with check (provider_id in (
    select id from provider_profiles where user_id = auth.uid()
  ));

-- Admin can read all
create policy driver_status_admin on driver_status for select
  using (is_admin());

-- =========================================================
-- 2. EXTEND RIDE_STATUS ENUM
-- =========================================================

-- Add missing statuses to the existing ride_status enum
ALTER TYPE ride_status ADD VALUE IF NOT EXISTS 'DRIVER_EN_ROUTE' AFTER 'DRIVER_ARRIVING';
ALTER TYPE ride_status ADD VALUE IF NOT EXISTS 'ARRIVED' AFTER 'DRIVER_EN_ROUTE';
ALTER TYPE ride_status ADD VALUE IF NOT EXISTS 'TRIP_STARTED' AFTER 'ARRIVED';

-- =========================================================
-- 3. EXTEND NOTIFICATION TYPES
-- =========================================================

ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'RIDE.NewRequest' AFTER 'RIDE_TAKEN';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'RIDE.Claimed' AFTER 'RIDE.NewRequest';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'RIDE.Cancelled' AFTER 'RIDE.Claimed';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'RIDE.DriverArriving' AFTER 'RIDE.Cancelled';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'RIDE.Arrived' AFTER 'RIDE.DriverArriving';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'RIDE.TripStarted' AFTER 'RIDE.Arrived';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'RIDE.TripCompleted' AFTER 'RIDE.TripStarted';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'RIDE.Rated' AFTER 'RIDE.TripCompleted';

-- =========================================================
-- 4. VEHICLE CATEGORY EXTENSIONS
-- =========================================================

-- Add vehicle_category_id to ride_requests if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'ride_requests' AND column_name = 'vehicle_category_id'
  ) THEN
    ALTER TABLE ride_requests ADD COLUMN vehicle_category_id uuid references categories(id);
  END IF;
END $$;

-- =========================================================
-- 5. FIND NEARBY ONLINE DRIVERS FUNCTION
-- =========================================================

create or replace function find_nearby_drivers(
  p_lat double precision,
  p_lng double precision,
  p_radius_km numeric default 10,
  p_vehicle_category_id uuid default null
) returns table (
  provider_id uuid,
  vehicle_id uuid,
  provider_name text,
  vehicle_brand text,
  vehicle_model text,
  vehicle_plate text,
  distance_km numeric,
  vehicle_category uuid
)
language plpgsql
security definer
stable
as $$
declare
  v_location geography(Point,4326);
begin
  v_location := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;

  return query
  select
    ds.provider_id,
    v.id as vehicle_id,
    coalesce(pp.business_name, pr.full_name) as provider_name,
    v.brand as vehicle_brand,
    v.model as vehicle_model,
    v.plate_number as vehicle_plate,
    round((st_distance(ds.current_location, v_location) / 1000.0)::numeric, 2) as distance_km,
    v.category_id as vehicle_category
  from driver_status ds
  join provider_profiles pp on pp.id = ds.provider_id and pp.status = 'APPROVED'
  join profiles pr on pr.id = pp.user_id
  join vehicles v on v.provider_id = ds.provider_id and v.is_available = true and v.status = 'APPROVED'
  where ds.is_online = true
    and ds.current_location is not null
    and ds.current_ride_id is null  -- not on an active ride
    and st_dwithin(ds.current_location, v_location, p_radius_km * 1000)
    and (p_vehicle_category_id is null or v.category_id = p_vehicle_category_id)
  order by st_distance(ds.current_location, v_location)
  limit 20;
end;
$$;

-- =========================================================
-- 6. UPDATE DRIVER LOCATION FUNCTION
-- =========================================================

create or replace function update_driver_location(
  p_provider_id uuid,
  p_lat double precision,
  p_lng double precision
) returns driver_status
language plpgsql
security definer
as $$
declare
  v_status driver_status;
begin
  -- Verify provider owns this driver_status
  if not exists (
    select 1 from provider_profiles
    where id = p_provider_id and user_id = auth.uid()
  ) then
    raise exception 'NOT_YOUR_DRIVER_STATUS';
  end if;

  insert into driver_status (provider_id, current_location, last_location_update, updated_at)
  values (p_provider_id, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, now(), now())
  on conflict (provider_id) do update set
    current_location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    last_location_update = now(),
    updated_at = now()
  returning * into v_status;

  return v_status;
end;
$$;

-- =========================================================
-- 7. SET DRIVER ONLINE/OFFLINE FUNCTION
-- =========================================================

create or replace function set_driver_online(
  p_provider_id uuid,
  p_online boolean,
  p_lat double precision default null,
  p_lng double precision default null
) returns driver_status
language plpgsql
security definer
as $$
declare
  v_status driver_status;
begin
  if not exists (
    select 1 from provider_profiles
    where id = p_provider_id and user_id = auth.uid() and status = 'APPROVED'
  ) then
    raise exception 'PROVIDER_NOT_APPROVED';
  end if;

  -- If going online, must have location
  if p_online and (p_lat is null or p_lng is null) then
    raise exception 'LOCATION_REQUIRED_TO_GO_ONLINE';
  end if;

  insert into driver_status (provider_id, is_online, current_location, last_location_update, updated_at)
  values (p_provider_id, p_online,
          case when p_online then st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography else null end,
          case when p_online then now() else null end,
          now())
  on conflict (provider_id) do update set
    is_online = p_online,
    current_location = case when p_online then st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography else driver_status.current_location end,
    last_location_update = case when p_online then now() else driver_status.last_location_update end,
    updated_at = now()
  returning * into v_status;

  return v_status;
end;
$$;

-- =========================================================
-- 8. CREATE RIDE REQUEST FUNCTION (USER SIDE)
-- =========================================================

create or replace function create_ride_request(
  p_user_id uuid,
  p_pickup_lat double precision,
  p_pickup_lng double precision,
  p_destination_lat double precision,
  p_destination_lng double precision,
  p_pickup_text text default null,
  p_destination_text text default null,
  p_vehicle_category_id uuid default null
) returns ride_requests
language plpgsql
security definer
as $$
declare
  v_ride ride_requests;
begin
  -- Verify the user creating the ride is the authenticated user
  if p_user_id != auth.uid() then
    raise exception 'CANNOT_CREATE_RIDE_FOR_ANOTHER_USER';
  end if;

  insert into ride_requests (
    user_id, pickup_location, destination_location,
    pickup_text, destination_text, vehicle_category_id, status
  ) values (
    p_user_id,
    st_setsrid(st_makepoint(p_pickup_lng, p_pickup_lat), 4326)::geography,
    st_setsrid(st_makepoint(p_destination_lng, p_destination_lat), 4326)::geography,
    p_pickup_text, p_destination_text, p_vehicle_category_id,
    'REQUESTED'
  ) returning * into v_ride;

  insert into ride_status_history (ride_request_id, from_status, to_status, changed_by)
  values (v_ride.id, null, 'REQUESTED', p_user_id);

  return v_ride;
end;
$$;

-- =========================================================
-- 9. CREATE RATINGS TABLE
-- =========================================================

create table if not exists ride_ratings (
  id uuid primary key default uuid_generate_v4(),
  ride_request_id uuid not null references ride_requests(id) on delete cascade,
  rater_id uuid not null references auth.users(id),
  ratee_provider_id uuid references provider_profiles(id),
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (ride_request_id, rater_id)
);

create index idx_ride_ratings_ride on ride_ratings(ride_request_id);
create index idx_ride_ratings_provider on ride_ratings(ratee_provider_id);

alter table ride_ratings enable row level security;

create policy ride_ratings_insert_own on ride_ratings for insert
  with check (rater_id = auth.uid());
create policy ride_ratings_read on ride_ratings for select
  using (true);
create policy ride_ratings_admin on ride_ratings for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- 10. TRIGGER: AUTO-CREATE DRIVER_STATUS ON PROVIDER APPROVAL
-- =========================================================

create or replace function auto_create_driver_status()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.status = 'APPROVED' and new.provider_type = 'VEHICLE_PROVIDER' then
    insert into driver_status (provider_id, is_online)
    values (new.id, false)
    on conflict (provider_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger trg_provider_profiles_driver_status
  after update on provider_profiles
  for each row
  execute function auto_create_driver_status();

-- Also on insert for already-approved providers
create or replace function auto_create_driver_status_insert()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.status = 'APPROVED' and new.provider_type = 'VEHICLE_PROVIDER' then
    insert into driver_status (provider_id, is_online)
    values (new.id, false)
    on conflict (provider_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger trg_provider_profiles_driver_status_insert
  after insert on provider_profiles
  for each row
  execute function auto_create_driver_status_insert();

-- =========================================================
-- 11. INDEXES FOR PERFORMANCE
-- =========================================================

CREATE INDEX IF NOT EXISTS idx_ride_requests_user_status
  ON ride_requests(user_id, status);
CREATE INDEX IF NOT EXISTS idx_ride_requests_provider_status
  ON ride_requests(claimed_by_provider_id, status);
CREATE INDEX IF NOT EXISTS idx_driver_status_provider
  ON driver_status(provider_id);
