-- Socle commun GFE (schéma séparé "gfe"). Ne touche pas au schéma public.
create schema if not exists gfe;

-- Entreprises clientes
create table if not exists gfe.entreprises (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  created_at timestamptz not null default now()
);

-- Profil lié à un compte d'authentification
create table if not exists gfe.profils (
  id uuid primary key references auth.users(id) on delete cascade,
  nom text,
  created_at timestamptz not null default now()
);

-- Appartenance d'un utilisateur à une entreprise, avec son rôle
create table if not exists gfe.appartenances (
  profil_id uuid not null references gfe.profils(id) on delete cascade,
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  role text not null check (role in ('admin','utilisateur','lecture')),
  primary key (profil_id, entreprise_id)
);

-- Modules activés par entreprise (stock, comptabilite, rh_paie)
create table if not exists gfe.modules_actifs (
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  module text not null check (module in ('stock','comptabilite','rh_paie')),
  actif boolean not null default true,
  primary key (entreprise_id, module)
);

-- Sécurité par ligne : chacun ne voit que ses entreprises
alter table gfe.entreprises enable row level security;
alter table gfe.profils enable row level security;
alter table gfe.appartenances enable row level security;
alter table gfe.modules_actifs enable row level security;

create or replace function gfe.est_membre(eid uuid)
returns boolean language sql stable security definer set search_path = gfe, public as $$
  select exists (select 1 from gfe.appartenances a where a.entreprise_id = eid and a.profil_id = auth.uid());
$$;

create policy "membre voit son entreprise" on gfe.entreprises for select to authenticated
  using (gfe.est_membre(id));
create policy "membre voit son profil" on gfe.profils for select to authenticated
  using (id = auth.uid());
create policy "membre voit ses appartenances" on gfe.appartenances for select to authenticated
  using (profil_id = auth.uid());
create policy "membre voit les modules de son entreprise" on gfe.modules_actifs for select to authenticated
  using (gfe.est_membre(entreprise_id));
