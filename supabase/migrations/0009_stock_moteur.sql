-- 0009 : moteur du module stock (contrôles SAISIE + calculs GESTION), messages repris de Drive.

-- Vérification : le stock reste >= 0 à toute date, pour chaque article et chaque site
create or replace function gfe.stock_negatif(p_eid uuid, p_effets jsonb) returns text
language plpgsql stable security definer set search_path = gfe, public as $$
declare r record;
begin
  for r in
    with cand as (
      select (e->>'site')::uuid s, (e->>'article')::uuid a, (e->>'date')::date d, (e->>'qte')::numeric q
      from jsonb_array_elements(coalesce(p_effets, '[]'::jsonb)) e),
    tout as (
      select site_id s, article_id a, date_mvt d, sum(qte) q from gfe.mouvements_stock where entreprise_id = p_eid group by 1,2,3
      union all
      select s, a, d, sum(q) from cand group by 1,2,3),
    jour as (select s, a, d, sum(q) q from tout group by 1,2,3),
    solde as (select s, a, d, sum(q) over (partition by s, a order by d) st from jour)
    select solde.d, solde.st, arts.designation, sites.nom as site_nom
    from solde join gfe.articles arts on arts.id = solde.a join gfe.sites sites on sites.id = solde.s
    where solde.st < 0 order by solde.d limit 1
  loop
    return format('Refusé : stock négatif pour %s sur %s le %s (stock résultant : %s)',
                  r.designation, r.site_nom, to_char(r.d, 'DD/MM/YYYY'), round(r.st)::text);
  end loop;
  return null;
end $$;

create or replace function gfe.ecrire_mouvements(p_eid uuid, p_effets jsonb, p_source text, p_source_id uuid)
returns void language sql security definer set search_path = gfe, public as $$
  insert into gfe.mouvements_stock (entreprise_id, site_id, article_id, date_mvt, qte, source, source_id)
  select p_eid, (e->>'site')::uuid, (e->>'article')::uuid, (e->>'date')::date, (e->>'qte')::numeric, p_source, p_source_id
  from jsonb_array_elements(coalesce(p_effets, '[]'::jsonb)) e where (e->>'qte')::numeric <> 0;
$$;

-- ===== VENTE =====
create or replace function gfe.saisir_vente(p_entreprise uuid, p_date date, p_point uuid, p_commercial uuid,
  p_article uuid, p_quantite numeric, p_prix numeric, p_piece text, p_saisi_par text)
returns jsonb language plpgsql security definer set search_path = gfe, public as $$
declare e gfe.entreprises; s gfe.sites; a gfe.articles; v text := 'OK'; prix numeric; eff jsonb; msg text; sid uuid;
begin
  if not gfe.peut_ecrire(p_entreprise) then raise exception 'Accès refusé'; end if;
  select * into e from gfe.entreprises where id = p_entreprise;
  select * into s from gfe.sites where id = p_point and entreprise_id = p_entreprise;
  select * into a from gfe.articles where id = p_article and entreprise_id = p_entreprise;
  if p_date is null then v := 'Date manquante';
  elsif p_point is null then v := 'Point de vente manquant';
  elsif s.id is null then v := 'Point de vente inconnu';
  elsif e.opt_suivi_commercial and p_commercial is null then v := 'Commercial manquant';
  elsif e.opt_suivi_commercial and not exists (select 1 from gfe.commerciaux c where c.id = p_commercial and c.entreprise_id = p_entreprise) then v := 'Commercial inconnu';
  elsif p_article is null then v := 'Article manquant';
  elsif a.id is null or a.nature not in ('Produit fini', 'Marchandise') then v := 'Article non vendable';
  elsif coalesce(p_quantite, 0) <= 0 then v := 'Quantité invalide';
  end if;
  prix := coalesce(p_prix, a.prix_vente);
  if v = 'OK' then
    eff := jsonb_build_array(jsonb_build_object('site', p_point, 'article', p_article, 'date', p_date, 'qte', -p_quantite));
    msg := gfe.stock_negatif(p_entreprise, eff);
    if msg is not null then v := msg; end if;
  end if;
  insert into gfe.saisies_vente (entreprise_id, date_saisie, point_id, commercial_id, article_id, quantite, prix_unitaire, montant,
      piece, saisi_par, controle, valide, created_by)
  values (p_entreprise, p_date, p_point, p_commercial, p_article, p_quantite, prix,
      case when p_quantite > 0 then p_quantite * prix end, p_piece, p_saisi_par, v, v = 'OK', auth.uid())
  returning id into sid;
  if v = 'OK' then perform gfe.ecrire_mouvements(p_entreprise, eff, 'vente', sid); end if;
  return jsonb_build_object('id', sid, 'valide', v = 'OK', 'controle', v);
