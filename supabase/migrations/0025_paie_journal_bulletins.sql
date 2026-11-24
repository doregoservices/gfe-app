-- 0025 : bulletins mensuels et journal de paie (journal PA) dans la Comptabilité.
-- Reprend MOTEUR_PAIE du modèle GFE COMPTABLE : 9 lignes par bulletin, les lignes à zéro sortent du journal.
-- Lignes (comptes du plan général) :
--   1 D 66100000 brut imposable            2 D 66340000 transport
--   3 D 66410000 CNPS patronale + PF/AT/maternité + CMU employeur
--   4 D 64130000 ITS employeur             5 D 64140000 FDFP
--   6 C 42200000 net à payer (personnel)
--   7 C 43100000 CNPS salarié + CMU salarié + CNPS patronale + PF/AT/maternité + CMU employeur
--   8 C 44700000 ITS salarié net + ITS employeur
--   9 C 44700000 FDFP
-- Accès : bulletins lisibles et générables par le comptable de l'entreprise ou un chef (est_comptable_de).
-- Idempotente.

-- 1. Bulletins mensuels (un par salarié et par mois)
create table if not exists gfe.bulletins_paie (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  salarie_id uuid not null references gfe.salaries(id) on delete cascade,
  periode date not null,                 -- fin de mois de la paie
  date_paie date not null,
  brut numeric not null default 0,
  transport numeric not null default 0,
  cnps_salarie numeric not null default 0,
  cmu_salarie numeric not null default 0,
  its_brut numeric not null default 0,
  ricf numeric not null default 0,
  its_net numeric not null default 0,
  net_a_payer numeric not null default 0,
  cnps_patronale numeric not null default 0,
  prestations_familiales numeric not null default 0,
  accidents_travail numeric not null default 0,
  maternite numeric not null default 0,
  cmu_patronale numeric not null default 0,
  its_patronal numeric not null default 0,
  fdfp numeric not null default 0,
  cout_employeur numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (salarie_id, periode)
);
alter table gfe.bulletins_paie enable row level security;
drop policy if exists "bulletins paie comptable" on gfe.bulletins_paie;
create policy "bulletins paie comptable" on gfe.bulletins_paie for select to authenticated
  using (gfe.est_comptable_de(entreprise_id));
grant select on gfe.bulletins_paie to authenticated;

