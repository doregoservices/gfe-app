-- 0021 : gratification de fin d'année (CCI 1977 art. 53) et dommages-intérêts pour licenciement abusif (Code du travail art. 18.15)
-- Tous les taux, seuils et minima sont dans des tables modifiables (aucune valeur figée dans le code).

-- 1. Catégories conventionnelles, par branche d'activité.
--    La grille dépend de la convention de la branche (chaque branche a sa grille). minimum_conventionnel = salaire minimum
--    mensuel de la catégorie. Chaque ligne indique sa source ; une valeur vide bloque le calcul (aucune valeur inventée).
--    Branche « commerce » : grille de l'arrêté n° 0050/MEPS/CAB du 19/05/2023, relevée par AfricaPaieRH (source : AfricaPaieRH).
create table if not exists gfe.rh_categories (
  branche text not null,
  categorie text not null,
  ordre integer not null,
  libelle text not null,
  famille text,
  minimum_conventionnel numeric(12,0),
  source text,
  explication text,
  primary key (branche, categorie)
);
alter table gfe.rh_categories enable row level security;
drop policy if exists "categories lisibles" on gfe.rh_categories;
create policy "categories lisibles" on gfe.rh_categories for select to authenticated using (true);

insert into gfe.rh_categories (branche, categorie, ordre, libelle, famille, minimum_conventionnel, source, explication) values
  ('commerce', '1',   1,  'Manœuvre', 'Ouvrier', 75000, 'Arrêté 0050/MEPS/CAB du 19/05/2023 (grille commerce, relevé AfricaPaieRH)', 'Égal au SMIG.'),
  ('commerce', '2',   2,  'Employé 2e échelon', 'Employé', 85168, 'idem', ''),
  ('commerce', '3',   3,  'Employé qualifié', 'Employé', 85765, 'idem', ''),
  ('commerce', '4',   4,  'Employé très qualifié', 'Employé', 91135, 'idem', ''),
  ('commerce', '5',   5,  'Chef de rayon junior', 'Employé', 108716, 'idem', ''),
  ('commerce', '6',   6,  'Premier vendeur / comptable adjoint', 'Employé', 123213, 'idem', ''),
  ('commerce', '7A',  7,  'Secrétaire de direction', 'Employé', 124504, 'idem', ''),
  ('commerce', '7B',  8,  'Comptable principal', 'Employé', 133724, 'idem', ''),
  ('commerce', 'MNP', 9,  'Maîtrise débutant', 'Maîtrise', 116786, 'idem', ''),
  ('commerce', 'M1',  10, 'Agent de maîtrise M1', 'Maîtrise', 132473, 'idem', ''),
  ('commerce', 'M2',  11, 'Agent de maîtrise M2', 'Maîtrise', 141760, 'idem', ''),
  ('commerce', 'M3',  12, 'Technicien supérieur', 'Maîtrise', 169309, 'idem', ''),
  ('commerce', '1A',  13, 'Cadre débutant', 'Cadre', 170606, 'idem', ''),
  ('commerce', '1B',  14, 'Cadre confirmé', 'Cadre', 196398, 'idem', '')
on conflict (branche, categorie) do nothing;

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
  p_branche text,
  p_categorie text,
  p_annee integer,
  p_date_entree date,
  p_date_sortie date default null)
returns numeric language plpgsql stable security invoker set search_path = gfe, public as $$
declare
  c gfe.rh_categories%rowtype;
  fraction numeric; debut date; fin date; jours integer;
begin
  select * into c from gfe.rh_categories where branche = p_branche and categorie = p_categorie;
  if not found then raise exception 'Catégorie % inconnue pour la branche %', p_categorie, p_branche; end if;
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
grant execute on function gfe.gratification_minimum(text, text, integer, date, date) to authenticated;
grant execute on function gfe.dommages_licenciement_abusif(numeric, integer) to authenticated;
