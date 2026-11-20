-- Module stock complet. Regle absolue : aucun stock negatif (verifie par trigger).
-- Nettoyage des objets de test de l'etape precedente (donnees de test uniquement).
drop view if exists gfe.stock_actuel;
drop table if exists gfe.mouvements_stock;
drop table if exists gfe.produits;

create table gfe.stock_articles (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  designation text not null,
  categorie text not null check (categorie in ('matiere','produit_fini')),
  unite text not null default 'unité',
  seuil numeric not null default 0 check (seuil >= 0),
  mode text not null default 'quantite' check (mode in ('lot','quantite')),
  created_at timestamptz not null default now(),
  unique (entreprise_id, designation)
);

create table gfe.points (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  nom text not null,
  type text not null check (type in ('usine','point_vente')),
  unique (entreprise_id, nom)
);

create table gfe.commerciaux (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  nom text not null,
  unique (entreprise_id, nom)
);

create table gfe.lots (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  article_id uuid not null references gfe.stock_articles(id) on delete cascade,
  numero text not null,
  unique (entreprise_id, article_id, numero)
);

create table gfe.productions (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  point_id uuid not null references gfe.points(id),
  article_id uuid not null references gfe.stock_articles(id),
  quantite numeric not null check (quantite > 0),
  date_production date not null default current_date,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table gfe.production_lignes (
  id uuid primary key default gen_random_uuid(),
  production_id uuid not null references gfe.productions(id) on delete cascade,
  article_id uuid not null references gfe.stock_articles(id),
  lot_id uuid references gfe.lots(id),
  quantite numeric check (quantite is null or quantite > 0)
);

create table gfe.mouvements (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  article_id uuid not null references gfe.stock_articles(id) on delete cascade,
  type text not null check (type in ('stock_initial','entree','sortie','vente','production','consommation')),
  quantite numeric not null check (quantite > 0),
  prix_unitaire numeric check (prix_unitaire is null or prix_unitaire >= 0),
  lot_id uuid references gfe.lots(id) on delete cascade,
  point_id uuid references gfe.points(id),
  commercial_id uuid references gfe.commerciaux(id),
  production_id uuid references gfe.productions(id) on delete cascade,
  date_mouvement date not null default current_date,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (type <> 'vente' or (commercial_id is not null and point_id is not null and prix_unitaire is not null)),
  check (type <> 'production' or production_id is not null),
  check (type <> 'consommation' or production_id is not null)
);

-- Regle absolue : le stock ne peut jamais devenir negatif
create or replace function gfe.verifier_stock_positif() returns trigger
language plpgsql security definer set search_path = gfe, public as $$
declare s numeric;
begin
  perform pg_advisory_xact_lock(hashtext(new.article_id::text));
  select coalesce(sum(case when type in ('stock_initial','entree','production') then quantite
                           else -quantite end), 0) into s
  from gfe.mouvements where article_id = new.article_id;
  if s < 0 then
    raise exception 'Opération refusée : stock négatif interdit (stock résultant : %)', s;
  end if;
  return new;
end $$;

create trigger mouvements_stock_positif after insert on gfe.mouvements
  for each row execute function gfe.verifier_stock_positif();

-- Fabrication : une seule transaction (tout ou rien)
create or replace function gfe.enregistrer_production(
  p_entreprise uuid, p_point uuid, p_article uuid, p_quantite numeric,
  p_date date, p_lignes jsonb)
returns uuid language plpgsql security definer set search_path = gfe, public as $$
declare
  pid uuid; l jsonb; a gfe.stock_articles; pt gfe.points;
  lid uuid; q numeric; n int := 0; deja boolean; d date := coalesce(p_date, current_date);
begin
  if not gfe.peut_ecrire(p_entreprise) then raise exception 'Droits insuffisants'; end if;
  select * into pt from gfe.points where id = p_point and entreprise_id = p_entreprise;
  if pt.id is null or pt.type <> 'usine' then raise exception 'La production se fait uniquement dans une usine'; end if;
  select * into a from gfe.stock_articles where id = p_article and entreprise_id = p_entreprise;
  if a.id is null or a.categorie <> 'produit_fini' then raise exception 'Produit fini invalide'; end if;
  if p_quantite is null or p_quantite <= 0 then raise exception 'Quantité produite invalide'; end if;
  if p_lignes is null or jsonb_array_length(p_lignes) = 0 then raise exception 'Au moins une matière est nécessaire'; end if;
  if jsonb_array_length(p_lignes) > 8 then raise exception 'Maximum 8 matières par fabrication'; end if;

  insert into gfe.productions (entreprise_id, point_id, article_id, quantite, date_production, created_by)
  values (p_entreprise, p_point, p_article, p_quantite, d, auth.uid()) returning id into pid;
  insert into gfe.mouvements (entreprise_id, article_id, type, quantite, production_id, date_mouvement, created_by)
  values (p_entreprise, p_article, 'production', p_quantite, pid, d, auth.uid());

  for l in select * from jsonb_array_elements(p_lignes) loop
    n := n + 1;
    select * into a from gfe.stock_articles where id = (l->>'article_id')::uuid and entreprise_id = p_entreprise;
    if a.id is null or a.categorie <> 'matiere' then raise exception 'Ligne % : matière invalide', n; end if;
    q := nullif(l->>'quantite', '')::numeric;
    lid := null;
    if a.mode = 'lot' then
      if nullif(l->>'lot', '') is null then raise exception 'Ligne % : numéro de lot obligatoire', n; end if;
      insert into gfe.lots (entreprise_id, article_id, numero)
      values (p_entreprise, a.id, l->>'lot') on conflict (entreprise_id, article_id, numero) do nothing;
      select id into lid from gfe.lots where entreprise_id = p_entreprise and article_id = a.id and numero = l->>'lot';
      select exists(select 1 from gfe.mouvements where lot_id = lid and type = 'consommation') into deja;
      if not deja then
        if q is null or q <= 0 then raise exception 'Ligne % : quantité du lot à saisir la 1re fois', n; end if;
        insert into gfe.mouvements (entreprise_id, article_id, type, quantite, lot_id, production_id, date_mouvement, created_by)
        values (p_entreprise, a.id, 'consommation', q, lid, pid, d, auth.uid());
      else
        q := null; -- lot déjà prélevé : quantité non saisie, pas de double comptage
      end if;
    else
      if q is null or q <= 0 then raise exception 'Ligne % : quantité obligatoire', n; end if;
      insert into gfe.mouvements (entreprise_id, article_id, type, quantite, production_id, date_mouvement, created_by)
      values (p_entreprise, a.id, 'consommation', q, pid, d, auth.uid());
    end if;
    insert into gfe.production_lignes (production_id, article_id, lot_id, quantite)
    values (pid, a.id, lid, q);
  end loop;
  return pid;
end $$;

-- Stock actuel et alerte par article (respecte RLS)
create or replace view gfe.stock_articles_vue with (security_invoker = true) as
select a.id as article_id, a.entreprise_id, a.designation, a.categorie, a.unite, a.seuil, a.mode,
       s.stock, (s.stock <= a.seuil) as alerte
from gfe.stock_articles a
left join lateral (
  select coalesce(sum(case when m.type in ('stock_initial','entree','production') then m.quantite
                           when m.type in ('sortie','vente','consommation') then -m.quantite
                           else 0 end), 0) as stock
  from gfe.mouvements m where m.article_id = a.id
) s on true;

-- Rapport des ventes par période, commercial et point (membres seulement)
create or replace function gfe.rapport_ventes(p_entreprise uuid, p_debut date, p_fin date,
  p_commercial uuid default null, p_point uuid default null)
returns table(date_mouvement date, commercial text, point text, article text, quantite numeric, prix_unitaire numeric, montant numeric)
language sql stable security definer set search_path = gfe, public as $$
  select m.date_mouvement, c.nom, p.nom, a.designation, m.quantite, m.prix_unitaire, m.quantite * m.prix_unitaire
  from gfe.mouvements m
  join gfe.commerciaux c on c.id = m.commercial_id
  join gfe.points p on p.id = m.point_id
  join gfe.stock_articles a on a.id = m.article_id
  where gfe.est_membre(p_entreprise) and m.entreprise_id = p_entreprise and m.type = 'vente'
    and m.date_mouvement between p_debut and p_fin
    and (p_commercial is null or m.commercial_id = p_commercial)
    and (p_point is null or m.point_id = p_point)
  order by m.date_mouvement, c.nom;
$$;

-- RLS
alter table gfe.stock_articles enable row level security;
alter table gfe.points enable row level security;
alter table gfe.commerciaux enable row level security;
alter table gfe.lots enable row level security;
alter table gfe.productions enable row level security;
alter table gfe.production_lignes enable row level security;
alter table gfe.mouvements enable row level security;

create policy "lit articles" on gfe.stock_articles for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "ecrit articles" on gfe.stock_articles for insert to authenticated with check (gfe.peut_ecrire(entreprise_id));
create policy "modifie articles" on gfe.stock_articles for update to authenticated using (gfe.peut_ecrire(entreprise_id)) with check (gfe.peut_ecrire(entreprise_id));
create policy "lit points" on gfe.points for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "ecrit points" on gfe.points for insert to authenticated with check (gfe.peut_ecrire(entreprise_id));
create policy "lit commerciaux" on gfe.commerciaux for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "ecrit commerciaux" on gfe.commerciaux for insert to authenticated with check (gfe.peut_ecrire(entreprise_id));
create policy "lit lots" on gfe.lots for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "lit productions" on gfe.productions for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "lit lignes" on gfe.production_lignes for select to authenticated using (exists (select 1 from gfe.productions p where p.id = production_id and gfe.est_membre(p.entreprise_id)));
create policy "lit mouvements" on gfe.mouvements for select to authenticated using (gfe.est_membre(entreprise_id));
-- Saisie directe : seulement les types manuels (la production passe par la fonction)
create policy "ecrit mouvements manuels" on gfe.mouvements for insert to authenticated
  with check (gfe.peut_ecrire(entreprise_id) and created_by = auth.uid() and type in ('stock_initial','entree','sortie','vente'));

grant usage on schema gfe to authenticated;
grant select on all tables in schema gfe to authenticated;
grant insert on gfe.stock_articles, gfe.points, gfe.commerciaux, gfe.mouvements to authenticated;
grant update on gfe.stock_articles to authenticated;
grant select on gfe.stock_articles_vue to authenticated;
revoke all on function gfe.enregistrer_production(uuid, uuid, uuid, numeric, date, jsonb) from public, anon;
grant execute on function gfe.enregistrer_production(uuid, uuid, uuid, numeric, date, jsonb) to authenticated;
grant execute on function gfe.rapport_ventes(uuid, date, date, uuid, uuid) to authenticated;
