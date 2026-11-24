-- 0016 : module 2, étape 3 : journaux et balance (reprend JRN_* et BALANCE du modèle).
-- Journaux : CA (caisse), BQ (banque), AC (achats), VT (ventes), OD (opérations diverses).
-- Rang : ordre de saisie dans chaque journal (date, puis ordre de création, débit avant crédit).
-- Idempotente.

create or replace view gfe.v_journaux with (security_invoker = true) as
select e.entreprise_id, e.journal,
       row_number() over (partition by e.entreprise_id, e.journal
                          order by e.date_operation, o.created_at, e.operation_id, e.ecr,
                                   case when e.cote = 'D' then 0 else 1 end) as rang,
       e.operation_id, e.ecr, e.date_operation, coalesce(nullif(e.piece, ''), 'AUTO-' || e.operation_id::text) as piece,
       e.libelle, e.cote, e.compte, e.compte_tiers, e.tiers, e.debit, e.credit
from gfe.v_ecritures e
join gfe.operations o on o.id = e.operation_id;

-- Balance générale : un ligne par compte du plan de l'entreprise (ordre du plan)
create or replace view gfe.v_balance with (security_invoker = true) as
with mouv as (
  select entreprise_id, compte, sum(debit) as md, sum(credit) as mc
  from gfe.v_ecritures group by entreprise_id, compte
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

grant select on gfe.v_journaux, gfe.v_balance to authenticated;
