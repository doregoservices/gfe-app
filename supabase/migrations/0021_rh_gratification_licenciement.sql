-- 0021 : gratification de fin d'année (CCI 1977 art. 53) et dommages-intérêts pour licenciement abusif (Code du travail art. 18.15)
-- Tous les taux, seuils et minima sont dans des tables modifiables (aucune valeur figée dans le code).

-- 1. Catégories conventionnelles et minimum par catégorie.
--    minimum_conventionnel = salaire minimum hiérarchisé de la catégorie (grille de la CCI, à saisir depuis la grille officielle).
--    Seule la 1re catégorie est renseignée : elle correspond au SMIG (75 000 F, décret 2022-986). Les autres restent vides
--    tant que la grille officielle n'est pas saisie : le calcul refuse alors de travailler (pas de valeur inventée).
create table if not exists gfe.rh_categories (
  categorie text primary key,
  libelle text not null,
  minimum_conventionnel numeric(12,0),
  source text,
  explication text
);
alter table gfe.rh_categories enable row level security;
drop policy if exists "categories lisibles" on gfe.rh_categories;
create policy "categories lisibles" on gfe.rh_categories for select to authenticated using (true);

insert into gfe.rh_categories (categorie, libelle, minimum_conventionnel, source, explication) values
  ('1', '1re catégorie (manoeuvre ordinaire)', 75000, 'SMIG, décret 2022-986 ; à confirmer par la grille CCI', 'Salaire minimum de la 1re catégorie. Sert de base à la gratification.'),
  ('2', '2e catégorie', null, 'À saisir depuis la grille officielle de la CCI', 'Minimum non renseigné : saisir la valeur officielle.'),
  ('3', '3e catégorie', null, 'À saisir depuis la grille officielle de la CCI', 'Minimum non renseigné : saisir la valeur officielle.'),
  ('4', '4e catégorie', null, 'À saisir depuis la grille officielle de la CCI', 'Minimum non renseigné : saisir la valeur officielle.'),
  ('5', '5e catégorie', null, 'À saisir depuis la grille officielle de la CCI', 'Minimum non renseigné : saisir la valeur officielle.'),
  ('6', '6e catégorie et plus (cadres)', null, 'À saisir depuis la grille officielle de la CCI', 'Minimum non renseigné : saisir la valeur officielle.')
on conflict (categorie) do nothing;

-- 2. Paramètres (ajout aux réglages existants).
insert into gfe.rh_reglages (cle, valeur, libelle, source) values
  ('gratif_fraction_minimum', 0.75, 'Gratification : fraction du minimum de catégorie (3/4)', 'CCI 1977, art. 53, al. 1'),
  ('abus_mois_par_annee', 1, 'Licenciement abusif : mois de salaire brut par année d''ancienneté', 'Code du travail, art. 18.15, b)'),
  ('abus_mois_minimum', 3, 'Licenciement abusif : plancher (mois de salaire brut)', 'Code du travail, art. 18.15, b)'),
  ('abus_mois_maximum', 20, 'Licenciement abusif : plafond (mois de salaire brut)', 'Code du travail, art. 18.15, b)')
on conflict (cle) do nothing;

-- 3. Gratification minimale due pour une période de service dans l'année civile.
--    Montant = 3/4 x minimum de la catégorie x (jours de service dans l'année / 365).
--    Le prorata couvre l'embauche, la démission et le licenciement en cours d'année (art. 53, al. 2).
create or replace function gfe.gratification_minimum(
  p_categorie text,
  p_annee integer,
  p_date_entree date,
  p_date_sortie date default null)
returns numeric language plpgsql stable security invoker set search_path = gfe, public as $$
declare
  c gfe.rh_categories%rowtype;
  fraction numeric; debut date; fin date; jours integer;
begin
  select * into c from gfe.rh_categories where categorie = p_categorie;
  if not found then raise exception 'Catégorie inconnue : %', p_categorie; end if;
  if c.minimum_conventionnel is null then
    raise exception 'Minimum conventionnel non renseigné pour la catégorie % : saisir la grille officielle', p_categorie;
  end if;
  select valeur into fraction from gfe.rh_reglages where cle = 'gratif_fraction_minimum';
  debut := greatest(make_date(p_annee, 1, 1), coalesce(p_date_entree, make_date(p_annee, 1, 1)));
  fin := least(make_date(p_annee, 12, 31), coalesce(p_date_sortie, make_date(p_annee, 12, 31)));
  jours := greatest(0, fin - debut + 1);
  return round(fraction * c.minimum_conventionnel * jours / 365.0, 0);
end $$;

-- 4. Dommages-intérêts pour rupture abusive (art. 18.15, b) : 1 mois de salaire brut par année d'ancienneté,
--    avec plancher de 3 mois et plafond de 20 mois. Le calcul ne décide pas si le licenciement est abusif :
--    cette qualification relève de la juridiction compétente (art. 18.15, al. 2).
create or replace function gfe.dommages_licenciement_abusif(
  p_salaire_brut_moyen numeric,
  p_anciennete_annees integer)
returns table (mois_retenus numeric, montant numeric) language plpgsql stable security invoker set search_path = gfe, public as $$
declare par_an numeric; mini numeric; maxi numeric;
begin
  select valeur into par_an from gfe.rh_reglages where cle = 'abus_mois_par_annee';
  select valeur into mini from gfe.rh_reglages where cle = 'abus_mois_minimum';
  select valeur into maxi from gfe.rh_reglages where cle = 'abus_mois_maximum';
  mois_retenus := greatest(mini, least(maxi, par_an * greatest(coalesce(p_anciennete_annees, 0), 0)));
  montant := round(mois_retenus * coalesce(p_salaire_brut_moyen, 0), 0);
  return next;
end $$;

grant select on gfe.rh_categories to authenticated;
grant execute on function gfe.gratification_minimum(text, integer, date, date) to authenticated;
grant execute on function gfe.dommages_licenciement_abusif(numeric, integer) to authenticated;
