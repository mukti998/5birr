-- 5BIRR Milestone 8 — Phase 1: Marketplace Category Seed Data
-- Migration 0016_marketplace_seed.sql
-- Seeds sensible initial marketplace categories with subcategories.
-- Admin can add/edit/delete future categories without rebuilding the app.
-- All slugs are unique and used for URL-friendly identifiers.

-- =========================================================
-- MARKETPLACE CATEGORIES
-- Top-level categories with marketplace_sector mapping.
-- Existing categories get their marketplace_sector set where appropriate.
-- =========================================================

-- Update existing categories to map to marketplace sectors
UPDATE categories SET marketplace_sector = 'ACCOMMODATION'
  WHERE slug = 'hotels-lodging';

UPDATE categories SET marketplace_sector = 'FOOD'
  WHERE slug = 'food-restaurants';

UPDATE categories SET marketplace_sector = 'RETAIL'
  WHERE slug = 'retail';

UPDATE categories SET marketplace_sector = 'SERVICES'
  WHERE slug IN ('health', 'beauty', 'home-services', 'education',
                 'professional-services', 'entertainment', 'fitness',
                 'agriculture', 'real-estate');

UPDATE categories SET marketplace_sector = 'TRANSPORT'
  WHERE sector = 'VEHICLE';

-- Add descriptions to existing categories
UPDATE categories SET description = 'Hotels, guesthouses, lodges, resorts, and short-term accommodation'
  WHERE slug = 'hotels-lodging';

UPDATE categories SET description = 'Restaurants, cafes, bakeries, and food delivery services'
  WHERE slug = 'food-restaurants';

UPDATE categories SET description = 'Retail shops, groceries, electronics, and general merchandise'
  WHERE slug = 'retail';

UPDATE categories SET description = 'Healthcare providers, pharmacies, clinics, and medical services'
  WHERE slug = 'health';

UPDATE categories SET description = 'Barbers, salons, beauty services, and wellness'
  WHERE slug = 'beauty';

UPDATE categories SET description = 'Home repair, construction, cleaning, and maintenance services'
  WHERE slug = 'home-services';

UPDATE categories SET description = 'Schools, training centers, tutoring, and educational services'
  WHERE slug = 'education';

UPDATE categories SET description = 'Accounting, legal, consulting, and professional services'
  WHERE slug = 'professional-services';

UPDATE categories SET description = 'Events, entertainment venues, and recreational activities'
  WHERE slug = 'entertainment';

UPDATE categories SET description = 'Gyms, sports facilities, and fitness services'
  WHERE slug = 'fitness';

UPDATE categories SET description = 'Agricultural products, farm services, and equipment'
  WHERE slug = 'agriculture';

UPDATE categories SET description = 'Real estate, property listings, and rental services'
  WHERE slug = 'real-estate';

UPDATE categories SET description = 'Ride-hailing, taxi, and passenger transport'
  WHERE slug = 'ride-taxi';

UPDATE categories SET description = 'Delivery vehicles and logistics services'
  WHERE slug = 'delivery-vehicle';

UPDATE categories SET description = 'Food delivery and courier services'
  WHERE slug = 'food-delivery';

-- =========================================================
-- NEW MARKETPLACE-SPECIFIC SUBCATEGORIES
-- Add useful subcategories that don't exist yet.
-- =========================================================

-- FOOD subcategories (under food-restaurants parent)
INSERT INTO categories (parent_id, name, sector, slug, marketplace_sector, description, sort_order)
SELECT p.id, sub.name, 'SERVICE', sub.slug, 'FOOD', sub.description, sub.sort_order
FROM categories p
JOIN (VALUES
  ('food-restaurants', 'Food Trucks', 'food-trucks', 'Mobile food vendors and street food', 7),
  ('food-restaurants', 'Juice Bars', 'juice-bars', 'Fresh juices, smoothies, and health drinks', 8),
  ('food-restaurants', 'Coffee Shops', 'coffee-shops', 'Coffee, tea, and beverages', 9)
) AS sub(parent_slug, name, slug, description, sort_order)
ON p.slug = sub.parent_slug
ON CONFLICT (slug) DO NOTHING;

-- RETAIL subcategories
INSERT INTO categories (parent_id, name, sector, slug, marketplace_sector, description, sort_order)
SELECT p.id, sub.name, 'SERVICE', sub.slug, 'RETAIL', sub.description, sub.sort_order
FROM categories p
JOIN (VALUES
  ('retail', 'Handmade Crafts', 'handmade-crafts', 'Handmade and artisanal products', 8),
  ('retail', 'Books & Stationery', 'books-stationery', 'Books, notebooks, and office supplies', 9),
  ('retail', 'Sports & Outdoors', 'sports-outdoors', 'Sports equipment and outdoor gear', 10),
  ('retail', 'Baby & Kids', 'baby-kids', 'Baby products, toys, and children items', 11),
  ('retail', 'Automotive Parts', 'automotive-parts', 'Car parts, accessories, and supplies', 12),
  ('retail', 'Garden & Home', 'garden-home', 'Garden tools, decor, and home improvement', 13)
) AS sub(parent_slug, name, slug, description, sort_order)
ON p.slug = sub.parent_slug
ON CONFLICT (slug) DO NOTHING;

