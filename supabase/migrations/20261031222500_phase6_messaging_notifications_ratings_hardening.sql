-- Phase 6, steps 15-17 follow-up: apply chat retention to reads/Realtime,
-- honor push preferences, and keep rating aggregates correct when moderated.

-- Push is separate from the in-app notification inbox, so give message pushes
-- their own preference and retain existing users' current opt-in behavior.
alter table public.notification_preferences
  add column if not exists message_updates boolean not null default true;
grant update (message_updates) on public.notification_preferences to authenticated;

alter table public.notifications drop constraint if exists notifications_category_check;
alter table public.notifications add constraint notifications_category_check
  check (category in ('booking', 'trip', 'message', 'safety', 'support', 'account', 'marketing'));

-- Reads and Realtime visibility must follow the same booking/trip window as send_message.
drop policy if exists messages_participant_read on public.messages;
create policy messages_participant_read on public.messages
for select to authenticated
using (
  exists (
    select 1
    from public.conversations c
    join public.bookings b on b.id = c.booking_id
    join public.trips t on t.id = c.trip_id
    where c.id = messages.conversation_id
      and c.booking_id = messages.booking_id
      and (c.rider_id = (select auth.uid()) or c.driver_id = (select auth.uid()))
      and b.status in ('confirmed', 'completed')
      and t.status <> 'cancelled'
      and (
        t.status <> 'completed'
        or t.arrival_time is null
        or pg_catalog.now() <= t.arrival_time + pg_catalog.make_interval(days => coalesce(
          (select (s.value #>> '{}')::integer from public.app_settings s where s.key = 'chat_retention_days_after_trip'),
          30
        ))
      )
  )
);

-- Always store the in-app notification. Queue a push only when both the global
-- push switch and the matching category preference are enabled.
create or replace function public.enqueue_notification(
  p_recipient uuid,
  p_category text,
  p_event text,
  p_title jsonb,
  p_body jsonb,
  p_data jsonb,
  p_key text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_push_enabled boolean;
  v_category_enabled boolean;
begin
  if p_recipient is null or (p_recipient = auth.uid() and p_event = 'new_message') then
    return;
  end if;

  insert into public.notifications(recipient_id, category, title, body, data, idempotency_key)
  values (p_recipient, p_category, p_title, p_body, coalesce(p_data, '{}'::jsonb), p_key)
  on conflict (idempotency_key) do nothing;

  select coalesce(np.push_enabled, true),
         case p_category
           when 'booking' then coalesce(np.booking_updates, true)
           when 'trip' then coalesce(np.trip_updates, true)
           when 'message' then coalesce(np.message_updates, true)
           when 'safety' then coalesce(np.safety_alerts, true)
           when 'support' then coalesce(np.support_updates, true)
           when 'marketing' then coalesce(np.marketing_messages, true)
           when 'account' then true
           else false
         end
    into v_push_enabled, v_category_enabled
  from (select 1) seed
  left join public.notification_preferences np on np.user_id = p_recipient;

  if v_push_enabled and v_category_enabled then
    insert into public.notification_outbox(recipient_id, category, event_type, payload, idempotency_key)
    values (p_recipient, p_category, p_event, coalesce(p_data, '{}'::jsonb), p_key)
    on conflict (idempotency_key) do nothing;
  end if;
end;
$$;
revoke all on function public.enqueue_notification(uuid, text, text, jsonb, jsonb, jsonb, text) from public, anon, authenticated;

-- Keep profile rating averages/counts correct for inserts, moderation changes,
-- reassignment, or deletion of a rating.
create or replace function public.refresh_profile_rating_after_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' or (tg_op = 'UPDATE' and old.reviewee_id is distinct from new.reviewee_id) then
    update public.profiles p
    set rating_count = (select count(*)::integer from public.ratings r where r.reviewee_id = old.reviewee_id and r.is_visible),
        rating_avg = coalesce((select round(avg(r.score)::numeric, 2) from public.ratings r where r.reviewee_id = old.reviewee_id and r.is_visible), 0)
    where p.id = old.reviewee_id;
  end if;

  if tg_op <> 'DELETE' then
    update public.profiles p
    set rating_count = (select count(*)::integer from public.ratings r where r.reviewee_id = new.reviewee_id and r.is_visible),
        rating_avg = coalesce((select round(avg(r.score)::numeric, 2) from public.ratings r where r.reviewee_id = new.reviewee_id and r.is_visible), 0)
    where p.id = new.reviewee_id;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.refresh_profile_rating_after_change() from public, anon, authenticated;
drop trigger if exists rating_profile_summary on public.ratings;
create trigger rating_profile_summary
after insert or update of is_visible, score, reviewee_id or delete on public.ratings
for each row execute function public.refresh_profile_rating_after_change();

-- The notification inbox is user-owned under RLS; enable it for live inbox updates.
do $$
begin
  if exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_catalog.pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
     ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end;
$$;

