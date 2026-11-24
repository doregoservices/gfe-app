-- 0018 : droits d'écriture pour le module comptabilité (la sécurité reste assurée par RLS).
grant insert, update on gfe.tiers, gfe.operations, gfe.plan_comptes, gfe.parametres_entreprise to authenticated;
grant insert, update, delete on gfe.tiers, gfe.plan_comptes, gfe.parametres_entreprise to authenticated;
grant insert, update on gfe.modules_actifs to authenticated;