end $$;

-- ===== ACHAT =====
create or replace function gfe.saisir_achat(p_entreprise uuid, p_date date, p_site uuid, p_article uuid, p_quantite numeric,
  p_prix numeric, p_lot text, p_peremption date, p_piece text, p_saisi_par text)
returns jsonb language plpgsql security definer set search_path = gfe, public as $$
declare s gfe.sites; a gfe.articles; v text := 'OK'; eff jsonb; sid uuid;
begin
  if not gfe.peut_ecrire(p_entreprise) then raise exception 'Accès refusé'; end if;
  select * into s from gfe.sites where id = p_site and entreprise_id = p_entreprise;
  select * into a from gfe.articles where id = p_article and entreprise_id = p_entreprise;
  if p_date is null then v := 'Date manquante';
  elsif p_site is null then v := 'Site manquant';
  elsif s.id is null then v := 'Site inconnu';
  elsif p_article is null then v := 'Article manquant';
  elsif a.id is null or a.nature not in ('Matière première', 'Marchandise', 'Autre stockable') then v := 'Article non achetable';
  elsif coalesce(p_quantite, 0) <= 0 then v := 'Quantité invalide';
  elsif p_prix is null or p_prix < 0 then v := 'Prix d''achat manquant';
  end if;
  insert into gfe.saisies_achat (entreprise_id, date_saisie, site_id, article_id, quantite, prix_unitaire, montant, lot, peremption,
      piece, saisi_par, controle, valide, created_by)
  values (p_entreprise, p_date, p_site, p_article, p_quantite, p_prix,
      case when p_quantite > 0 and p_prix >= 0 then p_quantite * p_prix end, p_lot, p_peremption, p_piece, p_saisi_par, v, v = 'OK', auth.uid())
  returning id into sid;
  if v = 'OK' then
    eff := jsonb_build_array(jsonb_build_object('site', p_site, 'article', p_article, 'date', p_date, 'qte', p_quantite));
    perform gfe.ecrire_mouvements(p_entreprise, eff, 'achat', sid);
  end if;
  return jsonb_build_object('id', sid, 'valide', v = 'OK', 'controle', v);
end $$;

-- ===== AUTRES =====
create or replace function gfe.saisir_autres(p_entreprise uuid, p_date date, p_site uuid, p_type text, p_article uuid,
  p_quantite numeric, p_destination uuid, p_lot text, p_peremption date, p_motif text, p_remarque text, p_saisi_par text)
returns jsonb language plpgsql security definer set search_path = gfe, public as $$
declare e gfe.entreprises; s gfe.sites; a gfe.articles; v text := 'OK'; inv boolean; theo numeric := 0;
  eff jsonb := '[]'::jsonb; msg text; sid uuid; effet numeric; signe int;
