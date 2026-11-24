-- 0023 : salariés par entreprise, bulletin de paie (taux du modèle GFE COMPTABLE, feuille PARAM),
-- calculs gratification / préavis / dommages par salarié. Tous les taux sont dans gfe.rh_reglages et gfe.rh_bareme_its.

-- 1. Sources : retirer les mentions d'attente des grilles chargées (le texte officiel est la source de référence)
update gfe.rh_categories
   set source = 'Arrêté 0050/MEPS/CAB du 19/05/2023, grille ' || branche || ' (source : AfricaPaieRH, état au 1er octobre 2026)'
 where source is not null;

-- 2. Taux de paie (modèle GFE COMPTABLE, PARAM B38 à B50)
insert into gfe.rh_reglages (cle, valeur, libelle, source) values
  ('cnps_salarie_taux', 0.063, 'CNPS retraite, part salarié', 'Modèle GFE COMPTABLE, PARAM B38'),
  ('cnps_patronale_taux', 0.077, 'CNPS retraite, part employeur', 'Modèle GFE COMPTABLE, PARAM B39'),
  ('cnps_plafond', 3375000, 'Plafond CNPS retraite (F/mois)', 'Modèle GFE COMPTABLE, PARAM B40'),
  ('pf_taux', 0.05, 'Prestations familiales, employeur', 'Modèle GFE COMPTABLE, PARAM B41'),
  ('at_taux', 0.03, 'Accidents du travail, employeur', 'Modèle GFE COMPTABLE, PARAM B42'),
  ('mat_taux', 0.0075, 'Maternité, employeur', 'Modèle GFE COMPTABLE, PARAM B43'),
  ('pf_at_mat_plafond', 70000, 'Plafond prestations familiales, AT, maternité (F/mois)', 'Modèle GFE COMPTABLE, PARAM B44'),
  ('cmu_montant', 1000, 'CMU, montant par personne couverte (F/mois)', 'Modèle GFE COMPTABLE, PARAM B45'),
  ('cmu_part_salarie', 0.5, 'CMU, part salarié (le reste est payé par l''employeur)', 'Modèle GFE COMPTABLE, PARAM B46'),
  ('fdfp_taux', 0.016, 'FDFP, part du brut', 'Modèle GFE COMPTABLE, PARAM B47'),
  ('its_patronal_taux', 0.012, 'ITS employeur, part du brut', 'Modèle GFE COMPTABLE, PARAM B48'),
  ('ricf_demi_part', 5500, 'RICF : réduction par demi-part (F/mois)', 'Modèle GFE COMPTABLE, PARAM B49'),
  ('ricf_parts_max', 5, 'RICF : nombre maximal de parts', 'Modèle GFE COMPTABLE, PARAM B50')
on conflict (cle) do nothing;

-- 3. Barème ITS mensuel (modèle GFE COMPTABLE, PARAM B53 à B62)
create table if not exists gfe.rh_bareme_its (
  ordre integer primary key,
  de_montant numeric(14,0) not null,
  a_montant numeric(14,0),
  taux numeric(6,4) not null
);
alter table gfe.rh_bareme_its enable row level security;
drop policy if exists "bareme its lisible" on gfe.rh_bareme_its;
create policy "bareme its lisible" on gfe.rh_bareme_its for select to authenticated using (true);
insert into gfe.rh_bareme_its (ordre, de_montant, a_montant, taux) values
  (1, 0, 75000, 0), (2, 75000, 240000, 0.16), (3, 240000, 800000, 0.21),
  (4, 800000, 2400000, 0.24), (5, 2400000, 8000000, 0.28), (6, 8000000, null, 0.32)
on conflict (ordre) do nothing;
grant select on gfe.rh_bareme_its to authenticated;

