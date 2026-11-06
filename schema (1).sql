-- DNT VOLUNTEER HUB - schema Supabase (ruleaza in SQL Editor)
create table public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  nume text, prenume text, email text,
  role text not null default 'voluntar' check (role in ('voluntar','board','admin')),
  status text not null default 'in_asteptare' check (status in ('in_asteptare','activ','suspendat')),
  created_at timestamptz default now());

create or replace function public.is_board() returns boolean
language sql security definer set search_path=public stable as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role in ('board','admin') and status='activ') $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,nume,prenume,email)
  values(new.id,new.raw_user_meta_data->>'nume',new.raw_user_meta_data->>'prenume',new.email);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
create policy "vede propriul profil sau board" on public.profiles for select using (id=auth.uid() or public.is_board());
create policy "doar board modifica profile" on public.profiles for update using (public.is_board()) with check (public.is_board());

-- Filiale si documente: DOAR board
create table public.branches(id uuid primary key default gen_random_uuid(), name text not null, judet text, status text, created_at timestamptz default now());
create table public.documents(id uuid primary key default gen_random_uuid(), titlu text not null, categorie text, nr_inreg text, data date, fisier_url text, created_by uuid references public.profiles(id), created_at timestamptz default now());
alter table public.branches enable row level security;
alter table public.documents enable row level security;
create policy "board filiale" on public.branches for all using (public.is_board()) with check (public.is_board());
create policy "board documente" on public.documents for all using (public.is_board()) with check (public.is_board());

-- Ore: voluntarul vede/adauga doar ale lui (nevalidate); board valideaza
create table public.volunteer_hours(id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id), data date not null, proiect text not null, ore numeric not null check (ore>0), coordonator text, validat boolean not null default false, created_at timestamptz default now());
alter table public.volunteer_hours enable row level security;
create policy "ore: citire proprii sau board" on public.volunteer_hours for select using (user_id=auth.uid() or public.is_board());
create policy "ore: adaugare proprii" on public.volunteer_hours for insert with check (user_id=auth.uid() and validat=false);
create policy "ore: board modifica" on public.volunteer_hours for update using (public.is_board());
create policy "ore: board sterge" on public.volunteer_hours for delete using (public.is_board());

-- Audit: oricine autentificat scrie, doar board citeste, nimeni nu modifica/sterge
create table public.audit_logs(id bigint generated always as identity primary key, user_id uuid default auth.uid(), actiune text not null, created_at timestamptz default now());
alter table public.audit_logs enable row level security;
create policy "audit: scriere" on public.audit_logs for insert with check (user_id=auth.uid());
create policy "audit: citire board" on public.audit_logs for select using (public.is_board());
