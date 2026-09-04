-- 5BIRR — Storage Bucket Policies
-- Migration 0012_storage_policies.sql
-- Configures Supabase Storage bucket access policies.
-- Run AFTER creating buckets in the Supabase dashboard/CLI:
--   supabase storage create user-documents --no-public
--   supabase storage create payment-proofs --no-public
--   supabase storage create product-images
--   supabase storage create vehicle-images

-- =========================================================
-- BUCKET CREATION (idempotent)
-- =========================================================

-- Create buckets if they don't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('user-documents', 'user-documents', false, 10485760, -- 10MB
   ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('payment-proofs', 'payment-proofs', false, 10485760, -- 10MB
   ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('product-images', 'product-images', true, 5242880, -- 5MB
   ARRAY['image/jpeg', 'image/png', 'image/webp']),
  ('vehicle-images', 'vehicle-images', true, 5242880, -- 5MB
   ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

-- =========================================================
-- USER-DOCUMENTS (PRIVATE)
-- Owner uploads, owner reads, admin reads.
-- Path convention: {user_id}/{document_type}/{filename}
-- =========================================================

-- Allow authenticated users to upload to their own folder
CREATE POLICY user_documents_insert ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'user-documents'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Allow owners to read their own documents
CREATE POLICY user_documents_select_own ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'user-documents'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Allow admins to read all user documents
CREATE POLICY user_documents_admin_read ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'user-documents'
    AND EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_id = auth.uid() AND role = 'ADMIN'
    )
  );

-- Allow owners to delete their own documents
CREATE POLICY user_documents_delete_own ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'user-documents'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- =========================================================
-- PAYMENT-PROOFS (PRIVATE)
-- Provider uploads, provider reads own, admin reads all.
-- Path convention: {provider_user_id}/{recharge_id}/{filename}
-- =========================================================

-- Allow authenticated users to upload payment proofs
CREATE POLICY payment_proofs_insert ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'payment-proofs'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Allow owners to read their own payment proofs
CREATE POLICY payment_proofs_select_own ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'payment-proofs'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Allow admins to read all payment proofs
CREATE POLICY payment_proofs_admin_read ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'payment-proofs'
    AND EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_id = auth.uid() AND role = 'ADMIN'
    )
  );

-- =========================================================
-- PRODUCT-IMAGES (PUBLIC READ)
-- Provider writes to own folder, anyone reads.
-- Path convention: {provider_user_id}/{product_id}/{filename}
-- =========================================================

-- Allow authenticated providers to upload product images
CREATE POLICY product_images_insert ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'product-images'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Public read for product images
CREATE POLICY product_images_public_read ON storage.objects
  FOR SELECT
  USING (bucket_id = 'product-images');

-- Allow owners to update their own product images
CREATE POLICY product_images_update_own ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'product-images'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Allow owners to delete their own product images
CREATE POLICY product_images_delete_own ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'product-images'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- =========================================================
-- VEHICLE-IMAGES (PUBLIC READ)
-- Provider writes to own folder, anyone reads.
-- Path convention: {provider_user_id}/{vehicle_id}/{filename}
-- =========================================================

-- Allow authenticated providers to upload vehicle images
CREATE POLICY vehicle_images_insert ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'vehicle-images'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Public read for vehicle images
CREATE POLICY vehicle_images_public_read ON storage.objects
  FOR SELECT
  USING (bucket_id = 'vehicle-images');

-- Allow owners to update their own vehicle images
CREATE POLICY vehicle_images_update_own ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'vehicle-images'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );

-- Allow owners to delete their own vehicle images
CREATE POLICY vehicle_images_delete_own ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'vehicle-images'
    AND auth.uid()::text = (string_to_array(name, '/'))[1]
  );