begin
  if not gfe.peut_ecrire(p_entreprise) then raise exception 'Accès refusé'; end if;
  select * into e from gfe.entreprises where id = p_entreprise;
  select * into s from gfe.sites where id = p_site and entreprise_id = p_entreprise;
  select * into a from gfe.articles where id = p_article and entreprise_id = p_entreprise;
  inv := p_type = 'Inventaire (comptage)';
  signe := case when p_type in ('Stock initial', 'Entrée (autre)') then 1
                when p_type in ('Sortie (autre)', 'Casse ou perte', 'Don ou échantillon', 'Consommation interne', 'Transfert') then -1 end;
  if p_date is null then v := 'Date manquante';
  elsif p_site is null then v := 'Site manquant';
  elsif s.id is null then v := 'Site inconnu';
  elsif p_type is null then v := 'Type de mouvement manquant';
  elsif p_type not in ('Stock initial','Entrée (autre)','Sortie (autre)','Transfert','Casse ou perte','Don ou échantillon','Consommation interne','Inventaire (comptage)') then v := 'Type inconnu';
  elsif p_article is null then v := 'Article manquant';
  elsif a.id is null then v := 'Article inconnu';
  elsif inv and p_quantite is null then v := 'Quantité comptée manquante';
  elsif not inv and coalesce(p_quantite, 0) <= 0 then v := 'Quantité invalide';
  elsif p_type = 'Transfert' and not e.opt_destination then v := 'Transfert désactivé (PARAM B15 = NON)';
  elsif p_type = 'Transfert' and p_destination is null then v := 'Destination de transfert manquante';
  elsif p_type = 'Transfert' and p_destination = p_site then v := 'Destination identique au site';
  end if;
  if v = 'OK' then
    if inv then
      select coalesce(sum(qte), 0) into theo from gfe.mouvements_stock
        where entreprise_id = p_entreprise and site_id = p_site and article_id = p_article and date_mvt <= p_date;
      effet := p_quantite - theo;
      eff := jsonb_build_array(jsonb_build_object('site', p_site, 'article', p_article, 'date', p_date, 'qte', effet));
    elsif p_type = 'Transfert' then
      eff := jsonb_build_array(
        jsonb_build_object('site', p_site, 'article', p_article, 'date', p_date, 'qte', -p_quantite),
        jsonb_build_object('site', p_destination, 'article', p_article, 'date', p_date, 'qte', p_quantite));
    else
      eff := jsonb_build_array(jsonb_build_object('site', p_site, 'article', p_article, 'date', p_date, 'qte', signe * p_quantite));
    end if;
    msg := gfe.stock_negatif(p_entreprise, eff);
    if msg is not null then v := msg; end if;
  end if;
  insert into gfe.saisies_autres (entreprise_id, date_saisie, site_id, type, article_id, quantite, site_destination_id, lot,
      peremption, motif, remarque, saisi_par, effet, controle, valide, created_by)
  values (p_entreprise, p_date, p_site, p_type, p_article, p_quantite, case when p_type = 'Transfert' then p_destination end,
      p_lot, p_peremption, p_motif, p_remarque, p_saisi_par, case when inv and v = 'OK' then effet end, v, v = 'OK', auth.uid())
  returning id into sid;
  if v = 'OK' then perform gfe.ecrire_mouvements(p_entreprise, eff, 'autres', sid); end if;
  return jsonb_build_object('id', sid, 'valide', v = 'OK', 'controle', v);
end $$;

-- ===== PRODUCTION =====
-- p_matieres : tableau de {"article": uuid, "lot": texte, "quantite": nombre}
create or replace function gfe.saisir_production(p_entreprise uuid, p_date date, p_site uuid, p_produit uuid, p_quantite numeric,
  p_lot text, p_peremption date, p_remarque text, p_saisi_par text, p_matieres jsonb)
returns jsonb language plpgsql security definer set search_path = gfe, public as $$
declare e gfe.entreprises; s gfe.sites; pr gfe.articles; v text := 'OK'; n int; k int; it jsonb;
  ma uuid; ml text; mq numeric; mart gfe.articles; deja boolean; eff jsonb := '[]'::jsonb; msg text; sid uuid;
