-- 0010 : paramètres (PARAM de GESTION), noms des colonnes d'analyse, vue réduite pour SAISIE.

alter table gfe.entreprises
  add column if not exists analyse1_nom text not null default 'Analyse 1',
  add column if not exists analyse2_nom text not null default 'Analyse 2';

-- Seul le comptable de l'entreprise modifie PARAM
create or replace function gfe.modifier_parametres(
  p_entreprise uuid, p_nom text, p_code text, p_type_activite text, p_methode_cout text,
  p_opt_lot boolean, p_opt_peremption boolean, p_opt_saisi_par boolean, p_opt_suivi_commercial boolean,
  p_opt_destination boolean, p_nb_matieres int, p_alerte_jours int, p_analyse1 text, p_analyse2 text)
returns void language plpgsql security definer set search_path = gfe, public as $$
begin
  if not gfe.est_comptable_de(p_entreprise) then raise exception 'Réservé au comptable de cette entreprise'; end if;
  if nullif(trim(p_nom), '') is null then raise exception 'Nom obligatoire'; end if;
  update gfe.entreprises set
    nom = trim(p_nom), code = nullif(upper(trim(p_code)), ''), type_activite = p_type_activite,
    methode_cout = p_methode_cout, opt_lot = p_opt_lot, opt_peremption = p_opt_peremption,
    opt_saisi_par = p_opt_saisi_par, opt_suivi_commercial = p_opt_suivi_commercial,
    opt_destination = p_opt_destination, nb_matieres = p_nb_matieres,
    alerte_peremption_jours = p_alerte_jours,
    analyse1_nom = coalesce(nullif(trim(p_analyse1), ''), 'Analyse 1'),
    analyse2_nom = coalesce(nullif(trim(p_analyse2), ''), 'Analyse 2')
  where id = p_entreprise;
end $$;
revoke all on function gfe.modifier_parametres(uuid,text,text,text,text,boolean,boolean,boolean,boolean,boolean,int,int,text,text) from public, anon;
grant execute on function gfe.modifier_parametres(uuid,text,text,text,text,boolean,boolean,boolean,boolean,boolean,int,int,text,text) to authenticated;

-- Référentiel visible par le client (SAISIE) : sans coût, sans seuil, sans prix d'achat
create or replace view gfe.v_articles_saisie with (security_invoker = true) as
  select id, entreprise_id, code, designation, nature, unite, mode, prix_vente, famille_id from gfe.articles;
grant select on gfe.v_articles_saisie to authenticated;
