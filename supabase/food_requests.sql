-- GYM Paper · Eksik besin bildirimi · 8 Kas 2026
-- Aramada bulunamayan besin adı (yalnız sorgu metni) sayılır; kimlik, cihaz ya da sağlık verisi gönderilmez.
-- Tabloya doğrudan erişim kapalı; yalnız fd_request RPC'si yazar. Tekrar çalıştırılabilir.

create table if not exists public.fd_requests (
  norm text primary key check (char_length(norm) between 2 and 80),
  sample text not null check (char_length(sample) between 2 and 80),
  hits integer not null default 1,
  first_at timestamptz not null default now(),
  last_at timestamptz not null default now()
);
alter table public.fd_requests enable row level security;
revoke all on public.fd_requests from anon, authenticated;

create or replace function public.fd_request(p_q text, p_norm text) returns void
language plpgsql security definer set search_path = public as $$
declare q text := left(btrim(coalesce(p_q, '')), 80); n text := left(btrim(coalesce(p_norm, '')), 80);
begin
  if char_length(n) < 2 or char_length(q) < 2 then raise exception 'short'; end if;
  insert into fd_requests(norm, sample) values (n, q)
  on conflict (norm) do update set hits = least(fd_requests.hits + 1, 1000000), last_at = now();
end $$;
revoke all on function public.fd_request(text, text) from public;
grant execute on function public.fd_request(text, text) to anon;

-- En çok istenenler: select sample, hits, last_at from fd_requests order by hits desc, last_at desc limit 100;
