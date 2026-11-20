-- Module stock : produits et mouvements, par entreprise. Accès via RLS.
create table if not exists gfe.produits (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  designation text not null,
  unite text not null default 'unité',
  seuil numeric not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists gfe.mouvements_stock (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  produit_id uuid not null references gfe.produits(id) on delete cascade,
  type text not null check (type in ('entree','sortie','ajustement')),
  quantite numeric not null check (quantite >= 0),
  note text,
  date_mouvement date not null default current_date,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table gfe.produits enable row level security;
alter table gfe.mouvements_stock enable row level security;

-- Lecture : tout membre de l'entreprise
create policy "membre lit produits" on gfe.produits for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "membre lit mouvements" on gfe.mouvements_stock for select to authenticated using (gfe.est_membre(entreprise_id));

-- Écriture : admin ou utilisateur de l'entreprise (pas le rôle lecture)
create or replace function gfe.peut_ecrire(eid uuid)
returns boolean language sql stable security definer set search_path = gfe, public as $$
  select exists (select 1 from gfe.appartenances a where a.entreprise_id = eid and a.profil_id = auth.uid() and a.role in ('admin','utilisateur'));
$$;

create policy "ecrit produits" on gfe.produits for insert to authenticated with check (gfe.peut_ecrire(entreprise_id));
create policy "modifie produits" on gfe.produits for update to authenticated using (gfe.peut_ecrire(entreprise_id)) with check (gfe.peut_ecrire(entreprise_id));
create policy "ecrit mouvements" on gfe.mouvements_stock for insert to authenticated with check (gfe.peut_ecrire(entreprise_id) and created_by = auth.uid());

-- Stock actuel par produit (vue qui respecte les droits de l'utilisateur)
create or replace view gfe.stock_actuel with (security_invoker = true) as
select p.id as produit_id, p.entreprise_id, p.designation, p.unite, p.seuil,
  coalesce(sum(case when m.type='entree' then m.quantite
                    when m.type='sortie' then -m.quantite
                    else 0 end), 0) as stock
from gfe.produits p
left join gfe.mouvements_stock m on m.produit_id = p.id
group by p.id;

grant select, insert, update on gfe.produits to authenticated;
grant select, insert on gfe.mouvements_stock to authenticated;
grant select on gfe.stock_actuel to authenticated;