-- 2. Génération interne (sans contrôle d'accès : appelée par la fonction publique et par les tests)
create or replace function gfe.generer_bulletins_entreprise(p_entreprise uuid, p_mois date)
returns integer
language plpgsql security definer set search_path = gfe, public as $$
declare
  s record; bl record; n integer := 0;
  debut date := date_trunc('month', p_mois)::date;
  fin date := (date_trunc('month', p_mois) + interval '1 month - 1 day')::date;
begin
  for s in
    select * from gfe.salaries
    where entreprise_id = p_entreprise and mode_paie = 'mois'
      and date_entree <= fin and (date_sortie is null or date_sortie >= debut)
  loop
    select * into bl from gfe.bulletin_paie(s.salaire_base, s.transport, s.personnes_cmu, s.parts);
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

-- 3. Fonction publique : contrôle du rôle (comptable de l'entreprise ou chef)
create or replace function gfe.generer_bulletins(p_entreprise uuid, p_mois date)
returns integer
language plpgsql security definer set search_path = gfe, public as $$
begin
  if not gfe.est_comptable_de(p_entreprise) then
    raise exception 'Accès réservé aux comptables de cette entreprise et aux chefs';
  end if;
  return gfe.generer_bulletins_entreprise(p_entreprise, p_mois);
end $$;
revoke all on function gfe.generer_bulletins(uuid, date) from public;
grant execute on function gfe.generer_bulletins(uuid, date) to authenticated;

-- 4. Écritures de paie : 9 lignes par bulletin, lignes à zéro exclues
create or replace view gfe.v_ecritures_paie with (security_invoker = true) as
select b.entreprise_id, 'PA'::text as journal, b.id as operation_id, n.ecr, b.date_paie as date_operation,
       'PAIE-' || to_char(b.periode, 'YYYYMM') || '-' || left(b.salarie_id::text, 8) as piece,
       'Paie ' || s.nom || ' ' || to_char(b.periode, 'MM/YYYY') as libelle,
       n.cote, n.compte, n.compte_tiers, n.tiers,
       case when n.cote = 'D' then n.montant else 0 end as debit,
       case when n.cote = 'C' then n.montant else 0 end as credit,
       b.created_at
from gfe.bulletins_paie b
join gfe.salaries s on s.id = b.salarie_id
cross join lateral (values
  (1, 'D', '66100000', b.brut, '', ''),
  (2, 'D', '66340000', b.transport, '', ''),
  (3, 'D', '66410000', b.cnps_patronale + b.prestations_familiales + b.accidents_travail + b.maternite + b.cmu_patronale, '', ''),
  (4, 'D', '64130000', b.its_patronal, '', ''),
  (5, 'D', '64140000', b.fdfp, '', ''),
  (6, 'C', '42200000', b.net_a_payer, 'SAL-' || left(b.salarie_id::text, 8), s.nom),
  (7, 'C', '43100000', b.cnps_salarie + b.cmu_salarie + b.cnps_patronale + b.prestations_familiales + b.accidents_travail + b.maternite + b.cmu_patronale, '', ''),
  (8, 'C', '44700000', b.its_net + b.its_patronal, '', ''),
  (9, 'C', '44700000', b.fdfp, '', '')
) as n(ecr, cote, compte, montant, compte_tiers, tiers)
where n.montant <> 0;

-- 5. Écritures de toutes les sources (opérations et paie), utilisées par le journal et la balance
create or replace view gfe.v_ecritures_tous with (security_invoker = true) as
select e.entreprise_id, e.journal, e.date_operation, e.operation_id, e.ecr, e.piece, e.libelle, e.cote,
       e.compte, e.compte_tiers, e.tiers, e.debit, e.credit, o.created_at
from gfe.v_ecritures e
join gfe.operations o on o.id = e.operation_id
union all
select p.entreprise_id, p.journal, p.date_operation, p.operation_id, p.ecr, p.piece, p.libelle, p.cote,
       p.compte, p.compte_tiers, p.tiers, p.debit, p.credit, p.created_at
from gfe.v_ecritures_paie p;

-- 6. Journaux et balance reposent désormais sur toutes les écritures (journal PA inclus)
create or replace view gfe.v_journaux with (security_invoker = true) as
select e.entreprise_id, e.journal,
       row_number() over (partition by e.entreprise_id, e.journal
                          order by e.date_operation, e.created_at, e.operation_id, e.ecr,
                                   case when e.cote = 'D' then 0 else 1 end) as rang,
       e.operation_id, e.ecr, e.date_operation, coalesce(nullif(e.piece, ''), 'AUTO-' || e.operation_id::text) as piece,
       e.libelle, e.cote, e.compte, e.compte_tiers, e.tiers, e.debit, e.credit
from gfe.v_ecritures_tous e;

create or replace view gfe.v_balance with (security_invoker = true) as
with mouv as (
  select entreprise_id, compte, sum(debit) as md, sum(credit) as mc
  from gfe.v_ecritures_tous group by entreprise_id, compte
)
select pc.entreprise_id, pc.numero_affiche as compte, pc.libelle, pc.classe,
       greatest(pc.solde_ouverture, 0) as ouverture_d,
       greatest(-pc.solde_ouverture, 0) as ouverture_c,
       coalesce(m.md, 0) as mouvements_d,
       coalesce(m.mc, 0) as mouvements_c,
       greatest(0, greatest(pc.solde_ouverture, 0) + coalesce(m.md, 0)
                  - greatest(-pc.solde_ouverture, 0) - coalesce(m.mc, 0)) as solde_final_d,
       greatest(0, greatest(-pc.solde_ouverture, 0) + coalesce(m.mc, 0)
                  - greatest(pc.solde_ouverture, 0) - coalesce(m.md, 0)) as solde_final_c,
       pc.numero_interne
from gfe.plan_comptes pc
left join mouv m on m.entreprise_id = pc.entreprise_id and m.compte = pc.numero_interne;

grant select on gfe.v_ecritures_paie, gfe.v_ecritures_tous, gfe.v_journaux, gfe.v_balance to authenticated;