-- 4. Salariés
create table if not exists gfe.salaries (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  nom text not null,
  fonction text,
  branche text not null,
  categorie text not null,
  date_entree date not null,
  date_sortie date,
  mode_paie text not null default 'mois' check (mode_paie in ('heure', 'mois')),
  groupe_preavis text not null default 'cat1_5' check (groupe_preavis in ('cat1_5', 'cat6')),
  salaire_base numeric(12,0) not null check (salaire_base >= 0),
  transport numeric(12,0) not null default 0,
  personnes_cmu integer not null default 0 check (personnes_cmu >= 0),
  parts numeric(3,1) not null default 1,
  created_at timestamptz not null default now(),
  foreign key (branche, categorie) references gfe.rh_categories (branche, categorie)
);
alter table gfe.salaries enable row level security;
drop policy if exists "salaries lisibles membre" on gfe.salaries;
drop policy if exists "salaries ajout" on gfe.salaries;
drop policy if exists "salaries modif" on gfe.salaries;
drop policy if exists "salaries suppr" on gfe.salaries;
create policy "salaries lisibles membre" on gfe.salaries for select to authenticated using (gfe.est_membre(entreprise_id));
create policy "salaries ajout" on gfe.salaries for insert to authenticated with check (gfe.peut_ecrire(entreprise_id));
create policy "salaries modif" on gfe.salaries for update to authenticated using (gfe.peut_ecrire(entreprise_id)) with check (gfe.peut_ecrire(entreprise_id));
create policy "salaries suppr" on gfe.salaries for delete to authenticated using (gfe.peut_ecrire(entreprise_id));
grant select, insert, update, delete on gfe.salaries to authenticated;

-- 5. Bulletin de paie d'un mois (règles du modèle : brut imposable = base, transport hors ITS)
create or replace function gfe.bulletin_paie(
  p_brut numeric,
  p_transport numeric default 0,
  p_cmu_personnes integer default 0,
  p_parts numeric default 1)
returns table (
  brut numeric, transport numeric, cnps_salarie numeric, cmu_salarie numeric,
  its_brut numeric, ricf numeric, its_net numeric, net_a_payer numeric,
  cnps_patronale numeric, prestations_familiales numeric, accidents_travail numeric, maternite numeric,
  cmu_patronale numeric, its_patronal numeric, fdfp numeric, cout_employeur numeric)
language plpgsql stable security invoker set search_path = gfe, public as $$
declare
  r record;
  base_cnps numeric; base_pf numeric; parts_ret numeric;
  v_its numeric; v_ricf numeric; v_cmu_total numeric;
begin
  select
    max(valeur) filter (where cle = 'cnps_salarie_taux') as cnps_sal,
    max(valeur) filter (where cle = 'cnps_patronale_taux') as cnps_pat,
    max(valeur) filter (where cle = 'cnps_plafond') as cnps_plafond,
    max(valeur) filter (where cle = 'pf_taux') as pf,
    max(valeur) filter (where cle = 'at_taux') as at,
    max(valeur) filter (where cle = 'mat_taux') as mat,
    max(valeur) filter (where cle = 'pf_at_mat_plafond') as pf_plafond,
    max(valeur) filter (where cle = 'cmu_montant') as cmu,
    max(valeur) filter (where cle = 'cmu_part_salarie') as cmu_part,
    max(valeur) filter (where cle = 'fdfp_taux') as fdfp,
    max(valeur) filter (where cle = 'its_patronal_taux') as its_pat,
    max(valeur) filter (where cle = 'ricf_demi_part') as ricf_dp,
    max(valeur) filter (where cle = 'ricf_parts_max') as ricf_max
  into r from gfe.rh_reglages;

  base_cnps := least(coalesce(p_brut, 0), r.cnps_plafond);
  base_pf := least(coalesce(p_brut, 0), r.pf_plafond);
  v_its := (select coalesce(sum(greatest(0, least(coalesce(p_brut, 0), coalesce(a_montant, coalesce(p_brut, 0))) - de_montant) * taux), 0)
              from gfe.rh_bareme_its);
  parts_ret := least(greatest(coalesce(p_parts, 1), 1), r.ricf_max);
  v_ricf := least(round((parts_ret - 1) * 2 * r.ricf_dp, 0), round(v_its, 0));
  v_cmu_total := r.cmu * greatest(coalesce(p_cmu_personnes, 0), 0);

  brut := round(coalesce(p_brut, 0), 0);
  transport := round(coalesce(p_transport, 0), 0);
  cnps_salarie := round(base_cnps * r.cnps_sal, 0);
  cmu_salarie := round(v_cmu_total * r.cmu_part, 0);
  its_brut := round(v_its, 0);
  ricf := v_ricf;
  its_net := greatest(0, round(v_its, 0) - v_ricf);
  net_a_payer := brut + transport - cnps_salarie - cmu_salarie - its_net;
  cnps_patronale := round(base_cnps * r.cnps_pat, 0);
  prestations_familiales := round(base_pf * r.pf, 0);
  accidents_travail := round(base_pf * r.at, 0);
  maternite := round(base_pf * r.mat, 0);
  cmu_patronale := round(v_cmu_total * (1 - r.cmu_part), 0);
  its_patronal := round(brut * r.its_pat, 0);
  fdfp := round(brut * r.fdfp, 0);
  cout_employeur := brut + transport + cnps_patronale + prestations_familiales + accidents_travail
                    + maternite + cmu_patronale + its_patronal + fdfp;
  return next;