begin
  if not gfe.peut_ecrire(p_entreprise) then raise exception 'Accès refusé'; end if;
  select * into e from gfe.entreprises where id = p_entreprise;
  select * into s from gfe.sites where id = p_site and entreprise_id = p_entreprise;
  select * into pr from gfe.articles where id = p_produit and entreprise_id = p_entreprise;
  n := coalesce(jsonb_array_length(coalesce(p_matieres, '[]'::jsonb)), 0);
  if p_date is null then v := 'Date manquante';
  elsif p_site is null then v := 'Site manquant';
  elsif s.id is null then v := 'Site inconnu';
  elsif s.type <> 'Usine' then v := 'Site non usine';
  elsif p_produit is null then v := 'Produit manquant';
  elsif pr.id is null or pr.nature <> 'Produit fini' then v := 'Produit fini inconnu';
  elsif coalesce(p_quantite, 0) <= 0 then v := 'Quantité invalide';
  elsif n > e.nb_matieres then v := format('Matière %s saisie au-delà du nombre prévu (PARAM B22)', e.nb_matieres + 1);
  end if;

  if v = 'OK' then
    eff := jsonb_build_array(jsonb_build_object('site', p_site, 'article', p_produit, 'date', p_date, 'qte', p_quantite));
    for k in 1..n loop
      it := p_matieres -> (k - 1);
      ma := nullif(it->>'article', '')::uuid; ml := nullif(trim(it->>'lot'), ''); mq := nullif(it->>'quantite', '')::numeric;
      if ma is null and (mq is not null or ml is not null) then v := format('Matière %s manquante (quantité saisie)', k); exit; end if;
      if ma is null then continue; end if;
      select * into mart from gfe.articles where id = ma and entreprise_id = p_entreprise;
      if mart.id is null or mart.nature not in ('Matière première', 'Marchandise', 'Autre stockable') then
        v := format('Matière %s inconnue', k); exit;
      end if;
      if mart.mode = 'LOT' then
        if ml is null then v := format('Lot manquant (matière %s, mode LOT)', k); exit; end if;
        select exists (select 1 from gfe.saisies_production_matieres m join gfe.saisies_production p on p.id = m.production_id
                       where p.entreprise_id = p_entreprise and p.valide and m.matiere_id = ma and m.lot = ml) into deja;
        if deja and mq is not null then
          v := format('Quantité du lot à saisir une seule fois, sur la première fabrication du lot (matière %s)', k); exit;
        end if;
        if not deja and coalesce(mq, 0) <= 0 then v := format('Quantité consommée manquante (matière %s)', k); exit; end if;
        if deja then continue; end if;   -- lot déjà décompté : pas de nouvelle sortie
      else
        if ml is not null then v := format('Lot saisi alors que la matière %s est en mode QUANTITÉ', k); exit; end if;
        if coalesce(mq, 0) <= 0 then v := format('Quantité consommée manquante (matière %s)', k); exit; end if;
      end if;
      eff := eff || jsonb_build_array(jsonb_build_object('site', p_site, 'article', ma, 'date', p_date, 'qte', -mq));
    end loop;
  end if;

  if v = 'OK' then
    msg := gfe.stock_negatif(p_entreprise, eff);
    if msg is not null then v := msg; end if;
  end if;

  insert into gfe.saisies_production (entreprise_id, date_saisie, site_id, produit_id, quantite, lot, peremption, saisi_par,
      remarque, controle, valide, created_by)
  values (p_entreprise, p_date, p_site, p_produit, p_quantite, p_lot, p_peremption, p_saisi_par, p_remarque, v, v = 'OK', auth.uid())
  returning id into sid;
  for k in 1..n loop
    it := p_matieres -> (k - 1);
    insert into gfe.saisies_production_matieres (production_id, rang, matiere_id, lot, quantite)
    values (sid, k, nullif(it->>'article', '')::uuid, nullif(trim(it->>'lot'), ''), nullif(it->>'quantite', '')::numeric);
  end loop;
  if v = 'OK' then perform gfe.ecrire_mouvements(p_entreprise, eff, 'production', sid); end if;
  return jsonb_build_object('id', sid, 'valide', v = 'OK', 'controle', v);
end $$;

-- ===== Vues de GESTION (le client ne les voit pas : RLS sur mouvements_stock et invoker) =====
create or replace view gfe.v_stock with (security_invoker = true) as
  select entreprise_id, article_id, site_id, sum(qte) as solde
  from gfe.mouvements_stock group by entreprise_id, article_id, site_id;

create or replace view gfe.v_cout_article with (security_invoker = true) as
with achats as (
  select article_id, sum(montant) as m, sum(quantite) as q from gfe.saisies_achat where valide group by article_id),
base as (
  select a.id, a.entreprise_id, a.nature,
    case when e.methode_cout = 'cmp' and coalesce(ac.q, 0) > 0 then ac.m / ac.q else a.prix_achat_ref end as cout
  from gfe.articles a join gfe.entreprises e on e.id = a.entreprise_id left join achats ac on ac.article_id = a.id)
select b.id as article_id, b.entreprise_id,
  case when b.nature = 'Produit fini'
       then coalesce((select sum(n.quantite * m.cout) from gfe.nomenclature n join base m on m.id = n.matiere_id where n.produit_id = b.id), 0)
       else b.cout end as cout
from base b;

-- Droits d'exécution
revoke all on function gfe.stock_negatif(uuid, jsonb), gfe.ecrire_mouvements(uuid, jsonb, text, uuid) from public, anon, authenticated;
grant execute on function gfe.saisir_vente(uuid, date, uuid, uuid, uuid, numeric, numeric, text, text) to authenticated;
grant execute on function gfe.saisir_achat(uuid, date, uuid, uuid, numeric, numeric, text, date, text, text) to authenticated;
grant execute on function gfe.saisir_autres(uuid, date, uuid, text, uuid, numeric, uuid, text, date, text, text, text) to authenticated;
grant execute on function gfe.saisir_production(uuid, date, uuid, uuid, numeric, text, date, text, text, jsonb) to authenticated;
grant select on gfe.v_stock, gfe.v_cout_article to authenticated;
