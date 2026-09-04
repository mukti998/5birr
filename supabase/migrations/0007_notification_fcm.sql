-- 5BIRR Phase 2 — Notification Foundation & n8n Integration
-- Migration 0007_notification_fcm.sql
-- FCM token storage, notification read functions, n8n webhook events.

-- =========================================================
-- 1. FCM TOKEN STORAGE
-- =========================================================

create table if not exists fcm_tokens (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  device_type text not null default 'android' check (device_type in ('android','ios','web')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

create index idx_fcm_tokens_user on fcm_tokens(user_id);
create index idx_fcm_tokens_active on fcm_tokens(is_active) where is_active = true;

alter table fcm_tokens enable row level security;

create policy fcm_tokens_owner_all on fcm_tokens for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy fcm_tokens_admin_all on fcm_tokens for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- 2. NOTIFICATION READ FUNCTION
-- =========================================================

create or replace function mark_notification_read(
  p_notification_id uuid
) returns notifications
language plpgsql
security definer
as $$
declare
  v_notification notifications;
begin
  update notifications
  set is_read = true
  where id = p_notification_id and user_id = auth.uid()
  returning * into v_notification;

  if v_notification.id is null then
    raise exception 'NOTIFICATION_NOT_FOUND_OR_UNAUTHORIZED';
  end if;

  return v_notification;
end;
$$;

create or replace function mark_all_notifications_read()
returns int
language plpgsql
security definer
as $$
declare
  v_count int;
begin
  update notifications
  set is_read = true
  where user_id = auth.uid() and is_read = false;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- =========================================================
-- 3. NOTIFICATION PREFERENCES UPDATE
-- =========================================================

create or replace function upsert_notification_preferences(
  p_push_enabled boolean default null,
  p_in_app_enabled boolean default null
) returns notification_preferences
language plpgsql
security definer
as $$
declare
  v_prefs notification_preferences;
begin
  insert into notification_preferences (user_id, push_enabled, in_app_enabled)
  values (auth.uid(),
          coalesce(p_push_enabled, true),
          coalesce(p_in_app_enabled, true))
  on conflict (user_id) do update set
    push_enabled = coalesce(p_push_enabled, notification_preferences.push_enabled),
    in_app_enabled = coalesce(p_in_app_enabled, notification_preferences.in_app_enabled)
  returning * into v_prefs;

  return v_prefs;
end;
$$;

-- =========================================================
-- 4. N8N WEBHOOK EVENT ARCHITECTURE
--    Table to track n8n workflow executions and events.
-- =========================================================

create table if not exists n8n_events (
  id uuid primary key default uuid_generate_v4(),
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  payload jsonb,
  status text not null default 'PENDING' check (status in ('PENDING','SENT','FAILED','RETRYING')),
  attempts int not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index idx_n8n_events_status on n8n_events(status);
create index idx_n8n_events_type on n8n_events(event_type, entity_type);
create index idx_n8n_events_entity on n8n_events(entity_type, entity_id);

alter table n8n_events enable row level security;
-- n8n_events is admin/service-role only
create policy n8n_events_admin_only on n8n_events for all
  using (is_admin()) with check (is_admin());

-- =========================================================
-- 5. FUNCTION TO CREATE N8N EVENT (called by other functions)
-- =========================================================

create or replace function create_n8n_event(
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_payload jsonb default null
) returns n8n_events
language plpgsql
security definer
as $$
declare
  v_event n8n_events;
begin
  insert into n8n_events (event_type, entity_type, entity_id, payload)
  values (p_event_type, p_entity_type, p_entity_id, p_payload)
  returning * into v_event;

  return v_event;
end;
$$;

-- =========================================================
-- 6. ENHANCED PROVIDER APPROVAL: also create n8n event
-- =========================================================

-- Patch approve_provider to also create n8n event for notification orchestration
create or replace function approve_provider(
  p_provider_id uuid,
  p_admin_id uuid
) returns provider_profiles
language plpgsql
security definer
as $$
declare
  v_provider provider_profiles;
  v_is_admin boolean;
begin
  select exists (
    select 1 from user_roles
    where user_id = p_admin_id and role = 'ADMIN'
  ) into v_is_admin;

  if not v_is_admin then
    raise exception 'ONLY_ADMINISTRATORS_CAN_APPROVE_PROVIDERS';
  end if;

  if exists (
    select 1 from provider_profiles
    where id = p_provider_id and user_id = p_admin_id
  ) then
    raise exception 'ADMINISTRATORS_CANNOT_APPROVE_THEIR_OWN_PROVIDER_ACCOUNT';
  end if;

  update provider_profiles set status = 'APPROVED', updated_at = now()
  where id = p_provider_id
  returning * into v_provider;

  if v_provider.id is null then
    raise exception 'PROVIDER_NOT_FOUND';
  end if;

  insert into wallets (provider_id, balance) values (p_provider_id, 0)
  on conflict (provider_id) do nothing;

  insert into subscriptions (provider_id, next_due_date)
  values (p_provider_id, v_provider.subscription_start_date)
  on conflict (provider_id) do nothing;

  insert into approval_history (subject_type, subject_id, action, performed_by)
  values ('PROVIDER', p_provider_id, 'APPROVE', p_admin_id);

  insert into notifications (user_id, type, title, body)
  select user_id, 'APPROVAL', 'Application approved', 'Your provider account is now active.'
  from provider_profiles where id = p_provider_id;

  insert into admin_actions (admin_id, action, target_type, target_id)
  values (p_admin_id, 'APPROVE_PROVIDER', 'provider_profiles', p_provider_id);

  -- n8n event for external notification orchestration
  perform create_n8n_event('PROVIDER_APPROVED', 'provider_profiles', p_provider_id,
    jsonb_build_object('provider_id', p_provider_id, 'admin_id', p_admin_id));

  return v_provider;
end;
$$;

-- =========================================================
-- 7. UPDATE SUBSCRIPTION PROCESS TO CREATE N8N EVENTS
-- =========================================================

-- The subscription-process Edge Function already handles notifications.
-- We just ensure n8n_events are created for orchestration.