-- ACCOMMODATION subcategories
INSERT INTO categories (parent_id, name, sector, slug, marketplace_sector, description, sort_order)
SELECT p.id, sub.name, 'SERVICE', sub.slug, 'ACCOMMODATION', sub.description, sub.sort_order
FROM categories p
JOIN (VALUES
  ('hotels-lodging', 'Vacation Rentals', 'vacation-rentals', 'Short-term vacation property rentals', 6),
  ('hotels-lodging', 'Hostels', 'hostels', 'Budget-friendly shared accommodation', 7),
  ('hotels-lodging', 'Apartments', 'apartments', 'Serviced apartments and furnished units', 8)
) AS sub(parent_slug, name, slug, description, sort_order)
ON p.slug = sub.parent_slug
ON CONFLICT (slug) DO NOTHING;

-- SERVICES subcategories (add under existing parents)
INSERT INTO categories (parent_id, name, sector, slug, marketplace_sector, description, sort_order)
SELECT p.id, sub.name, 'SERVICE', sub.slug, 'SERVICES', sub.description, sub.sort_order
FROM categories p
JOIN (VALUES
  ('home-services', 'Moving & Packing', 'moving-packing', 'Relocation and moving services', 7),
  ('home-services', 'Interior Design', 'interior-design', 'Interior decoration and design services', 8),
  ('professional-services', 'IT Services', 'it-services', 'Computer repair, web design, and IT support', 6),
  ('professional-services', 'Translation', 'translation', 'Translation and interpretation services', 7),
  ('professional-services', 'Delivery Services', 'delivery-services', 'Package delivery and courier services', 8),
  ('health', 'Mental Health', 'mental-health', 'Counseling and mental health services', 6),
  ('beauty', 'Tattoo & Piercing', 'tattoo-piercing', 'Tattoo and body piercing studios', 5),
  ('fitness', 'Yoga & Meditation', 'yoga-meditation', 'Yoga classes and meditation sessions', 4),
  ('entertainment', 'Photography Studios', 'photography-studios', 'Professional photography and videography', 4),
  ('education', 'Online Courses', 'online-courses', 'Digital learning and online education platforms', 5)
) AS sub(parent_slug, name, slug, description, sort_order)
ON p.slug = sub.parent_slug
ON CONFLICT (slug) DO NOTHING;

-- TRANSPORT subcategories
INSERT INTO categories (parent_id, name, sector, slug, marketplace_sector, description, sort_order)
SELECT p.id, sub.name, 'VEHICLE', sub.slug, 'TRANSPORT', sub.description, sub.sort_order
FROM categories p
JOIN (VALUES
  ('ride-taxi', 'Bike Taxi', 'bike-taxi', 'Motorcycle and bike taxi services', 14),
  ('ride-taxi', 'Shared Rides', 'shared-rides', 'Carpooling and ride-sharing services', 15),
  ('delivery-vehicle', 'Express Delivery', 'express-delivery', 'Same-day and express package delivery', 14),
  ('car-rental', 'Luxury Car Rental', 'luxury-car-rental', 'Premium and luxury vehicle rental', 15),
  ('freight-cargo', 'Moving Trucks', 'moving-trucks', 'Large vehicle rental for moving and logistics', 16),
  ('tour-travel', 'Safari Tours', 'safari-tours', 'Wildlife safari and nature tour packages', 17)
) AS sub(parent_slug, name, slug, description, sort_order)
ON p.slug = sub.parent_slug
ON CONFLICT (slug) DO NOTHING;

-- =========================================================
-- NEW TOP-LEVEL MARKETPLACE CATEGORIES
-- For categories that don't fit existing parents.
-- =========================================================

-- OTHER sector: general/miscellaneous
INSERT INTO categories (name, sector, slug, marketplace_sector, description, sort_order)
VALUES ('Other Services', 'SERVICE', 'other-services', 'OTHER',
        'Miscellaneous services not classified elsewhere', 50)
ON CONFLICT (slug) DO NOTHING;

-- =========================================================
-- MARKETPLACE SECTOR MAPPING FOR NAVIGATION
-- =========================================================

-- Create a view for easy marketplace sector navigation
CREATE OR REPLACE VIEW marketplace_sectors AS
SELECT
  marketplace_sector,
  COUNT(*) FILTER (WHERE parent_id IS NULL) AS top_category_count,
  COUNT(*) AS total_category_count
FROM categories
WHERE is_active = true
  AND marketplace_sector IS NOT NULL
GROUP BY marketplace_sector
ORDER BY marketplace_sector;
