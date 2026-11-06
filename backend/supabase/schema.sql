-- Ballı · Supabase şeması (canlı projeyle eşit, 22.10.2026). Tekrar çalıştırılabilir.

-- Veri (tek JSON, kullanıcı başına)
create table if not exists public.balli_data (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_key text not null default 'main',
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_key)
);
alter table public.balli_data enable row level security;
drop policy if exists balli_data_select_own on public.balli_data;
drop policy if exists balli_data_insert_own on public.balli_data;
drop policy if exists balli_data_update_own on public.balli_data;
drop policy if exists balli_data_delete_own on public.balli_data;
create policy balli_data_select_own on public.balli_data for select to authenticated using ((select auth.uid()) = user_id);
create policy balli_data_insert_own on public.balli_data for insert to authenticated with check ((select auth.uid()) = user_id);
create policy balli_data_update_own on public.balli_data for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy balli_data_delete_own on public.balli_data for delete to authenticated using ((select auth.uid()) = user_id);

-- Görseller (kullanıcı klasörü: <uid>/img-*.jpg), 2 MB, yalnız görsel
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('balli-images', 'balli-images', false, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists balli_images_select_own on storage.objects;
drop policy if exists balli_images_insert_own on storage.objects;
drop policy if exists balli_images_update_own on storage.objects;
create policy balli_images_select_own on storage.objects for select to authenticated using (bucket_id = 'balli-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy balli_images_insert_own on storage.objects for insert to authenticated with check (bucket_id = 'balli-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy balli_images_update_own on storage.objects for update to authenticated using (bucket_id = 'balli-images' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Adım otomasyonu (iOS Kestirmeler → functions/v1/steps)
create extension if not exists pgcrypto;
create table if not exists public.balli_step_tokens (
  token text primary key default encode(extensions.gen_random_bytes(18), 'hex'),
  user_id uuid not null unique references auth.users(id) on delete cascade default auth.uid(),
  created_at timestamptz not null default now()
);
alter table public.balli_step_tokens enable row level security;
drop policy if exists step_tokens_select_own on public.balli_step_tokens;
drop policy if exists step_tokens_insert_own on public.balli_step_tokens;
drop policy if exists step_tokens_delete_own on public.balli_step_tokens;
create policy step_tokens_select_own on public.balli_step_tokens for select to authenticated using ((select auth.uid()) = user_id);
create policy step_tokens_insert_own on public.balli_step_tokens for insert to authenticated with check ((select auth.uid()) = user_id);
create policy step_tokens_delete_own on public.balli_step_tokens for delete to authenticated using ((select auth.uid()) = user_id);

create table if not exists public.balli_steps (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  steps integer not null check (steps between 0 and 300000),
  updated_at timestamptz not null default now(),
  primary key (user_id, date)
);
alter table public.balli_steps enable row level security;
drop policy if exists steps_select_own on public.balli_steps;
create policy steps_select_own on public.balli_steps for select to authenticated using ((select auth.uid()) = user_id);

-- Hata kaydı (kişisel veri yok; yalnız yazılabilir)
create table if not exists public.balli_errors (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  msg text not null check (length(msg) <= 1000),
  stack text check (length(stack) <= 4000),
  ua text check (length(ua) <= 200),
  ver text check (length(ver) <= 40)
);
alter table public.balli_errors enable row level security;
drop policy if exists errors_insert_any on public.balli_errors;
create policy errors_insert_any on public.balli_errors for insert to anon, authenticated with check (true);
