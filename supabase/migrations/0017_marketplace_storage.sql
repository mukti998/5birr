-- 5BIRR Milestone 8 — Phase 1: Marketplace Storage Buckets
-- Migration 0017_marketplace_storage.sql
-- Adds provider-gallery bucket for marketplace provider gallery images.

-- =========================================================
-- PROVIDER GALLERY BUCKET (PUBLIC READ)
-- Provider writes to own folder, anyone reads.
-- Path convention: {provider_user_id}/{gallery_id}/{filename}
-- =========================================================

-- Create bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('provider-gallery', 'provider-gallery', true, 5242880, -- 5MB
   ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated providers to upload to their own folder
CREATE POLICY provider_gallery_insert ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'provider-gallery'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Public read for gallery images
CREATE POLICY provider_gallery_public_read ON storage.objects
  FOR SELECT
  USING (bucket_id = 'provider-gallery');

-- Allow owners to update their own gallery images
CREATE POLICY provider_gallery_update_own ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'provider-gallery'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Allow owners to delete their own gallery images
CREATE POLICY provider_gallery_delete_own ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'provider-gallery'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );
