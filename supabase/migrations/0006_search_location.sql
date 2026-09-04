-- 5BIRR Phase 2 — Search & Location Foundation
-- Migration 0006_search_location.sql
-- Server-side search RPC, nearby providers, and location helpers.

-- =========================================================
-- 1. FULL-TEXT + GEO SEARCH FOR PRODUCTS
-- =========================================================

create or replace function search_products(
  p_query text default null,
  p_category_id uuid default null,
  p_sector text default null, -- 'SERVICE' or null for all
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_km numeric default null,
  p_min_price numeric default null,
  p_max_price numeric default null,
  p_min_rating numeric default null,
  p_sort_by text default 'relevance', -- relevance|price_asc|price_desc|rating|distance|newest
  p_limit int default 20,
  p_offset int default 0
) returns table (
  id uuid,
  name text,
  description text,
  price numeric,
  currency text,
  rating numeric,
  review_count int,
  sales_count int,
  category_id uuid,
  provider_id uuid,
  provider_name text,
  distance_km numeric,
  is_available boolean,
  image_path text,
  rank_score numeric
)
language plpgsql
security definer
stable
as $$
declare
  v_location geography(Point,4326);
begin
  -- Build location point if coordinates provided
  if p_lat is not null and p_lng is not null then
    v_location := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  end if;

  return query
  select
    p.id,
    p.name,
    p.description,
    p.price,
    p.currency,
    p.rating,
    p.review_count,
    p.sales_count,
    p.category_id,
    p.provider_id,
    pp.business_name as provider_name,
    case when v_location is not null and p.location is not null
      then round((st_distance(p.location, v_location) / 1000.0)::numeric, 2)
      else null
    end as distance_km,
    p.is_available,
    (select pi.storage_path from product_images pi
     where pi.product_id = p.id order by pi.sort_order limit 1) as image_path,
    case
      when p_query is not null and p_query != ''
      then ts_rank(p.search_vector, plainto_tsquery('simple', p_query))
           + (1.0 / (1.0 + coalesce(
             case when v_location is not null and p.location is not null
               then st_distance(p.location, v_location) / 1000.0
               else 9999 end, 9999)))
      else 0
    end as rank_score
  from products p
  join provider_profiles pp on pp.id = p.provider_id and pp.status = 'APPROVED'
  where p.is_active = true
    and p.is_available = true
    and (p_query is null or p_query = '' or p.search_vector @@ plainto_tsquery('simple', p_query))
    and (p_category_id is null or p.category_id = p_category_id)
    and (p_sector is null or exists (
      select 1 from categories c where c.id = p.category_id and c.sector = p_sector
    ))
    and (v_location is null or p.location is null
         or st_dwithin(p.location, v_location, p_radius_km * 1000))
    and (p_min_price is null or p.price >= p_min_price)
    and (p_max_price is null or p.price <= p_max_price)
    and (p_min_rating is null or p.rating >= p_min_rating)
  order by
    case p_sort_by
      when 'price_asc' then p.price
      else null
    end asc,
    case p_sort_by
      when 'price_desc' then p.price
      else null
    end desc,
    case p_sort_by
      when 'rating' then p.rating
      else null
    end desc nulls last,
    case p_sort_by
      when 'newest' then p.created_at
      else null
    end desc nulls last,
    case p_sort_by
      when 'relevance' then
        case
          when p_query is not null and p_query != ''
          then ts_rank(p.search_vector, plainto_tsquery('simple', p_query))
               + (1.0 / (1.0 + coalesce(
                 case when v_location is not null and p.location is not null
                   then st_distance(p.location, v_location) / 1000.0
                   else 9999 end, 9999)))
          else 0
        end
      else null
    end desc nulls last,
    case p_sort_by
      when 'distance' then
        case when v_location is not null and p.location is not null
          then st_distance(p.location, v_location)
          else 999999999 end
      else null
    end asc nulls last
  limit p_limit
  offset p_offset;
end;
$$;

-- =========================================================
-- 2. NEARBY PROVIDERS
-- =========================================================

