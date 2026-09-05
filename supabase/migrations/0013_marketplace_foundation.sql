-- 5BIRR Milestone 8 — Phase 1: Marketplace Foundation
-- Migration 0013_marketplace_foundation.sql
-- Adds reusable marketplace architecture: categories, provider stores,
-- unified listings, listing images, provider gallery.
-- ALL changes are additive; no existing data is modified.

-- =========================================================
-- 1. NEW ENUMS
-- =========================================================

CREATE TYPE listing_type AS ENUM ('PRODUCT', 'FOOD', 'SERVICE', 'ROOM', 'OTHER');
CREATE TYPE listing_status AS ENUM ('ACTIVE', 'DRAFT', 'SOLD_OUT', 'ARCHIVED');

-- =========================================================
-- 2. EXTEND CATEGORIES TABLE
--    Add marketplace-specific fields for dynamic admin-managed categories.
-- =========================================================

ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS marketplace_sector text
    CHECK (marketplace_sector IN ('FOOD','RETAIL','ACCOMMODATION','SERVICES','TRANSPORT','OTHER')),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Add updated_at trigger for categories
CREATE TRIGGER trg_categories_updated
  BEFORE UPDATE ON categories
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();

-- =========================================================
-- 3. EXTEND PRODUCTS TABLE (Unified Listing Model)
--    Adds listing_type, stock management, status, and flexible metadata.
--    Existing products default to listing_type='PRODUCT', status='ACTIVE'.
-- =========================================================

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS listing_type listing_type NOT NULL DEFAULT 'PRODUCT',
  ADD COLUMN IF NOT EXISTS stock_quantity int,
  ADD COLUMN IF NOT EXISTS low_stock_threshold int DEFAULT 5,
  ADD COLUMN IF NOT EXISTS listing_status listing_status NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN IF NOT EXISTS metadata jsonb;

-- Backfill: set stock_quantity from existing quantity column where available
UPDATE products SET stock_quantity = quantity WHERE stock_quantity IS NULL AND quantity IS NOT NULL;

-- =========================================================
-- 4. PROVIDER STORES
--    Public marketplace store profile for approved providers.
--    Only approved + active providers appear publicly.
--    Suspended/rejected providers must not appear as active stores.
-- =========================================================

CREATE TABLE provider_stores (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id uuid NOT NULL UNIQUE REFERENCES provider_profiles(id) ON DELETE CASCADE,
  business_name text NOT NULL,
  description text,
  category_id uuid REFERENCES categories(id),
  location geography(Point,4326),
  address_text text,
  contact_phone text,
  contact_email text,
  website_url text,
  logo_storage_path text,
  cover_image_storage_path text,
  rating numeric(3,2) NOT NULL DEFAULT 0 CHECK (rating >= 0 AND rating <= 5),
  review_count int NOT NULL DEFAULT 0,
  listing_count int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_provider_stores_provider ON provider_stores(provider_id);
CREATE INDEX idx_provider_stores_category ON provider_stores(category_id);
CREATE INDEX idx_provider_stores_active ON provider_stores(is_active) WHERE is_active = true;
CREATE INDEX idx_provider_stores_location ON provider_stores USING gist(location);
CREATE INDEX idx_provider_stores_rating ON provider_stores(rating DESC);

-- Trigger for updated_at
CREATE TRIGGER trg_provider_stores_updated
  BEFORE UPDATE ON provider_stores
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();

-- =========================================================
-- 5. LISTING IMAGES
--    Unified image management for all listing types.
--    Supports multiple images, primary image, display order.
--    Provider can ONLY manage images for their own listings.
--    No national IDs, driving licenses, or payment evidence here.
-- =========================================================

CREATE TABLE listing_images (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  listing_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  alt_text text,
  is_primary boolean NOT NULL DEFAULT false,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_listing_images_listing ON listing_images(listing_id);
CREATE INDEX idx_listing_images_primary ON listing_images(listing_id) WHERE is_primary = true;
CREATE INDEX idx_listing_images_sort ON listing_images(listing_id, sort_order);

-- =========================================================
-- 6. PROVIDER GALLERY
--    Provider-level gallery images (not tied to specific listings).
--    Provider manages only their own gallery. Admin can moderate.
-- =========================================================

CREATE TABLE provider_gallery (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id uuid NOT NULL REFERENCES provider_profiles(id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  caption text,
  display_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_provider_gallery_provider ON provider_gallery(provider_id);
CREATE INDEX idx_provider_gallery_active ON provider_gallery(provider_id, is_active) WHERE is_active = true;
CREATE INDEX idx_provider_gallery_order ON provider_gallery(provider_id, display_order);

-- Trigger for updated_at
CREATE TRIGGER trg_provider_gallery_updated
  BEFORE UPDATE ON provider_gallery
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();

-- =========================================================
-- 7. ENABLE RLS ON ALL NEW TABLES
-- =========================================================

ALTER TABLE provider_stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE listing_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_gallery ENABLE ROW LEVEL SECURITY;
