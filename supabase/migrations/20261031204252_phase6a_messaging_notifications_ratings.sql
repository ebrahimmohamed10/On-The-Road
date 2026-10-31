-- Phase 6a: private booking conversations, in-app notification inbox/outbox, and post-trip ratings.
begin;

create table if not exists public.conversations (
 id uuid primary key default extensions.gen_random_uuid(),
 booking_id uuid not null unique references public.bookings(id) on delete cascade,
 trip_id uuid not null references public.trips(id) on delete cascade,
 rider_id uuid not null references public.profiles(id) on delete cascade,
 driver_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
insert into public.conversations(booking_id,trip_id,rider_id,driver_id)
select b.id,b.trip_id,b.passenger_id,t.driver_id
from public.bookings b join public.trips t on t.id=b.trip_id
on conflict(booking_id) do nothing;
alter table public.messages add column if not exists conversation_id uuid references public.conversations(id) on delete cascade;
update public.messages m set conversation_id=c.id from public.conversations c
where c.booking_id=m.booking_id and m.conversation_id is null;
alter table public.messages alter column conversation_id set not null;
create index if not exists messages_conversation_created_idx on public.messages(conversation_id,created_at);

alter table public.conversations enable row level security;
revoke all on public.conversations from public,anon,authenticated;
grant select on public.conversations to authenticated;
create policy conversations_participant_read on public.conversations for select to authenticated
using(rider_id=(select auth.uid()) or driver_id=(select auth.uid()));

drop policy if exists messages_participant_read on public.messages;
alter table public.messages enable row level security;
revoke all on public.messages from public,anon,authenticated;
grant select on public.messages to authenticated;
create policy messages_participant_read on public.messages for select to authenticated
using(exists(select 1 from public.conversations c where c.id=conversation_id
 and (c.rider_id=(select auth.uid()) or c.driver_id=(select auth.uid()))));

create or replace function public.ensure_booking_conversation()
returns trigger
language plpgsql security definer set search_path=''
as $$
begin
 if new.status='confirmed' then
  insert into public.conversations(booking_id,trip_id,rider_id,driver_id)
  select new.id,new.trip_id,new.passenger_id,t.driver_id from public.trips t where t.id=new.trip_id
  on conflict(booking_id) do nothing;
 end if;
 return new;
end $$;
revoke all on function public.ensure_booking_conversation() from public,anon,authenticated;
create trigger booking_conversation_on_confirm after insert or update of status on public.bookings
for each row execute function public.ensure_booking_conversation();

create or replace function public.send_message(p_booking_id uuid,p_content text)
returns public.messages
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype; v_conversation public.conversations%rowtype; v_message public.messages%rowtype; v_days integer;
begin
 if v_user is null or p_content is null or length(pg_catalog.btrim(p_content))<1 or length(p_content)>4000 then
  raise exception using errcode='22023',message='Sign in and enter a message up to 4000 characters.';
 end if;
 select * into v_booking from public.bookings where id=p_booking_id for share;
 if not found or v_user not in (v_booking.passenger_id,(select t.driver_id from public.trips t where t.id=v_booking.trip_id)) then
  raise exception using errcode='42501',message='You are not part of this booking.';
 end if;
 select * into v_trip from public.trips where id=v_booking.trip_id;
 if v_booking.status not in ('confirmed','completed') or v_trip.status='cancelled' then
  raise exception using errcode='42501',message='Messaging is available only for confirmed trips.';
 end if;
 if v_trip.status='completed' then
  select (value#>>'{}')::integer into v_days from public.app_settings where key='chat_retention_days_after_trip';
  if v_trip.arrival_time is not null and pg_catalog.now()>v_trip.arrival_time+pg_catalog.make_interval(days=>coalesce(v_days,30)) then
   raise exception using errcode='42501',message='The messaging period for this trip has ended.';
  end if;
 end if;
 insert into public.conversations(booking_id,trip_id,rider_id,driver_id)
 values(v_booking.id,v_booking.trip_id,v_booking.passenger_id,v_trip.driver_id)
 on conflict(booking_id) do nothing;
 select * into v_conversation from public.conversations where booking_id=p_booking_id;
 insert into public.messages(booking_id,conversation_id,sender_id,content)
 values(v_booking.id,v_conversation.id,v_user,pg_catalog.btrim(p_content))
 returning * into v_message;
 return v_message;
end $$;
revoke all on function public.send_message(uuid,text) from public,anon,authenticated;
grant execute on function public.send_message(uuid,text) to authenticated;

create table if not exists public.notifications (
 id uuid primary key default extensions.gen_random_uuid(),
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 category text not null check(category in ('booking','trip','message','safety','support','account')),
 title jsonb not null,
 body jsonb not null,
 data jsonb not null default '{}'::jsonb,
 idempotency_key text not null unique,
 read_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists notifications_recipient_unread_idx on public.notifications(recipient_id,created_at desc) where read_at is null;
create index if not exists notifications_recipient_created_idx on public.notifications(recipient_id,created_at desc);
create table if not exists public.notification_outbox (
 id uuid primary key default extensions.gen_random_uuid(),
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 category text not null,
 event_type text not null,
 payload jsonb not null default '{}'::jsonb,
 idempotency_key text not null unique,
 available_at timestamptz not null default pg_catalog.now(),
 attempts integer not null default 0 check(attempts>=0),
 delivered_at timestamptz,
 last_error text,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists notification_outbox_pending_idx on public.notification_outbox(available_at,created_at) where delivered_at is null;
create index if not exists notification_outbox_recipient_idx on public.notification_outbox(recipient_id,created_at desc);

alter table public.notifications enable row level security;
alter table public.notification_outbox enable row level security;
revoke all on public.notifications,public.notification_outbox from public,anon,authenticated;
grant select on public.notifications to authenticated;
grant update(read_at) on public.notifications to authenticated;
create policy notifications_own_read on public.notifications for select to authenticated using(recipient_id=(select auth.uid()));
create policy notifications_own_mark_read on public.notifications for update to authenticated using(recipient_id=(select auth.uid())) with check(recipient_id=(select auth.uid()));
grant select,update on public.notification_outbox to service_role;

create trigger set_updated_at before update on public.conversations for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.notifications for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.notification_outbox for each row execute function public.set_updated_at();

create or replace function public.enqueue_notification(
 p_recipient uuid,p_category text,p_event text,p_title jsonb,p_body jsonb,p_data jsonb,p_key text
)
returns void
language plpgsql security definer set search_path=''
as $$
begin
 if p_recipient is null or p_recipient=auth.uid() and p_event='new_message' then return; end if;
 insert into public.notifications(recipient_id,category,title,body,data,idempotency_key)
 values(p_recipient,p_category,p_title,p_body,coalesce(p_data,'{}'::jsonb),p_key)
 on conflict(idempotency_key) do nothing;
 insert into public.notification_outbox(recipient_id,category,event_type,payload,idempotency_key)
 values(p_recipient,p_category,p_event,coalesce(p_data,'{}'::jsonb),p_key)
 on conflict(idempotency_key) do nothing;
end $$;
revoke all on function public.enqueue_notification(uuid,text,text,jsonb,jsonb,jsonb,text) from public,anon,authenticated;

create or replace function public.notify_booking_status_change()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare v_driver uuid; v_title jsonb; v_body jsonb; v_key text;
begin
 if old.status is not distinct from new.status then return new; end if;
 select driver_id into v_driver from public.trips where id=new.trip_id;
 v_title:=case new.status when 'confirmed' then '{"ar":"تم تأكيد الحجز","en":"Booking confirmed"}'::jsonb
  when 'rejected' then '{"ar":"تعذر تأكيد الحجز","en":"Booking declined"}'::jsonb
  when 'cancelled' then '{"ar":"تم إلغاء الحجز","en":"Booking cancelled"}'::jsonb
  when 'completed' then '{"ar":"اكتملت الرحلة","en":"Trip completed"}'::jsonb
  when 'no_show' then '{"ar":"لم يتم تسجيل صعودك","en":"Boarding was not recorded"}'::jsonb
  else '{"ar":"تحديث الحجز","en":"Booking update"}'::jsonb end;
 v_body:='{"ar":"تحديث لحالة حجزك.","en":"There is an update to your booking."}'::jsonb;
 v_key:='booking:'||new.id::text||':'||new.status::text||':'||new.updated_at::text;
 perform public.enqueue_notification(new.passenger_id,'booking','booking_status',v_title,v_body,jsonb_build_object('booking_id',new.id,'status',new.status::text),v_key||':rider');
 perform public.enqueue_notification(v_driver,'booking','booking_status',v_title,v_body,jsonb_build_object('booking_id',new.id,'status',new.status::text),v_key||':driver');
 return new;
end $$;
revoke all on function public.notify_booking_status_change() from public,anon,authenticated;
create trigger booking_status_notification after update of status on public.bookings
for each row execute function public.notify_booking_status_change();

create or replace function public.notify_trip_status_change()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare v_booking record; v_title jsonb; v_body jsonb; v_key text;
begin
 if old.status is not distinct from new.status then return new; end if;
 v_title:=case new.status when 'in_progress' then '{"ar":"بدأت الرحلة","en":"Trip started"}'::jsonb
  when 'completed' then '{"ar":"اكتملت الرحلة","en":"Trip completed"}'::jsonb
  when 'cancelled' then '{"ar":"تم إلغاء الرحلة","en":"Trip cancelled"}'::jsonb
  else '{"ar":"تحديث الرحلة","en":"Trip update"}'::jsonb end;
 v_body:='{"ar":"هناك تحديث على رحلتك.","en":"There is an update to your trip."}'::jsonb;
 v_key:='trip:'||new.id::text||':'||new.status::text||':'||new.updated_at::text;
 perform public.enqueue_notification(new.driver_id,'trip','trip_status',v_title,v_body,jsonb_build_object('trip_id',new.id,'status',new.status::text),v_key||':driver');
 for v_booking in select distinct passenger_id from public.bookings where trip_id=new.id loop
  perform public.enqueue_notification(v_booking.passenger_id,'trip','trip_status',v_title,v_body,jsonb_build_object('trip_id',new.id,'status',new.status::text),v_key||':'||v_booking.passenger_id::text);
 end loop;
 return new;
end $$;
revoke all on function public.notify_trip_status_change() from public,anon,authenticated;
create trigger trip_status_notification after update of status on public.trips
for each row execute function public.notify_trip_status_change();

create or replace function public.notify_new_message()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare v_conversation public.conversations%rowtype; v_recipient uuid; v_key text;
begin
 select * into v_conversation from public.conversations where id=new.conversation_id;
 v_recipient:=case when new.sender_id=v_conversation.rider_id then v_conversation.driver_id else v_conversation.rider_id end;
 v_key:='message:'||new.id::text;
 perform public.enqueue_notification(v_recipient,'message','new_message',
  '{"ar":"رسالة جديدة","en":"New message"}'::jsonb,
  '{"ar":"لديك رسالة جديدة في محادثة الرحلة.","en":"You have a new trip message."}'::jsonb,
  jsonb_build_object('booking_id',new.booking_id,'conversation_id',new.conversation_id),v_key);
 return new;
end $$;
revoke all on function public.notify_new_message() from public,anon,authenticated;
create trigger new_message_notification after insert on public.messages
for each row execute function public.notify_new_message();

create table if not exists public.ratings (
 id uuid primary key default extensions.gen_random_uuid(),
 booking_id uuid not null references public.bookings(id) on delete cascade,
 reviewer_id uuid not null references public.profiles(id) on delete cascade,
 reviewee_id uuid not null references public.profiles(id) on delete cascade,
 score smallint not null check(score between 1 and 5),
 comment text check(comment is null or length(comment)<=2000),
 is_visible boolean not null default true,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint ratings_reviewer_booking_key unique(booking_id,reviewer_id),
 constraint ratings_not_self check(reviewer_id<>reviewee_id)
);
create index if not exists ratings_reviewee_created_idx on public.ratings(reviewee_id,created_at desc) where is_visible;
create index if not exists ratings_booking_idx on public.ratings(booking_id);
alter table public.ratings enable row level security;
revoke all on public.ratings from public,anon,authenticated;
grant select on public.ratings to authenticated;
create policy ratings_public_visible_read on public.ratings for select to authenticated using(is_visible);
create trigger set_updated_at before update on public.ratings for each row execute function public.set_updated_at();

create or replace function public.refresh_profile_rating()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 update public.profiles p set
  rating_count=(select count(*)::integer from public.ratings r where r.reviewee_id=new.reviewee_id and r.is_visible),
  rating_avg=coalesce((select round(avg(r.score)::numeric,2) from public.ratings r where r.reviewee_id=new.reviewee_id and r.is_visible),0)
 where p.id=new.reviewee_id;
 return new;
end $$;
revoke all on function public.refresh_profile_rating() from public,anon,authenticated;
create trigger rating_profile_summary after insert or update of is_visible,score on public.ratings for each row execute function public.refresh_profile_rating();

create or replace function public.submit_rating(p_booking_id uuid,p_score smallint,p_comment text default null)
returns public.ratings
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype; v_reviewee uuid; v_rating public.ratings%rowtype;
begin
 if v_user is null or p_score not between 1 and 5 or p_comment is not null and length(p_comment)>2000 then raise exception using errcode='22023',message='Valid rating and sign-in are required.'; end if;
 select * into v_booking from public.bookings where id=p_booking_id and status='completed';
 if not found then raise exception using errcode='22023',message='Only a completed booking can be rated.'; end if;
 select * into v_trip from public.trips where id=v_booking.trip_id;
 if v_user=v_booking.passenger_id then v_reviewee:=v_trip.driver_id;
 elsif v_user=v_trip.driver_id then v_reviewee:=v_booking.passenger_id;
 else raise exception using errcode='42501',message='Only trip participants can leave a rating.'; end if;
 insert into public.ratings(booking_id,reviewer_id,reviewee_id,score,comment)
 values(p_booking_id,v_user,v_reviewee,p_score,nullif(pg_catalog.btrim(p_comment),''))
 returning * into v_rating;
 return v_rating;
end $$;
revoke all on function public.submit_rating(uuid,smallint,text) from public,anon,authenticated;
grant execute on function public.submit_rating(uuid,smallint,text) to authenticated;

do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime')
  and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
  execute 'alter publication supabase_realtime add table public.messages';
 end if;
end $$;

commit;
