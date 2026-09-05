-- 5BIRR Milestone 8 — Phase 1: Marketplace RLS Policies
-- Migration 0014_marketplace_rls.sql
-- Row-level security for provider_stores, listing_images, provider_gallery.
-- Follows existing patterns: public read for active data, strict ownership
-- enforcement for writes, admin override for moderation.

-- =========================================================
-- 1. CATEGORIES RLS EXTENSION
--    Allow authenticated users to manage marketplace_sector and description
--    via admin-only policies (already exists: categories_admin_write).
--    No new policies needed — existing admin_write covers the new columns.
-- =========================================================

-- =========================================================
-- 2. PROVIDER STORES
--    Public read for active stores (approved providers only).
--    Provider owns their store. Admin manages all.
-- =========================================================

-- Public can read active stores
CREATE POLICY provider_stores_public_read ON provider_stores FOR SELECT
  USING (
    is_active = true
    AND EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.status = 'APPROVED'
    )
  );

-- Provider can read their own store (even if inactive — for management)
CREATE POLICY provider_stores_owner_read ON provider_stores FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.user_id = auth.uid()
    )
  );

-- Provider can insert their own store
CREATE POLICY provider_stores_owner_insert ON provider_stores FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id
        AND pp.user_id = auth.uid()
        AND pp.status = 'APPROVED'
    )
  );

-- Provider can update their own store
CREATE POLICY provider_stores_owner_update ON provider_stores FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.user_id = auth.uid()
    )
  );

-- Provider can delete their own store
CREATE POLICY provider_stores_owner_delete ON provider_stores FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.user_id = auth.uid()
    )
  );

-- Admin manages all stores
CREATE POLICY provider_stores_admin_all ON provider_stores FOR ALL
  USING (is_admin()) WITH CHECK (is_admin());

-- =========================================================
-- 3. LISTING IMAGES
--    Public read for images on active listings.
--    Provider can only manage images belonging to their own listings.
-- =========================================================

-- Public can read images on active listings
CREATE POLICY listing_images_public_read ON listing_images FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM products p
      WHERE p.id = listing_id
        AND p.is_active = true
        AND p.listing_status = 'ACTIVE'
    )
  );

-- Provider can read images on their own listings (for management)
CREATE POLICY listing_images_owner_read ON listing_images FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM products p
      WHERE p.id = listing_id
        AND p.provider_id IN (
          SELECT pp.id FROM provider_profiles pp
          WHERE pp.user_id = auth.uid()
        )
    )
  );

-- Provider can insert images on their own listings
CREATE POLICY listing_images_owner_insert ON listing_images FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM products p
      WHERE p.id = listing_id
        AND p.provider_id IN (
          SELECT pp.id FROM provider_profiles pp
          WHERE pp.user_id = auth.uid()
        )
    )
  );

-- Provider can update images on their own listings
CREATE POLICY listing_images_owner_update ON listing_images FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM products p
      WHERE p.id = listing_id
        AND p.provider_id IN (
          SELECT pp.id FROM provider_profiles pp
          WHERE pp.user_id = auth.uid()
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM products p
      WHERE p.id = listing_id
        AND p.provider_id IN (
          SELECT pp.id FROM provider_profiles pp
          WHERE pp.user_id = auth.uid()
        )
    )
  );

-- Provider can delete images on their own listings
CREATE POLICY listing_images_owner_delete ON listing_images FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM products p
      WHERE p.id = listing_id
        AND p.provider_id IN (
          SELECT pp.id FROM provider_profiles pp
          WHERE pp.user_id = auth.uid()
        )
    )
  );

-- Admin manages all listing images
CREATE POLICY listing_images_admin_all ON listing_images FOR ALL
  USING (is_admin()) WITH CHECK (is_admin());

-- =========================================================
-- 4. PROVIDER GALLERY
--    Provider manages only their own gallery. Admin can moderate.
-- =========================================================

-- Public can read active gallery images for approved providers
CREATE POLICY provider_gallery_public_read ON provider_gallery FOR SELECT
  USING (
    is_active = true
    AND EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.status = 'APPROVED'
    )
  );

-- Provider can read their own gallery (for management)
CREATE POLICY provider_gallery_owner_read ON provider_gallery FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.user_id = auth.uid()
    )
  );

-- Provider can insert into their own gallery
CREATE POLICY provider_gallery_owner_insert ON provider_gallery FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id
        AND pp.user_id = auth.uid()
        AND pp.status = 'APPROVED'
    )
  );

-- Provider can update their own gallery
CREATE POLICY provider_gallery_owner_update ON provider_gallery FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.user_id = auth.uid()
    )
  );

-- Provider can delete their own gallery
CREATE POLICY provider_gallery_owner_delete ON provider_gallery FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM provider_profiles pp
      WHERE pp.id = provider_id AND pp.user_id = auth.uid()
    )
  );

-- Admin manages all gallery
CREATE POLICY provider_gallery_admin_all ON provider_gallery FOR ALL
  USING (is_admin()) WITH CHECK (is_admin());

-- =========================================================
-- 5. PRODUCTS (LISTINGS) RLS EXTENSION
--    Ensure suspended/rejected providers cannot publish active listings.
-- =========================================================

-- Trigger: prevent listing_status='ACTIVE' for non-approved providers
CREATE OR REPLACE FUNCTION prevent_inactive_provider_publish()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    IF NEW.listing_status = 'ACTIVE' AND OLD.listing_status != 'ACTIVE' THEN
      IF NOT EXISTS (
        SELECT 1 FROM provider_profiles pp
        WHERE pp.id = NEW.provider_id AND pp.status = 'APPROVED'
      ) THEN
        RAISE EXCEPTION 'SUSPENDED_OR_REJECTED_PROVIDERS_CANNOT_PUBLISH_ACTIVE_LISTINGS';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_listing_status_security
  BEFORE UPDATE ON products
  FOR EACH ROW
  WHEN (NEW.listing_status IS DISTINCT FROM OLD.listing_status)
  EXECUTE FUNCTION prevent_inactive_provider_publish();

-- Also enforce on insert
CREATE OR REPLACE FUNCTION prevent_inactive_provider_publish_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    IF NEW.listing_status = 'ACTIVE' THEN
      IF NOT EXISTS (
        SELECT 1 FROM provider_profiles pp
        WHERE pp.id = NEW.provider_id AND pp.status = 'APPROVED'
      ) THEN
        RAISE EXCEPTION 'SUSPENDED_OR_REJECTED_PROVIDERS_CANNOT_PUBLISH_ACTIVE_LISTINGS';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_listing_status_security_insert
  BEFORE INSERT ON products
  FOR EACH ROW
  EXECUTE FUNCTION prevent_inactive_provider_publish_insert();
