-- Phase 4 booking status vocabulary; keep this migration separate because new enum labels
-- must be committed before later migrations can use them in SQL expressions.
alter type public.booking_status add value if not exists 'expired';
alter type public.booking_status add value if not exists 'refunded';
