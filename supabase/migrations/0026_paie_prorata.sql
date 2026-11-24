-- 0026 : prorata des entrées et sorties en cours de mois (base 30 jours), validé par le responsable.
-- Mois complet = 30 jours. Mois partiel = jours calendaires travaillés (plafonnés à 30) ÷ 30.
-- Le salaire de base et le transport sont proratisés (arrondi au franc).
-- Un net à payer négatif n'est pas bloquant : il est signalé par une alerte (choix du responsable).
-- Idempotente.

create or replace function gfe.generer_bulletins_entreprise(p_entreprise uuid, p_mois date)
returns integer
language plpgsql security definer set search_path = gfe, public as $$
declare
  s record; bl record; n integer := 0;
  debut date := date_trunc('month', p_mois)::date;
  fin date := (date_trunc('month', p_mois) + interval '1 month - 1 day')::date;
  d_debut date; d_fin date; jours numeric; f numeric;
  brut_p numeric; transport_p numeric;
begin
  for s in
    select * from gfe.salaries
    where entreprise_id = p_entreprise and mode_paie = 'mois'
      and date_entree <= fin and (date_sortie is null or date_sortie >= debut)
  loop
    d_debut := greatest(debut, s.date_entree);
    d_fin := least(fin, coalesce(s.date_sortie, fin));
    if d_debut = debut and d_fin = fin then
      jours := 30;
    else
      jours := least(30, (d_fin - d_debut + 1));
    end if;
    f := jours / 30;
    brut_p := round(s.salaire_base * f, 0);
    transport_p := round(s.transport * f, 0);

    select * into bl from gfe.bulletin_paie(brut_p, transport_p, s.personnes_cmu, s.parts);
    insert into gfe.bulletins_paie as bp (
      entreprise_id, salarie_id, periode, date_paie, brut, transport, cnps_salarie, cmu_salarie,
      its_brut, ricf, its_net, net_a_payer, cnps_patronale, prestations_familiales, accidents_travail,
      maternite, cmu_patronale, its_patronal, fdfp, cout_employeur)
    values (p_entreprise, s.id, fin, fin, bl.brut, bl.transport, bl.cnps_salarie, bl.cmu_salarie,
      bl.its_brut, bl.ricf, bl.its_net, bl.net_a_payer, bl.cnps_patronale, bl.prestations_familiales,
      bl.accidents_travail, bl.maternite, bl.cmu_patronale, bl.its_patronal, bl.fdfp, bl.cout_employeur)
    on conflict (salarie_id, periode) do update set
      brut = excluded.brut, transport = excluded.transport, cnps_salarie = excluded.cnps_salarie,
      cmu_salarie = excluded.cmu_salarie, its_brut = excluded.its_brut, ricf = excluded.ricf,
      its_net = excluded.its_net, net_a_payer = excluded.net_a_payer, cnps_patronale = excluded.cnps_patronale,
      prestations_familiales = excluded.prestations_familiales, accidents_travail = excluded.accidents_travail,
      maternite = excluded.maternite, cmu_patronale = excluded.cmu_patronale, its_patronal = excluded.its_patronal,
      fdfp = excluded.fdfp, cout_employeur = excluded.cout_employeur;
    n := n + 1;
  end loop;
  return n;
end $$;
