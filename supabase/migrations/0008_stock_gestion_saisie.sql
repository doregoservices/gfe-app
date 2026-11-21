-- 0008 : module stock fidèle au modèle Drive « stock universel v4 »
--   GESTION (comptable) = référentiel, nomenclature, stock, points, journaux
--   SAISIE  (client)    = PRODUCTION, VENTE, ACHAT, AUTRES, avec colonne Contrôle
-- Seules les lignes OK alimentent le stock (table mouvements_stock).
-- Règle absolue : aucun stock négatif, à aucune date (contrôle à chaque saisie).
-- Les données du module précédent (0005) étaient des données de test : remplacées.

-- 0) Nettoyage du module précédent
do $$ declare r record; begin
  for r in select oid::regprocedure p from pg_proc
           where pronamespace='gfe'::regnamespace and proname in ('enregistrer_production','rapport_ventes','verifier_stock_positif')
  loop execute 'drop function '||r.p||' cascade'; end loop;
end $$;
drop table if exists gfe.production_lignes, gfe.productions, gfe.lots, gfe.mouvements,
  gfe.stock_articles, gfe.points, gfe.commerciaux cascade;

-- 1) Cabinet GFE : les comptables appartiennent au cabinet
create table if not exists gfe.cabinets (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  created_at timestamptz not null default now()
);
alter table gfe.profils add column if not exists cabinet_id uuid references gfe.cabinets(id);
alter table gfe.entreprises add column if not exists cabinet_id uuid references gfe.cabinets(id);
alter table gfe.cabinets enable row level security;
create policy "membre du cabinet lit son cabinet" on gfe.cabinets for select to authenticated
  using (id in (select cabinet_id from gfe.profils where id = auth.uid()));

-- 2) Paramètres d'entreprise (PARAM de GESTION)
alter table gfe.entreprises
  add column if not exists code text,
  add column if not exists type_activite text not null default 'mixte'
    check (type_activite in ('usine','commerce','mixte')),
  add column if not exists methode_cout text not null default 'cmp'
    check (methode_cout in ('cmp','ref')),
  add column if not exists opt_lot boolean not null default false,
  add column if not exists opt_peremption boolean not null default false,
  add column if not exists opt_saisi_par boolean not null default false,
  add column if not exists opt_suivi_commercial boolean not null default true,
  add column if not exists opt_destination boolean not null default false,
  add column if not exists nb_matieres int not null default 8 check (nb_matieres between 1 and 8),
  add column if not exists alerte_peremption_jours int not null default 30;

-- 3) Référentiel (GESTION)
create table if not exists gfe.sites (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  nom text not null,
  type text not null check (type in ('Usine','Point de vente','Dépôt')),
  remarque text,
  unique (entreprise_id, nom)
);
create table if not exists gfe.familles (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  nom text not null,
  unique (entreprise_id, nom)
);
create table if not exists gfe.commerciaux (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  nom text not null,
  site_id uuid references gfe.sites(id),
  telephone text,
  actif boolean not null default true,
  unique (entreprise_id, nom)
);
create table if not exists gfe.articles (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  code text,
  designation text not null,
  famille_id uuid references gfe.familles(id),
  nature text not null check (nature in ('Matière première','Produit fini','Marchandise','Autre stockable')),
  unite text not null,
  prix_achat_ref numeric not null default 0 check (prix_achat_ref >= 0),
  prix_vente numeric not null default 0 check (prix_vente >= 0),
  seuil numeric not null default 0 check (seuil >= 0),
  mode text not null default 'QUANTITÉ' check (mode in ('LOT','QUANTITÉ')),
  created_at timestamptz not null default now(),
  unique (entreprise_id, designation)
);
create or replace function gfe.code_article() returns trigger language plpgsql as $$
begin
  if new.code is null then
    select coalesce(nullif(e.code,'')||'-','') || 'ART-' || lpad((count(a.*)+1)::text,3,'0')
      into new.code from gfe.entreprises e left join gfe.articles a on a.entreprise_id = e.id
     where e.id = new.entreprise_id group by e.code;
  end if;
  return new;
end $$;
drop trigger if exists code_article on gfe.articles;
create trigger code_article before insert on gfe.articles for each row execute function gfe.code_article();

create table if not exists gfe.nomenclature (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  produit_id uuid not null references gfe.articles(id) on delete cascade,
  matiere_id uuid not null references gfe.articles(id) on delete cascade,
  quantite numeric not null check (quantite > 0),
  remarque text,
  unique (produit_id, matiere_id)
);

