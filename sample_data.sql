-- ================================================================
-- On The Road — بيانات تجريبية حقيقية للرحلات والسائقين (Sample Data)
-- ================================================================

-- 1. فك قيد الارتباط المؤقت للسماح بسائقين تجريبيين للعرض
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;

-- 2. إضافة 3 سائقين موثقين
INSERT INTO public.profiles (
  id, name, phone, role, verification_status, car_model, car_color, car_plate, rating, trips_count
) VALUES 
(
  '11111111-1111-1111-1111-111111111111',
  'محمود السيد',
  '+201011111111',
  'driver',
  'approved',
  'تويوتا كورولا 2022',
  'أبيض',
  'أ ب ج 1234',
  4.9,
  142
),
(
  '22222222-2222-2222-2222-222222222222',
  'كريم حسني',
  '+201022222222',
  'driver',
  'approved',
  'هيونداي إلنترا 2023',
  'رمادي',
  'س ص ع 5678',
  4.8,
  89
),
(
  '33333333-3333-3333-3333-333333333333',
  'محمد عادل',
  '+201033333333',
  'driver',
  'approved',
  'كيا سيراتو 2021',
  'أسود',
  'د ر و 9988',
  5.0,
  210
)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

-- 3. إضافة رحلات حية
INSERT INTO public.trips (
  id, driver_id, origin_city, destination_city, departure_time, arrival_time, total_seats, status, notes
) VALUES
(
  'aaaa1111-1111-1111-1111-111111111111',
  '11111111-1111-1111-1111-111111111111',
  'القاهرة',
  'الإسكندرية',
  NOW() + INTERVAL '1 day',
  NOW() + INTERVAL '1 day 2 hours 30 minutes',
  3,
  'upcoming',
  'التحرك من محطة مترو رمسيس - سيارة مكيفة بالكامل'
),
(
  'bbbb2222-2222-2222-2222-222222222222',
  '22222222-2222-2222-2222-222222222222',
  'القاهرة',
  'الإسكندرية',
  NOW() + INTERVAL '1 day 3 hours',
  NOW() + INTERVAL '1 day 5 hours 30 minutes',
  4,
  'upcoming',
  'مرور ببنها ودمنهور - متاح حقائب متوسطة'
)
ON CONFLICT (id) DO NOTHING;

-- 4. إضافة مقاطع الرحلات والأسعار
INSERT INTO public.trip_segments (
  trip_id, from_city, to_city, segment_order, price, segment_kind
) VALUES
('aaaa1111-1111-1111-1111-111111111111', 'القاهرة', 'طنطا', 1, 60.00, 'leg'),
('aaaa1111-1111-1111-1111-111111111111', 'طنطا', 'الإسكندرية', 2, 70.00, 'leg'),
('aaaa1111-1111-1111-1111-111111111111', 'القاهرة', 'الإسكندرية', 3, 120.00, 'fare_override'),

('bbbb2222-2222-2222-2222-222222222222', 'القاهرة', 'بنها', 1, 40.00, 'leg'),
('bbbb2222-2222-2222-2222-222222222222', 'بنها', 'دمنهور', 2, 60.00, 'leg'),
('bbbb2222-2222-2222-2222-222222222222', 'دمنهور', 'الإسكندرية', 3, 50.00, 'leg'),
('bbbb2222-2222-2222-2222-222222222222', 'القاهرة', 'الإسكندرية', 4, 110.00, 'fare_override');

