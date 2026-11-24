-- 0024 : accès à la paie réservé aux comptables de l'entreprise et aux chefs ; salaire moyen des 12 mois ;
-- indemnité de licenciement (décret 2017-210, art. 4).

-- 1. Droits : le client (saisie) ne voit pas les salariés ; le comptable ne voit que ses entreprises ; les chefs voient tout.
drop policy if exists "salaries lisibles membre" on gfe.salaries;
drop policy if exists "salaries ajout" on gfe.salaries;
drop policy if exists "salaries modif" on gfe.salaries;
drop policy if exists "salaries suppr" on gfe.salaries;
create policy "salaries paie" on gfe.salaries for select to authenticated using (gfe.est_comptable_de(entreprise_id));
create policy "salaries ajout" on gfe.salaries for insert to authenticated with check (gfe.est_comptable_de(entreprise_id));
create policy "salaries modif" on gfe.salaries for update to authenticated using (gfe.est_comptable_de(entreprise_id)) with check (gfe.est_comptable_de(entreprise_id));
create policy "salaries suppr" on gfe.salaries for delete to authenticated using (gfe.est_comptable_de(entreprise_id));

-- 2. Salaire moyen des 12 derniers mois (sert aux dommages-intérêts et à l'indemnité). Vide = salaire de base.
alter table gfe.salaries add column if not exists salaire_moyen_12_mois numeric(12,0) check (salaire_moyen_12_mois is null or salaire_moyen_12_mois >= 0);

-- 3. Paramètres de l'indemnité de licenciement (décret 2017-210, art. 4 : 30 % / 35 % / 40 % par année)
insert into gfe.rh_reglages (cle, valeur, libelle, source) values
  ('indemnite_taux_1', 0.30, 'Indemnité de licenciement : taux des 5 premières années', 'Décret 2017-210, art. 4'),
  ('indemnite_taux_2', 0.35, 'Indemnité de licenciement : taux de la 6e à la 10e année', 'Décret 2017-210, art. 4'),
  ('indemnite_taux_3', 0.40, 'Indemnité de licenciement : taux au-delà de la 10e année', 'Décret 2017-210, art. 4'),
  ('indemnite_seuil_1_mois', 60, 'Indemnité : fin de la 1re tranche (mois)', 'Décret 2017-210, art. 4'),
  ('indemnite_seuil_2_mois', 120, 'Indemnité : fin de la 2e tranche (mois)', 'Décret 2017-210, art. 4'),
  ('indemnite_anciennete_min_mois', 12, 'Indemnité : ancienneté minimale (mois de service continu)', 'Décret 2017-210, art. 1')
on conflict (cle) do nothing;

-- 4. Dommages-intérêts : salaire moyen des 12 mois si renseigné
create or replace function gfe.dommages_salarie(p_salarie uuid, p_date_rupture date default current_date)
returns table (mois_retenus numeric, montant numeric, anciennete_annees integer)
language plpgsql stable security invoker set search_path = gfe, public as $$
declare s gfe.salaries%rowtype; ans integer; res record;
begin
  select * into s from gfe.salaries where id = p_salarie;
  if not found then raise exception 'Salarié introuvable ou non visible'; end if;
  ans := extract(year from age(p_date_rupture, s.date_entree))::integer;
  select * into res from gfe.dommages_licenciement_abusif(coalesce(s.salaire_moyen_12_mois, s.salaire_base), ans);
  mois_retenus := res.mois_retenus; montant := res.montant; anciennete_annees := ans;
  return next;
end $$;

-- 5. Indemnité de licenciement : 30 % / 35 % / 40 % du salaire moyen par année, fractions arrondies au mois inférieur
create or replace function gfe.indemnite_licenciement_salarie(
  p_salarie uuid, p_date_rupture date default current_date, p_faute_lourde boolean default false)
returns table (eligible boolean, anciennete_mois integer, salaire_reference numeric, montant numeric)
language plpgsql stable security invoker set search_path = gfe, public as $$
declare
  s gfe.salaries%rowtype; m integer; a interval;
  t1 numeric; t2 numeric; t3 numeric; sg1 numeric; sg2 numeric; mini numeric;
  b1 numeric; b2 numeric; b3 numeric; ref numeric;
begin
  select * into s from gfe.salaries where id = p_salarie;
  if not found then raise exception 'Salarié introuvable ou non visible'; end if;
  select valeur into t1 from gfe.rh_reglages where cle = 'indemnite_taux_1';
  select valeur into t2 from gfe.rh_reglages where cle = 'indemnite_taux_2';
  select valeur into t3 from gfe.rh_reglages where cle = 'indemnite_taux_3';
  select valeur into sg1 from gfe.rh_reglages where cle = 'indemnite_seuil_1_mois';
  select valeur into sg2 from gfe.rh_reglages where cle = 'indemnite_seuil_2_mois';
  select valeur into mini from gfe.rh_reglages where cle = 'indemnite_anciennete_min_mois';
  a := age(p_date_rupture, s.date_entree);
  m := extract(year from a)::integer * 12 + extract(month from a)::integer;   -- fractions de mois ignorées
  ref := coalesce(s.salaire_moyen_12_mois, s.salaire_base);
  b1 := least(m, sg1);
  b2 := greatest(0, least(m, sg2) - sg1);
  b3 := greatest(0, m - sg2);
  eligible := (m >= mini) and not coalesce(p_faute_lourde, false);
  anciennete_mois := m;
  salaire_reference := ref;
  montant := case when eligible then round(ref * (b1 * t1 + b2 * t2 + b3 * t3) / 12, 0) else 0 end;
  return next;
end $$;

grant execute on function gfe.dommages_salarie(uuid, date) to authenticated;
grant execute on function gfe.indemnite_licenciement_salarie(uuid, date, boolean) to authenticated;
