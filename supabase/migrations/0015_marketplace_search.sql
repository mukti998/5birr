-- 5BIRR Milestone 8 — Phase 1: Marketplace Search & Performance
-- Migration 0015_marketplace_search.sql
-- Server-side marketplace search, listing management functions,
-- and performance indexes for the marketplace.

-- =========================================================
-- 1. MARKETPLACE SEARCH FUNCTION
--    Unified search across listings by name, category, type,
--    provider, location. Supports pagination, filtering, sorting.
--    The database is authoritative for all price data.
-- =========================================================

CREATE OR REPLACE FUNCTION search_marketplace(
  p_query text DEFAULT NULL,
  p_listing_type listing_type DEFAULT NULL,
  p_category_id uuid DEFAULT NULL,
  p_marketplace_sector text DEFAULT NULL,
  p_provider_id uuid DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_radius_km numeric DEFAULT NULL,
  p_min_price numeric DEFAULT NULL,
  p_max_price numeric DEFAULT NULL,
  p_min_rating numeric DEFAULT NULL,
  p_in_stock_only boolean DEFAULT true,
  p_sort_by text DEFAULT 'relevance', -- relevance|price_asc|price_desc|rating|distance|newest
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  name text,
  description text,
  price numeric,
  currency text,
  listing_type listing_type,
  listing_status listing_status,
  stock_quantity int,
  rating numeric,
  review_count int,
  sales_count int,
  category_id uuid,
  category_name text,
  marketplace_sector text,
  provider_id uuid,
  provider_name text,
  store_id uuid,
  distance_km numeric,
  is_available boolean,
  image_path text,
  metadata jsonb,
  created_at timestamptz,
  rank_score numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_location geography(Point,4326);
BEGIN
  -- Build location point if coordinates provided
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    v_location := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.name,
    p.description,
    p.price,
    p.currency,
    p.listing_type,
    p.listing_status,
    p.stock_quantity,
    p.rating,
    p.review_count,
    p.sales_count,
    p.category_id,
    c.name AS category_name,
    c.marketplace_sector,
    p.provider_id,
    COALESCE(pp.business_name, pr.full_name) AS provider_name,
    ps.id AS store_id,
    CASE WHEN v_location IS NOT NULL AND p.location IS NOT NULL
      THEN ROUND((ST_Distance(p.location, v_location) / 1000.0)::numeric, 2)
      ELSE NULL
    END AS distance_km,
    p.is_available,
    -- Get primary listing image, fallback to first image
    COALESCE(
      (SELECT li.storage_path FROM listing_images li
       WHERE li.listing_id = p.id AND li.is_primary = true LIMIT 1),
      (SELECT li.storage_path FROM listing_images li
       WHERE li.listing_id = p.id ORDER BY li.sort_order LIMIT 1),
      (SELECT pi.storage_path FROM product_images pi
       WHERE pi.product_id = p.id ORDER BY pi.sort_order LIMIT 1)
    ) AS image_path,
    p.metadata,
    p.created_at,
    CASE
      WHEN p_query IS NOT NULL AND p_query != ''
      THEN TS_Rank(p.search_vector, plainto_tsquery('simple', p_query))
           + (1.0 / (1.0 + COALESCE(
             CASE WHEN v_location IS NOT NULL AND p.location IS NOT NULL
               THEN ST_Distance(p.location, v_location) / 1000.0
               ELSE 9999 END, 9999)))
      ELSE 0
    END AS rank_score
  FROM products p
  JOIN provider_profiles pp ON pp.id = p.provider_id AND pp.status = 'APPROVED'
  JOIN profiles pr ON pr.id = pp.user_id
  LEFT JOIN provider_stores ps ON ps.provider_id = p.provider_id AND ps.is_active = true
  LEFT JOIN categories c ON c.id = p.category_id
  WHERE p.listing_status = 'ACTIVE'
    AND p.is_active = true
    -- Full-text search
    AND (p_query IS NULL OR p_query = ''
         OR p.search_vector @@ plainto_tsquery('simple', p_query)
         OR p.name ILIKE '%' || p_query || '%')
    -- Listing type filter
    AND (p_listing_type IS NULL OR p.listing_type = p_listing_type)
    -- Category filter
    AND (p_category_id IS NULL OR p.category_id = p_category_id)
    -- Marketplace sector filter
    AND (p_marketplace_sector IS NULL OR c.marketplace_sector = p_marketplace_sector)
    -- Provider filter
    AND (p_provider_id IS NULL OR p.provider_id = p_provider_id)
    -- Geo filter
    AND (v_location IS NULL OR p.location IS NULL
         OR ST_DWithin(p.location, v_location, p_radius_km * 1000))
    -- Price filters
    AND (p_min_price IS NULL OR p.price >= p_min_price)
    AND (p_max_price IS NULL OR p.price <= p_max_price)
    -- Rating filter
    AND (p_min_rating IS NULL OR p.rating >= p_min_rating)
    -- Stock filter
    AND (p_in_stock_only = false OR p.stock_quantity IS NULL OR p.stock_quantity > 0)
  ORDER BY
    CASE p_sort_by
      WHEN 'price_asc' THEN p.price
      ELSE NULL
    END ASC,
    CASE p_sort_by
      WHEN 'price_desc' THEN p.price
      ELSE NULL
    END DESC,
    CASE p_sort_by
      WHEN 'rating' THEN p.rating
      ELSE NULL
    END DESC NULLS LAST,
    CASE p_sort_by
      WHEN 'newest' THEN p.created_at
      ELSE NULL
    END DESC NULLS LAST,
    CASE p_sort_by
      WHEN 'relevance' THEN
        CASE
          WHEN p_query IS NOT NULL AND p_query != ''
          THEN TS_Rank(p.search_vector, plainto_tsquery('simple', p_query))
               + (1.0 / (1.0 + COALESCE(
                 CASE WHEN v_location IS NOT NULL AND p.location IS NOT NULL
                   THEN ST_Distance(p.location, v_location) / 1000.0
                   ELSE 9999 END, 9999)))
          ELSE 0
        END
      ELSE NULL
    END DESC NULLS LAST,
    CASE p_sort_by
      WHEN 'distance' THEN
        CASE WHEN v_location IS NOT NULL AND p.location IS NOT NULL
          THEN ST_Distance(p.location, v_location)
          ELSE 999999999 END
      ELSE NULL
    END ASC NULLS LAST
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- =========================================================
-- 2. MARKETPLACE STORE SEARCH
--    Search provider stores by name, category, sector, location.
-- =========================================================

CREATE OR REPLACE FUNCTION search_marketplace_stores(
  p_query text DEFAULT NULL,
  p_marketplace_sector text DEFAULT NULL,
  p_category_id uuid DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_radius_km numeric DEFAULT NULL,
  p_min_rating numeric DEFAULT NULL,
  p_sort_by text DEFAULT 'relevance', -- relevance|rating|distance|newest
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  provider_id uuid,
  business_name text,
  description text,
  category_id uuid,
  category_name text,
  marketplace_sector text,
  address_text text,
  contact_phone text,
  contact_email text,
  logo_storage_path text,
  cover_image_storage_path text,
  rating numeric,
  review_count int,
  listing_count int,
  distance_km numeric,
  created_at timestamptz,
  rank_score numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_location geography(Point,4326);
BEGIN
  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    v_location := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;
  END IF;

  RETURN QUERY
  SELECT
    ps.id,
    ps.provider_id,
    ps.business_name,
    ps.description,
    ps.category_id,
    c.name AS category_name,
    c.marketplace_sector,
    ps.address_text,
    ps.contact_phone,
    ps.contact_email,
    ps.logo_storage_path,
    ps.cover_image_storage_path,
    ps.rating,
    ps.review_count,
    ps.listing_count,
    CASE WHEN v_location IS NOT NULL AND ps.location IS NOT NULL
      THEN ROUND((ST_Distance(ps.location, v_location) / 1000.0)::numeric, 2)
      ELSE NULL
    END AS distance_km,
    ps.created_at,
    CASE
      WHEN p_query IS NOT NULL AND p_query != ''
      THEN TS_RANK(
        to_tsvector('simple', coalesce(ps.business_name, '') || ' ' || coalesce(ps.description, '')),
        plainto_tsquery('simple', p_query)
      )
      ELSE 0
    END AS rank_score
  FROM provider_stores ps
  JOIN provider_profiles pp ON pp.id = ps.provider_id AND pp.status = 'APPROVED'
  LEFT JOIN categories c ON c.id = ps.category_id
  WHERE ps.is_active = true
    AND (p_query IS NULL OR p_query = ''
         OR ps.business_name ILIKE '%' || p_query || '%'
         OR ps.description ILIKE '%' || p_query || '%')
    AND (p_marketplace_sector IS NULL OR c.marketplace_sector = p_marketplace_sector)
    AND (p_category_id IS NULL OR ps.category_id = p_category_id)
    AND (v_location IS NULL OR ps.location IS NULL
         OR ST_DWithin(ps.location, v_location, p_radius_km * 1000))
    AND (p_min_rating IS NULL OR ps.rating >= p_min_rating)
  ORDER BY
    CASE p_sort_by
      WHEN 'rating' THEN ps.rating
      ELSE NULL
    END DESC NULLS LAST,
    CASE p_sort_by
      WHEN 'distance' THEN
        CASE WHEN v_location IS NOT NULL AND ps.location IS NOT NULL
          THEN ST_Distance(ps.location, v_location)
          ELSE 999999999 END
      ELSE NULL
    END ASC NULLS LAST,
    CASE p_sort_by
      WHEN 'newest' THEN ps.created_at
      ELSE NULL
    END DESC NULLS LAST,
    CASE p_sort_by
      WHEN 'relevance' THEN
        CASE
          WHEN p_query IS NOT NULL AND p_query != ''
          THEN TS_RANK(
            to_tsvector('simple', coalesce(ps.business_name, '') || ' ' || coalesce(ps.description, '')),
            plainto_tsquery('simple', p_query)
          )
          ELSE 0
        END
      ELSE NULL
    END DESC NULLS LAST
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- =========================================================
-- 3. GET MARKETPLACE CATEGORIES
--    Returns categories with subcategories for marketplace navigation.
-- =========================================================

CREATE OR REPLACE FUNCTION get_marketplace_categories(
  p_marketplace_sector text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  parent_id uuid,
  name text,
  description text,
  slug text,
  icon text,
  image_url text,
  marketplace_sector text,
  sort_order int,
  subcategory_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.parent_id,
    c.name,
    c.description,
    c.slug,
    c.icon,
    c.image_url,
    c.marketplace_sector,
    c.sort_order,
    (SELECT COUNT(*) FROM categories sub WHERE sub.parent_id = c.id AND sub.is_active = true)
  FROM categories c
  WHERE c.is_active = true
    AND c.parent_id IS NULL  -- top-level only
    AND (p_marketplace_sector IS NULL OR c.marketplace_sector = p_marketplace_sector)
  ORDER BY c.sort_order;
END;
$$;

-- =========================================================
-- 4. GET LISTING DETAILS
--    Returns a single listing with images, provider store info.
--    Price is always fetched from the database (authoritative).
-- =========================================================

CREATE OR REPLACE FUNCTION get_listing_detail(
  p_listing_id uuid
)
RETURNS TABLE (
  id uuid,
  name text,
  description text,
  price numeric,
  currency text,
  listing_type listing_type,
  listing_status listing_status,
  stock_quantity int,
  low_stock_threshold int,
  is_available boolean,
  rating numeric,
  review_count int,
  sales_count int,
  category_id uuid,
  category_name text,
  marketplace_sector text,
  provider_id uuid,
  provider_name text,
  store_id uuid,
  store_business_name text,
  metadata jsonb,
  location_lat double precision,
  location_lng double precision,
  created_at timestamptz,
  updated_at timestamptz,
  images jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.name,
    p.description,
    p.price,
    p.currency,
    p.listing_type,
    p.listing_status,
    p.stock_quantity,
    p.low_stock_threshold,
    p.is_available,
    p.rating,
    p.review_count,
    p.sales_count,
    p.category_id,
    c.name AS category_name,
    c.marketplace_sector,
    p.provider_id,
    COALESCE(pp.business_name, pr.full_name) AS provider_name,
    ps.id AS store_id,
    ps.business_name AS store_business_name,
    p.metadata,
    CASE WHEN p.location IS NOT NULL THEN ST_Y(p.location::geometry) ELSE NULL END AS location_lat,
    CASE WHEN p.location IS NOT NULL THEN ST_X(p.location::geometry) ELSE NULL END AS location_lng,
    p.created_at,
    p.updated_at,
    -- Combine listing_images and legacy product_images
    (
      SELECT COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'id', li.id,
              'storage_path', li.storage_path,
              'alt_text', li.alt_text,
              'is_primary', li.is_primary,
              'sort_order', li.sort_order
            ) ORDER BY li.sort_order
          )
          FROM listing_images li
          WHERE li.listing_id = p.id
        ),
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'id', pi.id,
              'storage_path', pi.storage_path,
              'alt_text', NULL,
              'is_primary', (pi.sort_order = 0),
              'sort_order', pi.sort_order
            ) ORDER BY pi.sort_order
          )
          FROM product_images pi
          WHERE pi.product_id = p.id
        ),
        '[]'::jsonb
      )
    ) AS images
  FROM products p
  JOIN provider_profiles pp ON pp.id = p.provider_id
  JOIN profiles pr ON pr.id = pp.user_id
  LEFT JOIN provider_stores ps ON ps.provider_id = p.provider_id AND ps.is_active = true
  LEFT JOIN categories c ON c.id = p.category_id
  WHERE p.id = p_listing_id
    AND p.is_active = true
    AND (
      p.listing_status = 'ACTIVE'
      OR pp.user_id = auth.uid()
      OR is_admin()
    );
