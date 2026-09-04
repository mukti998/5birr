-- 5BIRR Phase 1 — Seed / Demo Data
-- Migration 0004_seed.sql
-- SAFE FOR DEV ONLY. Do not run against production without review.

-- =========================================================
-- SERVICE CATEGORIES
-- =========================================================
insert into categories (name, sector, slug, sort_order) values
  ('Hotels & Lodging', 'SERVICE', 'hotels-lodging', 1),
  ('Food & Restaurants', 'SERVICE', 'food-restaurants', 2),
  ('Retail', 'SERVICE', 'retail', 3),
  ('Health', 'SERVICE', 'health', 4),
  ('Beauty', 'SERVICE', 'beauty', 5),
  ('Home Services', 'SERVICE', 'home-services', 6),
  ('Education', 'SERVICE', 'education', 7),
  ('Professional Services', 'SERVICE', 'professional-services', 8),
  ('Entertainment', 'SERVICE', 'entertainment', 9),
  ('Fitness', 'SERVICE', 'fitness', 10),
  ('Agriculture', 'SERVICE', 'agriculture', 11),
  ('Real Estate', 'SERVICE', 'real-estate', 12);

insert into categories (parent_id, name, sector, slug, sort_order)
select id, sub.name, 'SERVICE', sub.slug, sub.sort_order from categories p
join (values
  ('hotels-lodging','Hotels','hotels',1),('hotels-lodging','Guesthouses','guesthouses',2),
  ('hotels-lodging','Lodges','lodges',3),('hotels-lodging','Resorts','resorts',4),('hotels-lodging','Rooms','rooms',5),
  ('food-restaurants','Restaurants','restaurants',1),('food-restaurants','Cafes','cafes',2),
  ('food-restaurants','Fast Food','fast-food',3),('food-restaurants','Bakeries','bakeries',4),
  ('food-restaurants','Traditional Food','traditional-food',5),('food-restaurants','Catering','catering',6),
  ('retail','Grocery','grocery',1),('retail','Clothing','clothing',2),('retail','Electronics','electronics',3),
  ('retail','Phones & Accessories','phones-accessories',4),('retail','Furniture','furniture',5),
  ('retail','Cosmetics','cosmetics',6),('retail','General Shops','general-shops',7),
  ('health','Pharmacies','pharmacies',1),('health','Clinics','clinics',2),('health','Laboratories','laboratories',3),
  ('health','Dental','dental',4),('health','Health Services','health-services',5),
  ('beauty','Barbers','barbers',1),('beauty','Hair Salons','hair-salons',2),
  ('beauty','Beauty Salons','beauty-salons',3),('beauty','Spa','spa',4),
  ('home-services','Plumbing','plumbing',1),('home-services','Electrical','electrical',2),
  ('home-services','Cleaning','cleaning',3),('home-services','Construction','construction',4),
  ('home-services','Repair','repair',5),('home-services','Maintenance','maintenance',6),
  ('education','Schools','schools',1),('education','Training Centers','training-centers',2),
  ('education','Tutors','tutors',3),('education','Courses','courses',4),
  ('professional-services','Accounting','accounting',1),('professional-services','Legal','legal',2),
  ('professional-services','Consulting','consulting',3),('professional-services','Printing','printing',4),
  ('professional-services','Photography','photography',5),
  ('entertainment','Events','events',1),('entertainment','Entertainment Centers','entertainment-centers',2),
  ('entertainment','Recreation','recreation',3),
  ('fitness','Gyms','gyms',1),('fitness','Sports','sports',2),('fitness','Fitness Centers','fitness-centers',3),
  ('agriculture','Agricultural Products','agricultural-products',1),('agriculture','Farm Services','farm-services',2),
  ('agriculture','Equipment','equipment',3),
  ('real-estate','Houses','houses',1),('real-estate','Land','land',2),
  ('real-estate','Rentals','rentals',3),('real-estate','Property Services','property-services',4)
) as sub(parent_slug, name, slug, sort_order) on p.slug = sub.parent_slug;

-- =========================================================
-- VEHICLE CATEGORIES
-- =========================================================
insert into categories (name, sector, slug, sort_order) values
  ('Ride / Taxi', 'VEHICLE', 'ride-taxi', 1),
  ('Delivery Vehicle', 'VEHICLE', 'delivery-vehicle', 2),
  ('Food Delivery', 'VEHICLE', 'food-delivery', 3),
  ('Motorcycle / Bajaj', 'VEHICLE', 'motorcycle-bajaj', 4),
  ('Car Rental', 'VEHICLE', 'car-rental', 5),
  ('Bus', 'VEHICLE', 'bus', 6),
  ('Minibus', 'VEHICLE', 'minibus', 7),
  ('Truck', 'VEHICLE', 'truck', 8),
  ('Freight / Cargo', 'VEHICLE', 'freight-cargo', 9),
  ('Tour & Travel', 'VEHICLE', 'tour-travel', 10),
  ('Airport Transport', 'VEHICLE', 'airport-transport', 11),
  ('Special Transport', 'VEHICLE', 'special-transport', 12),
  ('Ambulance / Emergency Transport', 'VEHICLE', 'ambulance-emergency', 13);

-- =========================================================
-- DEV ADMIN BOOTSTRAP
-- IMPORTANT: The seed password (77777) referenced in the spec must NEVER be
-- hard-coded into the Flutter client or committed as a real credential.
-- Create the actual auth.users row via `supabase auth admin create-user`
-- (see README) using a real dev password from your local .env, then run:
--
--   insert into user_roles (user_id, role) values ('<uuid-from-auth>', 'ADMIN');
--   insert into profiles (id, full_name, status) values ('<uuid-from-auth>', 'Dev Admin', 'APPROVED');
--
-- Admin UI access is additionally gated by the "tap logo 5x" client-side
-- reveal (cosmetic only) — real authorization is enforced by has_role()/is_admin()
-- in RLS and Edge Functions, never by the client-side tap gesture.
