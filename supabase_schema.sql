-- ================================================================
-- On The Road — Database Schema for Supabase PostgreSQL
-- ================================================================

-- 1. جدول المستخدمين (Profiles)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT UNIQUE,
  role TEXT CHECK (role IN ('passenger', 'driver', 'admin')) DEFAULT 'passenger',
  avatar_url TEXT,
  verification_status TEXT CHECK (verification_status IN (
    'unverified', 'pending', 'approved', 'rejected', 'resubmission_required'
  )) DEFAULT 'unverified',
  national_id TEXT,
  id_front_url TEXT,
  id_back_url TEXT,
  selfie_url TEXT,
  license_url TEXT,
  car_model TEXT,
  car_color TEXT,
  car_plate TEXT,
  rating NUMERIC(3,2) DEFAULT 5.0,
  trips_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. جدول الرحلات (Trips)
CREATE TABLE IF NOT EXISTS public.trips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  origin_city TEXT NOT NULL,
  destination_city TEXT NOT NULL,
  departure_time TIMESTAMPTZ NOT NULL,
  arrival_time TIMESTAMPTZ,
  total_seats INT NOT NULL DEFAULT 3,
  notes TEXT,
  status TEXT CHECK (status IN ('upcoming', 'active', 'completed', 'cancelled')) DEFAULT 'upcoming',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. جدول مقاطع الرحلة والأسعار (Trip Segments)
CREATE TABLE IF NOT EXISTS public.trip_segments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  from_city TEXT NOT NULL,
  to_city TEXT NOT NULL,
  segment_order INT NOT NULL,
  price NUMERIC(10,2) NOT NULL
);

-- 4. جدول الحجوزات (Bookings)
CREATE TABLE IF NOT EXISTS public.bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  passenger_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  pickup_city TEXT NOT NULL,
  dropoff_city TEXT NOT NULL,
  pickup_order INT NOT NULL DEFAULT 1,
  dropoff_order INT NOT NULL DEFAULT 2,
  seats_booked INT NOT NULL DEFAULT 1,
  total_price NUMERIC(10,2) NOT NULL,
  status TEXT CHECK (status IN (
    'pending', 'confirmed', 'rejected', 'cancelled', 'completed', 'no_show'
  )) DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. جدول الرسائل والمحادثة (Messages)
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================================
-- 6. دالة حساب المقاعد المتاحة لكل مقطع (Core Seat Logic)
-- ================================================================
CREATE OR REPLACE FUNCTION available_seats(
  p_trip_id UUID,
  p_pickup_order INT,
  p_dropoff_order INT
) RETURNS INT AS $$
DECLARE
  v_total_seats INT;
  v_max_booked INT;
BEGIN
  SELECT total_seats INTO v_total_seats FROM public.trips WHERE id = p_trip_id;

  SELECT COALESCE(MAX(segment_booked), 0) INTO v_max_booked
  FROM (
    SELECT SUM(b.seats_booked) AS segment_booked
    FROM public.bookings b
    WHERE b.trip_id = p_trip_id
      AND b.status IN ('pending', 'confirmed')
      AND b.pickup_order < p_dropoff_order
      AND b.dropoff_order > p_pickup_order
  ) sub;

  RETURN GREATEST(0, v_total_seats - v_max_booked);
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- 7. تفعيل الحماية وسياسات الأمان (Row Level Security - RLS)
-- ================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- سياسات القراءة العامة للرحلات والمقاطع
CREATE POLICY "Public read trips" ON public.trips FOR SELECT USING (true);
CREATE POLICY "Public read segments" ON public.trip_segments FOR SELECT USING (true);
CREATE POLICY "Public read profiles" ON public.profiles FOR SELECT USING (true);

-- سياسات المستخدم لملفه وحجوزاته
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can view own bookings" ON public.bookings FOR SELECT USING (auth.uid() = passenger_id);
CREATE POLICY "Users can create bookings" ON public.bookings FOR INSERT WITH CHECK (auth.uid() = passenger_id);
CREATE POLICY "Drivers can view trip bookings" ON public.bookings FOR SELECT USING (
  auth.uid() IN (SELECT driver_id FROM public.trips WHERE id = trip_id)
);