END;
$$;

-- =========================================================
-- 5. GET PROVIDER STORE DETAIL
--    Returns store profile with listing counts and gallery.
-- =========================================================

CREATE OR REPLACE FUNCTION get_provider_store_detail(
  p_store_id uuid DEFAULT NULL,
  p_provider_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  provider_id uuid,
  business_name text,
  description text,
  category_id uuid,
  category_name text,
  marketplace_sector text,
  address_text text,
  contact_phone text,
  contact_email text,
  website_url text,
  logo_storage_path text,
  cover_image_storage_path text,
  rating numeric,
  review_count int,
  listing_count int,
  metadata jsonb,
  created_at timestamptz,
  gallery jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ps.id,
    ps.provider_id,
    ps.business_name,
    ps.description,
    ps.category_id,
    c.name AS category_name,
    c.marketplace_sector,
    ps.address_text,
    ps.contact_phone,
    ps.contact_email,
    ps.website_url,
    ps.logo_storage_path,
    ps.cover_image_storage_path,
    ps.rating,
    ps.review_count,
    ps.listing_count,
    ps.metadata,
    ps.created_at,
    (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', pg.id,
            'storage_path', pg.storage_path,
            'caption', pg.caption,
            'display_order', pg.display_order
          ) ORDER BY pg.display_order
        ),
        '[]'::jsonb
      )
      FROM provider_gallery pg
      WHERE pg.provider_id = ps.provider_id AND pg.is_active = true
    ) AS gallery
  FROM provider_stores ps
  LEFT JOIN categories c ON c.id = ps.category_id
  WHERE ps.is_active = true
    AND (
      (p_store_id IS NOT NULL AND ps.id = p_store_id)
      OR (p_provider_id IS NOT NULL AND ps.provider_id = p_provider_id)
    )
    AND (
      EXISTS (
        SELECT 1 FROM provider_profiles pp
        WHERE pp.id = ps.provider_id AND pp.status = 'APPROVED'
      )
      OR ps.provider_id IN (
        SELECT pp2.id FROM provider_profiles pp2
        WHERE pp2.user_id = auth.uid()
      )
      OR is_admin()
    );
