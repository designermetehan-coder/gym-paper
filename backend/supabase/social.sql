-- GYM Paper · Sosyal (arkadaşlarla adım sıralaması) · 1 Kas 2026
-- Hesap yok: cihaz kendi rastgele kimliğini ve gizli anahtarını üretir (anahtar sunucuda yalnız özet olarak durur).
-- Tablolara doğrudan erişim kapalı (RLS açık, politika yok); her şey aşağıdaki RPC'lerden geçer.
-- Paylaşılan tek sağlık verisi: günlük adım sayısı. Kilo, ölçü, beslenme, oruç hiç gönderilmez.
-- Tekrar çalıştırılabilir.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.so_users (
  id uuid primary key default gen_random_uuid(),
  secret_hash text not null,
  name text not null check (char_length(name) between 1 and 24),
  code text not null unique,
  created_at timestamptz not null default now(),
  seen_at timestamptz not null default now()
);
create table if not exists public.so_steps (
  user_id uuid not null references public.so_users(id) on delete cascade,
  day date not null,
  steps integer not null check (steps between 0 and 200000),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);
create table if not exists public.so_friends (
  a uuid not null references public.so_users(id) on delete cascade,
  b uuid not null references public.so_users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (a, b),
  check (a <> b)
);
create index if not exists so_friends_b on public.so_friends(b);
alter table public.so_users enable row level security;
alter table public.so_steps enable row level security;
alter table public.so_friends enable row level security;
revoke all on public.so_users, public.so_steps, public.so_friends from anon, authenticated;

-- Kimlik doğrulama yardımcısı
create or replace function public.so_auth(p_id uuid, p_secret text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists(select 1 from so_users u where u.id = p_id and u.secret_hash = crypt(p_secret, u.secret_hash));
$$;
revoke all on function public.so_auth(uuid, text) from public, anon, authenticated;

-- Kayıt: görünen ad → kimlik, anahtar, davet kodu
create or replace function public.so_register(p_name text)
returns table(id uuid, secret text, code text)
language plpgsql security definer set search_path = public, extensions as $$
declare v_secret text := encode(gen_random_bytes(24), 'hex'); v_code text; v_id uuid;
begin
  if char_length(trim(p_name)) not between 1 and 24 then raise exception 'name'; end if;
  loop
    -- Karışmayan harf/rakamlar (0/O, 1/I yok)
    v_code := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random()*32)::int, 1), '') from generate_series(1,6));
    exit when not exists(select 1 from so_users u where u.code = v_code);
  end loop;
  insert into so_users(secret_hash, name, code) values (crypt(v_secret, gen_salt('bf')), trim(p_name), v_code) returning so_users.id into v_id;
  return query select v_id, v_secret, v_code;
end $$;

-- Adım gönder (son 14 gün; yalnız artar ya da aynı gün düzeltilir)
create or replace function public.so_push_steps(p_id uuid, p_secret text, p_days jsonb)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare r record;
begin
  if not so_auth(p_id, p_secret) then raise exception 'auth'; end if;
  for r in select key::date as d, value::int as s from jsonb_each_text(p_days) loop
    if r.d between current_date - 14 and current_date + 1 and r.s between 0 and 200000 then
      insert into so_steps(user_id, day, steps) values (p_id, r.d, r.s)
      on conflict (user_id, day) do update set steps = greatest(so_steps.steps, excluded.steps), updated_at = now();
    end if;
  end loop;
  update so_users set seen_at = now() where id = p_id;
end $$;

-- Arkadaş ekle (davet koduyla, karşılıklı)
create or replace function public.so_add_friend(p_id uuid, p_secret text, p_code text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare f so_users;
begin
  if not so_auth(p_id, p_secret) then raise exception 'auth'; end if;
  select * into f from so_users where code = upper(trim(p_code));
  if f.id is null then raise exception 'code'; end if;
  if f.id = p_id then raise exception 'self'; end if;
  if (select count(*) from so_friends where a = p_id) >= 100 then raise exception 'limit'; end if;
  insert into so_friends(a, b) values (p_id, f.id), (f.id, p_id) on conflict do nothing;
  return f.name;
end $$;

-- Arkadaşlıktan çıkar (iki yönlü; yeniden eklemek yeni kod ister)
create or replace function public.so_remove_friend(p_id uuid, p_secret text, p_friend uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not so_auth(p_id, p_secret) then raise exception 'auth'; end if;
  delete from so_friends where (a = p_id and b = p_friend) or (a = p_friend and b = p_id);
end $$;

-- Görünen adı değiştir
create or replace function public.so_rename(p_id uuid, p_secret text, p_name text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not so_auth(p_id, p_secret) then raise exception 'auth'; end if;
  if char_length(trim(p_name)) not between 1 and 24 then raise exception 'name'; end if;
  update so_users set name = trim(p_name) where id = p_id;
end $$;

-- Davet kodunu yenile (eski kod artık çalışmaz)
create or replace function public.so_new_code(p_id uuid, p_secret text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare v_code text;
begin
  if not so_auth(p_id, p_secret) then raise exception 'auth'; end if;
  loop
    v_code := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random()*32)::int, 1), '') from generate_series(1,6));
    exit when not exists(select 1 from so_users u where u.code = v_code);
  end loop;
  update so_users set code = v_code where id = p_id;
  return v_code;
end $$;

-- Sıralama: ben + arkadaşlarım; bugün, bu hafta (p_from..p_to) ve 7 günlük dizi
create or replace function public.so_board(p_id uuid, p_secret text, p_today date, p_from date)
returns table(user_id uuid, name text, is_me boolean, today integer, week integer, days jsonb)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not so_auth(p_id, p_secret) then raise exception 'auth'; end if;
  return query
  with people as (
    select p_id as uid union select b from so_friends where a = p_id
  )
  select u.id, u.name, u.id = p_id,
         coalesce((select s.steps from so_steps s where s.user_id = u.id and s.day = p_today), 0),
         coalesce((select sum(s.steps)::int from so_steps s where s.user_id = u.id and s.day between p_from and p_today), 0),
         coalesce((select jsonb_object_agg(s.day::text, s.steps) from so_steps s where s.user_id = u.id and s.day between p_from - 6 and p_today), '{}'::jsonb)
  from people p join so_users u on u.id = p.uid;
end $$;

-- Paylaşımı durdur: kişinin tüm verisi silinir
create or replace function public.so_delete(p_id uuid, p_secret text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not so_auth(p_id, p_secret) then raise exception 'auth'; end if;
  delete from so_users where id = p_id;
end $$;

grant execute on function public.so_register(text), public.so_push_steps(uuid, text, jsonb), public.so_add_friend(uuid, text, text),
  public.so_remove_friend(uuid, text, uuid), public.so_rename(uuid, text, text), public.so_new_code(uuid, text),
  public.so_board(uuid, text, date, date), public.so_delete(uuid, text) to anon;
