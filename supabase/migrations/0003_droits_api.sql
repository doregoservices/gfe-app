-- Droits d'accès pour l'API. La sécurité réelle reste assurée par RLS.
grant usage on schema gfe to authenticated, service_role;
grant select on all tables in schema gfe to authenticated;
grant all on all tables in schema gfe to service_role;
-- Aucun accès pour le rôle anonyme (non connecté).
revoke all on all tables in schema gfe from anon;
revoke usage on schema gfe from anon;
alter default privileges in schema gfe grant select on tables to authenticated;