END;
$$;

-- =========================================================
-- 6. GET CATEGORIES WITH LISTING COUNTS
-- =========================================================

CREATE OR REPLACE FUNCTION get_categories_with_counts()
RETURNS TABLE (
  id uuid,
  parent_id uuid,
  name text,
  description text,
  slug text,
  icon text,
  marketplace_sector text,
  sort_order int,
  active_listing_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.parent_id,
    c.name,
    c.description,
    c.slug,
    c.icon,
    c.marketplace_sector,
    c.sort_order,
    COUNT(p.id) AS active_listing_count
  FROM categories c
  LEFT JOIN products p ON p.category_id = c.id
    AND p.is_active = true
    AND p.listing_status = 'ACTIVE'
  WHERE c.is_active = true
  GROUP BY c.id, c.parent_id, c.name, c.description, c.slug,
           c.icon, c.marketplace_sector, c.sort_order
  ORDER BY c.sort_order;
END;
$$;

-- =========================================================
-- 7. AUTO-SYNC PROVIDER STORE LISTING COUNT
-- =========================================================

CREATE OR REPLACE FUNCTION sync_store_listing_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update listing count on the provider store when a listing is created/deleted
  IF TG_OP = 'INSERT' THEN
    UPDATE provider_stores
    SET listing_count = (
      SELECT COUNT(*) FROM products
      WHERE provider_id = NEW.provider_id
        AND is_active = true
        AND listing_status = 'ACTIVE'
    )
    WHERE provider_id = NEW.provider_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE provider_stores
    SET listing_count = (
      SELECT COUNT(*) FROM products
      WHERE provider_id = OLD.provider_id
        AND is_active = true
        AND listing_status = 'ACTIVE'
    )
    WHERE provider_id = OLD.provider_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_products_sync_store_count
  AFTER INSERT OR DELETE ON products
  FOR EACH ROW
  EXECUTE FUNCTION sync_store_listing_count();

-- Also sync on listing_status changes
CREATE OR REPLACE FUNCTION sync_store_listing_count_on_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.listing_status IS DISTINCT FROM OLD.listing_status THEN
    UPDATE provider_stores
    SET listing_count = (
      SELECT COUNT(*) FROM products
      WHERE provider_id = NEW.provider_id
        AND is_active = true
        AND listing_status = 'ACTIVE'
    )
    WHERE provider_id = NEW.provider_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_sync_store_count_status
  AFTER UPDATE ON products
  FOR EACH ROW
  WHEN (NEW.listing_status IS DISTINCT FROM OLD.listing_status)
  EXECUTE FUNCTION sync_store_listing_count_on_status();

-- =========================================================
-- 8. MARKETPLACE PERFORMANCE INDEXES
-- =========================================================

-- Listing type and status indexes
CREATE INDEX IF NOT EXISTS idx_products_listing_type
  ON products(listing_type);
CREATE INDEX IF NOT EXISTS idx_products_listing_status
  ON products(listing_status);
CREATE INDEX IF NOT EXISTS idx_products_type_status
  ON products(listing_type, listing_status);

-- Composite index for marketplace queries (active listings by provider)
CREATE INDEX IF NOT EXISTS idx_products_provider_status_active
  ON products(provider_id, listing_status)
  WHERE listing_status = 'ACTIVE' AND is_active = true;

-- Category + status composite
CREATE INDEX IF NOT EXISTS idx_products_category_status
  ON products(category_id, listing_status)
  WHERE listing_status = 'ACTIVE';

-- Listing status + created_at for sort-by-newest
CREATE INDEX IF NOT EXISTS idx_products_status_created
  ON products(listing_status, created_at DESC)
  WHERE listing_status = 'ACTIVE';

-- Price index for range queries
CREATE INDEX IF NOT EXISTS idx_products_price
  ON products(price)
  WHERE listing_status = 'ACTIVE' AND is_active = true;

-- Metadata GIN index for flexible queries
CREATE INDEX IF NOT EXISTS idx_products_metadata
  ON products USING gin(metadata)
  WHERE metadata IS NOT NULL;

-- Marketplace sector index on categories
CREATE INDEX IF NOT EXISTS idx_categories_marketplace_sector
  ON categories(marketplace_sector)
  WHERE marketplace_sector IS NOT NULL;

-- Provider stores composite indexes
CREATE INDEX IF NOT EXISTS idx_provider_stores_sector_active
  ON provider_stores(is_active)
  WHERE is_active = true;
