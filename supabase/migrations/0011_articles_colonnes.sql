-- 0011 : le client ne lit pas les prix d'achat ni les seuils (données de GESTION).
-- La lecture complète passe par gfe.articles_gestion(), réservée au comptable de l'entreprise.
revoke select on gfe.articles from authenticated;
grant select (id, entreprise_id, code, designation, famille_id, nature, unite, mode, prix_vente, created_at) on gfe.articles to authenticated;

create or replace function gfe.articles_gestion(p_entreprise uuid) returns setof gfe.articles
language plpgsql stable security definer set search_path = gfe, public as $$
begin
  if not gfe.est_comptable_de(p_entreprise) then raise exception 'Réservé au comptable de cette entreprise'; end if;
  return query select * from gfe.articles where entreprise_id = p_entreprise order by designation;
end $$;
revoke all on function gfe.articles_gestion(uuid) from public, anon;
grant execute on function gfe.articles_gestion(uuid) to authenticated;