-- 4) Saisies (SAISIE) : chaque ligne garde son contrôle ; seules les lignes valides comptent
create table if not exists gfe.saisies_production (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  date_saisie date not null, site_id uuid references gfe.sites(id), produit_id uuid references gfe.articles(id),
  quantite numeric, lot text, peremption date, saisi_par text, remarque text,
  controle text not null, valide boolean not null default false,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists gfe.saisies_production_matieres (
  id uuid primary key default gen_random_uuid(),
  production_id uuid not null references gfe.saisies_production(id) on delete cascade,
  rang int not null, matiere_id uuid references gfe.articles(id), lot text, quantite numeric,
  unique (production_id, rang)
);
create table if not exists gfe.saisies_vente (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  date_saisie date not null, point_id uuid references gfe.sites(id), commercial_id uuid references gfe.commerciaux(id),
  article_id uuid references gfe.articles(id), quantite numeric, prix_unitaire numeric, montant numeric,
  piece text, saisi_par text, controle text not null, valide boolean not null default false,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists gfe.saisies_achat (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  date_saisie date not null, site_id uuid references gfe.sites(id), article_id uuid references gfe.articles(id),
  quantite numeric, prix_unitaire numeric, montant numeric, lot text, peremption date, piece text, saisi_par text,
  controle text not null, valide boolean not null default false,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists gfe.saisies_autres (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  date_saisie date not null, site_id uuid references gfe.sites(id), type text, article_id uuid references gfe.articles(id),
  quantite numeric, site_destination_id uuid references gfe.sites(id), lot text, peremption date,
  motif text, remarque text, saisi_par text, effet numeric,
  controle text not null, valide boolean not null default false,
  created_by uuid, created_at timestamptz not null default now()
);

-- 5) Journal des mouvements valides (source unique du stock)
create table if not exists gfe.mouvements_stock (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  site_id uuid not null references gfe.sites(id),
  article_id uuid not null references gfe.articles(id),
  date_mvt date not null,
  qte numeric not null,
  source text not null,
  source_id uuid not null,
  created_at timestamptz not null default now()
);
create index if not exists mvt_stock_idx on gfe.mouvements_stock (entreprise_id, article_id, site_id, date_mvt);

-- 6) RLS : lecture par les membres, écriture par le comptable ; saisies et journal via fonctions
do $$ declare t text; begin
  foreach t in array array['sites','familles','commerciaux','articles','nomenclature',
                           'saisies_production','saisies_production_matieres','saisies_vente','saisies_achat','saisies_autres','mouvements_stock'] loop
    execute format('alter table gfe.%I enable row level security', t);
  end loop;
end $$;

-- Référentiel : membre lit, comptable écrit
create policy "membre lit sites" on gfe.sites for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "comptable écrit sites" on gfe.sites for all to authenticated using (gfe.est_comptable_de(entreprise_id)) with check (gfe.est_comptable_de(entreprise_id));
create policy "membre lit familles" on gfe.familles for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "comptable écrit familles" on gfe.familles for all to authenticated using (gfe.est_comptable_de(entreprise_id)) with check (gfe.est_comptable_de(entreprise_id));
create policy "membre lit commerciaux" on gfe.commerciaux for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "comptable écrit commerciaux" on gfe.commerciaux for all to authenticated using (gfe.est_comptable_de(entreprise_id)) with check (gfe.est_comptable_de(entreprise_id));
create policy "membre lit articles" on gfe.articles for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "comptable écrit articles" on gfe.articles for all to authenticated using (gfe.est_comptable_de(entreprise_id)) with check (gfe.est_comptable_de(entreprise_id));
create policy "membre lit nomenclature" on gfe.nomenclature for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "comptable écrit nomenclature" on gfe.nomenclature for all to authenticated using (gfe.est_comptable_de(entreprise_id)) with check (gfe.est_comptable_de(entreprise_id));
-- Saisies : le membre (client ou comptable) lit ; pas d'écriture directe (fonctions saisir_*)
create policy "membre lit saisies production" on gfe.saisies_production for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "membre lit saisies matieres" on gfe.saisies_production_matieres for select to authenticated
  using (exists (select 1 from gfe.saisies_production p where p.id = production_id and gfe.est_membre(p.entreprise_id)));
create policy "membre lit saisies vente" on gfe.saisies_vente for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "membre lit saisies achat" on gfe.saisies_achat for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "membre lit saisies autres" on gfe.saisies_autres for select to authenticated using (gfe.est_membre(entreprise_id));
-- Journal de stock : comptable seulement (le client ne voit pas les stocks de GESTION)
create policy "comptable lit mouvements" on gfe.mouvements_stock for select to authenticated using (gfe.est_comptable_de(entreprise_id));

-- 7) Grants
grant select, insert, update, delete on gfe.sites, gfe.familles, gfe.commerciaux, gfe.articles, gfe.nomenclature to authenticated;
grant select on gfe.saisies_production, gfe.saisies_production_matieres, gfe.saisies_vente, gfe.saisies_achat, gfe.saisies_autres, gfe.mouvements_stock to authenticated;
grant usage, select on all sequences in schema gfe to authenticated;
revoke all on gfe.sites, gfe.familles, gfe.commerciaux, gfe.articles, gfe.nomenclature,
  gfe.saisies_production, gfe.saisies_production_matieres, gfe.saisies_vente, gfe.saisies_achat, gfe.saisies_autres, gfe.mouvements_stock from anon;