end $$;

-- 6. Calculs par salarié (la règle d'accès est celle de la table : le salarié doit être visible)
create or replace function gfe.gratification_salarie(p_salarie uuid, p_annee integer)
returns numeric language plpgsql stable security invoker set search_path = gfe, public as $$
declare s gfe.salaries%rowtype;
begin
  select * into s from gfe.salaries where id = p_salarie;
  if not found then raise exception 'Salarié introuvable ou non visible'; end if;
  return gfe.gratification_minimum(s.branche, s.categorie, p_annee, s.date_entree, s.date_sortie);
end $$;

create or replace function gfe.preavis_salarie(p_salarie uuid, p_date_rupture date default current_date, p_incapacite boolean default false)
returns table (duree numeric, unite text, anciennete_mois numeric)
language plpgsql stable security invoker set search_path = gfe, public as $$
declare s gfe.salaries%rowtype; a interval; mois numeric; res record;
begin
  select * into s from gfe.salaries where id = p_salarie;
  if not found then raise exception 'Salarié introuvable ou non visible'; end if;
  a := age(p_date_rupture, s.date_entree);
  mois := extract(year from a) * 12 + extract(month from a) + extract(day from a) / 30.0;
  select * into res from gfe.duree_preavis(s.mode_paie, s.groupe_preavis, mois, p_incapacite);
  duree := res.duree; unite := res.unite; anciennete_mois := round(mois, 1);
  return next;
end $$;

create or replace function gfe.dommages_salarie(p_salarie uuid, p_date_rupture date default current_date)
returns table (mois_retenus numeric, montant numeric, anciennete_annees integer)
language plpgsql stable security invoker set search_path = gfe, public as $$
declare s gfe.salaries%rowtype; ans integer; res record;
begin
  select * into s from gfe.salaries where id = p_salarie;
  if not found then raise exception 'Salarié introuvable ou non visible'; end if;
  ans := extract(year from age(p_date_rupture, s.date_entree))::integer;
  select * into res from gfe.dommages_licenciement_abusif(s.salaire_base, ans);
  mois_retenus := res.mois_retenus; montant := res.montant; anciennete_annees := ans;
  return next;
end $$;

grant execute on function gfe.bulletin_paie(numeric, numeric, integer, numeric) to authenticated;
grant execute on function gfe.gratification_salarie(uuid, integer) to authenticated;
grant execute on function gfe.preavis_salarie(uuid, date, boolean) to authenticated;
grant execute on function gfe.dommages_salarie(uuid, date) to authenticated;