create or replace function get_nearby_providers(
  p_lat double precision,
  p_lng double precision,
  p_radius_km numeric default 5,
  p_provider_type app_role default null,
  p_category_id uuid default null,
  p_limit int default 20
) returns table (
  id uuid,
  user_id uuid,
  provider_type app_role,
  business_name text,
  status account_status,
  rating numeric,
  distance_km numeric,
  service_area_radius_km numeric,
  category_id uuid,
  category_name text
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
    pp.id,
    pp.user_id,
    pp.provider_type,
    pp.business_name,
    pp.status,
    0::numeric as rating,
    round((st_distance(pp.location, v_location) / 1000.0)::numeric, 2) as distance_km,
    pp.service_area_radius_km,
    pp.category_id,
    c.name as category_name
  from provider_profiles pp
  left join categories c on c.id = pp.category_id
  where pp.status = 'APPROVED'
    and pp.location is not null
    and st_dwithin(pp.location, v_location, p_radius_km * 1000)
    and (p_provider_type is null or pp.provider_type = p_provider_type)
    and (p_category_id is null or pp.category_id = p_category_id)
  order by st_distance(pp.location, v_location)
  limit p_limit;
end;
$$;

-- =========================================================
-- 3. NEARBY RIDE PROVIDERS (for ride request matching)
-- =========================================================

create or replace function get_nearby_ride_providers(
  p_lat double precision,
  p_lng double precision,
  p_radius_km numeric default 5,
  p_vehicle_category_id uuid default null,
  p_limit int default 10
) returns table (
  provider_id uuid,
  vehicle_id uuid,
  provider_name text,
  plate_number text,
  vehicle_brand text,
  vehicle_model text,
  distance_km numeric,
  rating numeric
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
    v.provider_id,
    v.id as vehicle_id,
    pp.business_name as provider_name,
    v.plate_number,
    v.brand as vehicle_brand,
    v.model as vehicle_model,
    round((st_distance(v.current_location, v_location) / 1000.0)::numeric, 2) as distance_km,
    v.rating
  from vehicles v
  join provider_profiles pp on pp.id = v.provider_id and pp.status = 'APPROVED'
  where v.is_available = true
    and v.status = 'APPROVED'
    and v.current_location is not null
    and st_dwithin(v.current_location, v_location, p_radius_km * 1000)
    and (p_vehicle_category_id is null or v.category_id = p_vehicle_category_id)
  order by st_distance(v.current_location, v_location)
  limit p_limit;
end;
$$;

-- =========================================================
-- 4. SEARCH PROVIDERS / SERVICES
-- =========================================================

create or replace function search_providers(
  p_query text default null,
  p_provider_type app_role default null,
  p_category_id uuid default null,
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_km numeric default null,
  p_limit int default 20,
  p_offset int default 0
) returns table (
  id uuid,
  user_id uuid,
  provider_type app_role,
  business_name text,
  owner_national_id text,
  status account_status,
  category_id uuid,
  category_name text,
  distance_km numeric,
  address_text text,
  created_at timestamptz
)
language plpgsql
security definer
stable
as $$
declare
  v_location geography(Point,4326);
begin
  if p_lat is not null and p_lng is not null then
    v_location := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  end if;

  return query
  select
    pp.id,
    pp.user_id,
    pp.provider_type,
    pp.business_name,
    pp.owner_national_id,
    pp.status,
    pp.category_id,
    c.name as category_name,
    case when v_location is not null and pp.location is not null
      then round((st_distance(pp.location, v_location) / 1000.0)::numeric, 2)
      else null
    end as distance_km,
    pp.address_text,
    pp.created_at
  from provider_profiles pp
  left join categories c on c.id = pp.category_id
  where pp.status = 'APPROVED'
    and (p_query is null or p_query = ''
         or pp.business_name ilike '%' || p_query || '%'
         or pp.address_text ilike '%' || p_query || '%')
    and (p_provider_type is null or pp.provider_type = p_provider_type)
    and (p_category_id is null or pp.category_id = p_category_id)
    and (v_location is null or pp.location is null
         or st_dwithin(pp.location, v_location, p_radius_km * 1000))
  order by
    case when v_location is not null and pp.location is not null
      then st_distance(pp.location, v_location)
      else 999999999 end
  limit p_limit
  offset p_offset;
end;
$$;

-- =========================================================
-- 5. DELIVERY ZONE CHECK
-- =========================================================

create or replace function check_delivery_zone(
  p_provider_id uuid,
  p_lat double precision,
  p_lng double precision
) returns boolean
language plpgsql
security definer
stable
as $$
declare
  v_provider provider_profiles;
  v_point geography(Point,4326);
begin
  select * into v_provider from provider_profiles where id = p_provider_id;
  if v_provider is null or v_provider.location is null then
    return false;
  end if;

  v_point := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  return st_dwithin(v_provider.location, v_point, v_provider.service_area_radius_km * 1000);
end;
$$;

-- =========================================================
-- 6. UPDATE VEHICLE LOCATION
--     Vehicle providers can update their own vehicle's location.
-- =========================================================

create or replace function update_vehicle_location(
  p_vehicle_id uuid,
  p_lat double precision,
  p_lng double precision
) returns vehicles
language plpgsql
security definer
as $$
declare
  v_vehicle vehicles;
begin
  -- Verify ownership
  if not exists (
    select 1 from vehicles v
    where v.id = p_vehicle_id and owns_provider_profile(v.provider_id)
  ) then
    raise exception 'VEHICLE_NOT_OWNED_BY_PROVIDER';
  end if;

  update vehicles
  set current_location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
  where id = p_vehicle_id
  returning * into v_vehicle;

  return v_vehicle;
end;
$$;

-- =========================================================
-- 7. INDEXES FOR SEARCH PERFORMANCE
-- =========================================================

-- Full-text search index for providers
create index idx_provider_profiles_business_name_trgm
  on provider_profiles using gin(business_name gin_trgm_ops);

-- Index for search_products provider name lookup
create index idx_provider_profiles_business_name
  on provider_profiles(business_name);
