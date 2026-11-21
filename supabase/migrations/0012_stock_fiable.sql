-- 0012 : stock fiable. (PARAM B11 gouverne le lot du produit fini, de l'achat et des autres mouvements ;
-- les lots des matières en mode LOT restent toujours saisissables, comme dans le classeur.) Verrou par entreprise, contrôles serveur, inventaires recalculés,
-- annulation avec motif, journal, colonnes d'analyse.
-- Principe : chaque saisie valide est appliquée « à titre d'essai » ; si le stock devient négatif
-- à une date quelconque (ou si un inventaire change), la ligne est enregistrée en erreur et rien n'est appliqué.

-- ---------- Colonnes communes
alter table gfe.saisies_production add column if not exists annulee boolean not null default false,
  add column if not exists motif_annulation text, add column if not exists annulee_le timestamptz,
  add column if not exists created_by_email text, add column if not exists analyse1 numeric, add column if not exists analyse2 numeric;
alter table gfe.saisies_vente add column if not exists annulee boolean not null default false,
  add column if not exists motif_annulation text, add column if not exists annulee_le timestamptz, add column if not exists created_by_email text;
alter table gfe.saisies_achat add column if not exists annulee boolean not null default false,
  add column if not exists motif_annulation text, add column if not exists annulee_le timestamptz, add column if not exists created_by_email text;
alter table gfe.saisies_autres add column if not exists annulee boolean not null default false,
  add column if not exists motif_annulation text, add column if not exists annulee_le timestamptz, add column if not exists created_by_email text;

-- ---------- Journal des modifications (qui, quand, quoi)
create table if not exists gfe.journal (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid references gfe.entreprises(id) on delete cascade,
  at timestamptz not null default now(),
  email text not null,
  action text not null,
  table_nom text not null,
  ligne_id uuid,
  detail text
);
alter table gfe.journal enable row level security;
drop policy if exists "membre lit journal" on gfe.journal;
create policy "membre lit journal" on gfe.journal for select to authenticated using (gfe.est_membre(entreprise_id));

create or replace function gfe.journaliser() returns trigger language plpgsql security definer set search_path = gfe, public as $$
begin
  insert into gfe.journal (entreprise_id, email, action, table_nom, ligne_id, detail)
  values (coalesce(new.entreprise_id, old.entreprise_id), coalesce(auth.jwt()->>'email', 'système'), tg_op, tg_table_name,
          coalesce(new.id, old.id), case when tg_op = 'DELETE' then null else left(to_jsonb(new)::text, 2000) end);
  return coalesce(new, old);
end $$;

do $$ declare t text; begin
  foreach t in array array['sites','familles','commerciaux','articles','nomenclature','saisies_production','saisies_vente','saisies_achat','saisies_autres'] loop
    execute format('drop trigger if exists journal_%1$s on gfe.%1$I', t);
    execute format('create trigger journal_%1$s after insert or update or delete on gfe.%1$I for each row execute function gfe.journaliser()', t);
  end loop;
end $$;

-- ---------- Verrou et erreurs de stock
create or replace function gfe.verrou(p_e uuid) returns void language sql as $$
  select pg_advisory_xact_lock(hashtextextended(p_e::text, 0));
$$;

-- Recalcule les inventaires dans l'ordre des dates, puis vérifie qu'aucun stock n'est négatif
create or replace function gfe.recalculer(p_e uuid) returns void language plpgsql security definer set search_path = gfe, public as $$
declare r record; theo numeric; eff numeric; neg record;
begin
  delete from gfe.mouvements_stock where entreprise_id = p_e and source = 'inventaire';
  for r in select id, site_id, article_id, date_saisie, quantite from gfe.saisies_autres
           where entreprise_id = p_e and type = 'Inventaire (comptage)' and valide and not annulee
           order by date_saisie, created_at, id loop
    select coalesce(sum(qte), 0) into theo from gfe.mouvements_stock
      where entreprise_id = p_e and site_id = r.site_id and article_id = r.article_id and date_mvt <= r.date_saisie;
    eff := r.quantite - theo;
    update gfe.saisies_autres set effet = eff where id = r.id;
    if eff <> 0 then
      insert into gfe.mouvements_stock (entreprise_id, site_id, article_id, date_mvt, qte, source, source_id)
      values (p_e, r.site_id, r.article_id, r.date_saisie, eff, 'inventaire', r.id);
    end if;
  end loop;
  select a.designation, s.nom as site_nom, x.date_mvt, x.st into neg from (
    select site_id, article_id, date_mvt, sum(q) over (partition by site_id, article_id order by date_mvt) as st from (
      select site_id, article_id, date_mvt, sum(qte) as q from gfe.mouvements_stock where entreprise_id = p_e group by 1, 2, 3) j
  ) x join gfe.articles a on a.id = x.article_id join gfe.sites s on s.id = x.site_id
  where x.st < 0 order by x.date_mvt limit 1;
  if found then
    raise exception 'Refusé : stock négatif pour % sur % le % (stock résultant : %)',
      neg.designation, neg.site_nom, to_char(neg.date_mvt, 'DD/MM/YYYY'), round(neg.st)::text using errcode = 'GFE01';
  end if;
end $$;

create or replace function gfe.inserer_matieres(p_sid uuid, p_matieres jsonb) returns void language plpgsql security definer set search_path = gfe, public as $$
declare k int; it jsonb; n int := coalesce(jsonb_array_length(coalesce(p_matieres, '[]'::jsonb)), 0);
begin
  for k in 1..n loop
    it := p_matieres -> (k - 1);
    insert into gfe.saisies_production_matieres (production_id, rang, matiere_id, lot, quantite)
    values (p_sid, k, nullif(it->>'article', '')::uuid, nullif(trim(it->>'lot'), ''), nullif(it->>'quantite', '')::numeric);
  end loop;
end $$;

-- ---------- VENTE
create or replace function gfe.saisir_vente(p_entreprise uuid, p_date date, p_point uuid, p_commercial uuid,
  p_article uuid, p_quantite numeric, p_prix numeric, p_piece text, p_saisi_par text)
returns jsonb language plpgsql security definer set search_path = gfe, public as $$
declare e gfe.entreprises; s gfe.sites; a gfe.articles; v text := 'OK'; prix numeric; eff jsonb; sid uuid; ok boolean := false;
begin
  if not gfe.peut_ecrire(p_entreprise) then raise exception 'Accès refusé'; end if;
  perform gfe.verrou(p_entreprise);
  select * into e from gfe.entreprises where id = p_entreprise;
  select * into s from gfe.sites where id = p_point and entreprise_id = p_entreprise;
  select * into a from gfe.articles where id = p_article and entreprise_id = p_entreprise;
  if p_date is null or p_date < date '2000-01-01' or p_date > date '2100-12-31' then v := 'Date invalide';
  elsif p_point is null then v := 'Point de vente manquant';
  elsif s.id is null then v := 'Point de vente inconnu';
  elsif s.type <> 'Point de vente' then v := 'Site non point de vente';
  elsif e.opt_suivi_commercial and p_commercial is null then v := 'Commercial manquant';
  elsif not e.opt_suivi_commercial and p_commercial is not null then v := 'Suivi commercial désactivé (PARAM B14)';
  elsif e.opt_suivi_commercial and not exists (select 1 from gfe.commerciaux c where c.id = p_commercial and c.entreprise_id = p_entreprise) then v := 'Commercial inconnu';
  elsif p_article is null then v := 'Article manquant';
  elsif a.id is null or a.nature not in ('Produit fini', 'Marchandise') then v := 'Article non vendable';
  elsif coalesce(p_quantite, 0) <= 0 then v := 'Quantité invalide';
  elsif p_prix is not null and p_prix < 0 then v := 'Prix invalide';
  elsif p_saisi_par is not null and not e.opt_saisi_par then v := 'Saisi par désactivé (PARAM B13)';
  end if;
  prix := coalesce(p_prix, a.prix_vente);
  eff := jsonb_build_array(jsonb_build_object('site', p_point, 'article', p_article, 'date', p_date, 'qte', -p_quantite));
  if v = 'OK' then
    begin
      insert into gfe.saisies_vente (entreprise_id, date_saisie, point_id, commercial_id, article_id, quantite, prix_unitaire, montant,
          piece, saisi_par, controle, valide, created_by, created_by_email)
      values (p_entreprise, p_date, p_point, p_commercial, p_article, p_quantite, prix, p_quantite * prix, p_piece, p_saisi_par,
          'OK', true, auth.uid(), auth.jwt()->>'email') returning id into sid;
      perform gfe.ecrire_mouvements(p_entreprise, eff, 'vente', sid);
      perform gfe.recalculer(p_entreprise);
      ok := true;
    exception when sqlstate 'GFE01' then v := sqlerrm;
    end;
  end if;
  if not ok then
    insert into gfe.saisies_vente (entreprise_id, date_saisie, point_id, commercial_id, article_id, quantite, prix_unitaire, montant,
        piece, saisi_par, controle, valide, created_by, created_by_email)
    values (p_entreprise, p_date, p_point, p_commercial, p_article, p_quantite, prix,
        case when coalesce(p_quantite, 0) > 0 then p_quantite * prix end, p_piece, p_saisi_par, v, false, auth.uid(), auth.jwt()->>'email')
    returning id into sid;
  end if;
  return jsonb_build_object('id', sid, 'valide', ok, 'controle', case when ok then 'OK' else v end);
end $$;

-- ---------- ACHAT
create or replace function gfe.saisir_achat(p_entreprise uuid, p_date date, p_site uuid, p_article uuid, p_quantite numeric,
  p_prix numeric, p_lot text, p_peremption date, p_piece text, p_saisi_par text)
returns jsonb language plpgsql security definer set search_path = gfe, public as $$
declare e gfe.entreprises; s gfe.sites; a gfe.articles; v text := 'OK'; eff jsonb; sid uuid; ok boolean := false;
begin
  if not gfe.peut_ecrire(p_entreprise) then raise exception 'Accès refusé'; end if;
  perform gfe.verrou(p_entreprise);
  select * into e from gfe.entreprises where id = p_entreprise;
  select * into s from gfe.sites where id = p_site and entreprise_id = p_entreprise;
  select * into a from gfe.articles where id = p_article and entreprise_id = p_entreprise;
  if p_date is null or p_date < date '2000-01-01' or p_date > date '2100-12-31' then v := 'Date invalide';
  elsif p_site is null then v := 'Site manquant';
  elsif s.id is null then v := 'Site inconnu';
  elsif p_article is null then v := 'Article manquant';
  elsif a.id is null or a.nature not in ('Matière première', 'Marchandise', 'Autre stockable') then v := 'Article non achetable';
  elsif coalesce(p_quantite, 0) <= 0 then v := 'Quantité invalide';
  elsif p_prix is null or p_prix < 0 then v := 'Prix d''achat manquant ou négatif';
  elsif p_lot is not null and not e.opt_lot then v := 'N° de lot désactivé (PARAM B11)';
  elsif p_peremption is not null and not e.opt_peremption then v := 'Péremption désactivée (PARAM B12)';
  elsif p_saisi_par is not null and not e.opt_saisi_par then v := 'Saisi par désactivé (PARAM B13)';
  end if;
  eff := jsonb_build_array(jsonb_build_object('site', p_site, 'article', p_article, 'date', p_date, 'qte', p_quantite));
  if v = 'OK' then
    begin
      insert into gfe.saisies_achat (entreprise_id, date_saisie, site_id, article_id, quantite, prix_unitaire, montant, lot, peremption,
          piece, saisi_par, controle, valide, created_by, created_by_email)
      values (p_entreprise, p_date, p_site, p_article, p_quantite, p_prix, p_quantite * p_prix, p_lot, p_peremption, p_piece, p_saisi_par,
          'OK', true, auth.uid(), auth.jwt()->>'email') returning id into sid;
      perform gfe.ecrire_mouvements(p_entreprise, eff, 'achat', sid);
      perform gfe.recalculer(p_entreprise);
      ok := true;
    exception when sqlstate 'GFE01' then v := sqlerrm;
    end;
  end if;
  if not ok then
    insert into gfe.saisies_achat (entreprise_id, date_saisie, site_id, article_id, quantite, prix_unitaire, montant, lot, peremption,
        piece, saisi_par, controle, valide, created_by, created_by_email)
    values (p_entreprise, p_date, p_site, p_article, p_quantite, p_prix,
        case when coalesce(p_quantite, 0) > 0 and p_prix >= 0 then p_quantite * p_prix end, p_lot, p_peremption, p_piece, p_saisi_par,
        v, false, auth.uid(), auth.jwt()->>'email') returning id into sid;
  end if;
  return jsonb_build_object('id', sid, 'valide', ok, 'controle', case when ok then 'OK' else v end);
end $$;

-- ---------- AUTRES (stock initial, entrée, sortie, transfert, casse, don, consommation, inventaire)
create or replace function gfe.saisir_autres(p_entreprise uuid, p_date date, p_site uuid, p_type text, p_article uuid,
  p_quantite numeric, p_destination uuid, p_lot text, p_peremption date, p_motif text, p_remarque text, p_saisi_par text)
returns jsonb language plpgsql security definer set search_path = gfe, public as $$
declare e gfe.entreprises; s gfe.sites; a gfe.articles; v text := 'OK'; inv boolean; signe int;
  eff jsonb := '[]'::jsonb; sid uuid; ok boolean := false;
begin
  if not gfe.peut_ecrire(p_entreprise) then raise exception 'Accès refusé'; end if;
  perform gfe.verrou(p_entreprise);
  select * into e from gfe.entreprises where id = p_entreprise;
  select * into s from gfe.sites where id = p_site and entreprise_id = p_entreprise;
  select * into a from gfe.articles where id = p_article and entreprise_id = p_entreprise;
  inv := p_type = 'Inventaire (comptage)';
  signe := case when p_type in ('Stock initial', 'Entrée (autre)') then 1
                when p_type in ('Sortie (autre)', 'Casse ou perte', 'Don ou échantillon', 'Consommation interne', 'Transfert') then -1 end;
  if p_date is null or p_date < date '2000-01-01' or p_date > date '2100-12-31' then v := 'Date invalide';
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
  elsif p_type = 'Transfert' and not exists (select 1 from gfe.sites d where d.id = p_destination and d.entreprise_id = p_entreprise) then v := 'Destination inconnue';
  elsif p_lot is not null and not e.opt_lot then v := 'N° de lot désactivé (PARAM B11)';
  elsif p_peremption is not null and not e.opt_peremption then v := 'Péremption désactivée (PARAM B12)';
  elsif p_saisi_par is not null and not e.opt_saisi_par then v := 'Saisi par désactivé (PARAM B13)';
  end if;
  if v = 'OK' and not inv then
    if p_type = 'Transfert' then
      eff := jsonb_build_array(
        jsonb_build_object('site', p_site, 'article', p_article, 'date', p_date, 'qte', -p_quantite),
        jsonb_build_object('site', p_destination, 'article', p_article, 'date', p_date, 'qte', p_quantite));
    else
      eff := jsonb_build_array(jsonb_build_object('site', p_site, 'article', p_article, 'date', p_date, 'qte', signe * p_quantite));
    end if;
  end if;
  if v = 'OK' then
    begin
      insert into gfe.saisies_autres (entreprise_id, date_saisie, site_id, type, article_id, quantite, site_destination_id, lot,
          peremption, motif, remarque, saisi_par, controle, valide, created_by, created_by_email)
      values (p_entreprise, p_date, p_site, p_type, p_article, p_quantite, case when p_type = 'Transfert' then p_destination end,
          p_lot, p_peremption, p_motif, p_remarque, p_saisi_par, 'OK', true, auth.uid(), auth.jwt()->>'email') returning id into sid;
      if not inv then perform gfe.ecrire_mouvements(p_entreprise, eff, 'autres', sid); end if;
      perform gfe.recalculer(p_entreprise);
      ok := true;
    exception when sqlstate 'GFE01' then v := sqlerrm;
    end;
  end if;
  if not ok then
    insert into gfe.saisies_autres (entreprise_id, date_saisie, site_id, type, article_id, quantite, site_destination_id, lot,
        peremption, motif, remarque, saisi_par, controle, valide, created_by, created_by_email)
    values (p_entreprise, p_date, p_site, p_type, p_article, p_quantite, case when p_type = 'Transfert' then p_destination end,
        p_lot, p_peremption, p_motif, p_remarque, p_saisi_par, v, false, auth.uid(), auth.jwt()->>'email') returning id into sid;
  end if;
  return jsonb_build_object('id', sid, 'valide', ok, 'controle', case when ok then 'OK' else v end);
end $$;

-- ---------- PRODUCTION
create or replace function gfe.saisir_production(p_entreprise uuid, p_date date, p_site uuid, p_produit uuid, p_quantite numeric,
  p_lot text, p_peremption date, p_remarque text, p_saisi_par text, p_matieres jsonb)
returns jsonb language plpgsql security definer set search_path = gfe, public as $$
declare e gfe.entreprises; s gfe.sites; pr gfe.articles; v text := 'OK'; n int; k int; it jsonb;
  ma uuid; ml text; mq numeric; mart gfe.articles; deja boolean; eff jsonb := '[]'::jsonb; sid uuid; ok boolean := false;
begin
  if not gfe.peut_ecrire(p_entreprise) then raise exception 'Accès refusé'; end if;
  perform gfe.verrou(p_entreprise);
  select * into e from gfe.entreprises where id = p_entreprise;
  select * into s from gfe.sites where id = p_site and entreprise_id = p_entreprise;
  select * into pr from gfe.articles where id = p_produit and entreprise_id = p_entreprise;
  n := coalesce(jsonb_array_length(coalesce(p_matieres, '[]'::jsonb)), 0);
  if p_date is null or p_date < date '2000-01-01' or p_date > date '2100-12-31' then v := 'Date invalide';
  elsif e.type_activite = 'commerce' then v := 'Activité commerce : pas de fabrication (PARAM B6)';
  elsif p_site is null then v := 'Site manquant';
  elsif s.id is null then v := 'Site inconnu';
  elsif s.type <> 'Usine' then v := 'Site non usine';
  elsif p_produit is null then v := 'Produit manquant';
  elsif pr.id is null or pr.nature <> 'Produit fini' then v := 'Produit fini inconnu';
  elsif coalesce(p_quantite, 0) <= 0 then v := 'Quantité invalide';
  elsif n > e.nb_matieres then v := format('Matière %s saisie au-delà du nombre prévu (PARAM B22)', e.nb_matieres + 1);
  elsif p_lot is not null and not e.opt_lot then v := 'N° de lot désactivé (PARAM B11)';
  elsif p_peremption is not null and not e.opt_peremption then v := 'Péremption désactivée (PARAM B12)';
  elsif p_saisi_par is not null and not e.opt_saisi_par then v := 'Saisi par désactivé (PARAM B13)';
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
                       where p.entreprise_id = p_entreprise and p.valide and not p.annulee and m.matiere_id = ma and m.lot = ml) into deja;
        if deja and mq is not null then v := format('Quantité du lot à saisir une seule fois, sur la première fabrication du lot (matière %s)', k); exit; end if;
        if not deja and coalesce(mq, 0) <= 0 then v := format('Quantité consommée manquante (matière %s)', k); exit; end if;
        if deja then continue; end if;
      else
        if ml is not null then v := format('Lot saisi alors que la matière %s est en mode QUANTITÉ', k); exit; end if;
        if coalesce(mq, 0) <= 0 then v := format('Quantité consommée manquante (matière %s)', k); exit; end if;
      end if;
      eff := eff || jsonb_build_array(jsonb_build_object('site', p_site, 'article', ma, 'date', p_date, 'qte', -mq));
    end loop;
  end if;

  if v = 'OK' then
    begin
      insert into gfe.saisies_production (entreprise_id, date_saisie, site_id, produit_id, quantite, lot, peremption, saisi_par,
          remarque, controle, valide, created_by, created_by_email)
      values (p_entreprise, p_date, p_site, p_produit, p_quantite, p_lot, p_peremption, p_saisi_par, p_remarque, 'OK', true,
          auth.uid(), auth.jwt()->>'email') returning id into sid;
      perform gfe.inserer_matieres(sid, p_matieres);
      perform gfe.ecrire_mouvements(p_entreprise, eff, 'production', sid);
      perform gfe.recalculer(p_entreprise);
      ok := true;
    exception when sqlstate 'GFE01' then v := sqlerrm;
    end;
  end if;
  if not ok then
    insert into gfe.saisies_production (entreprise_id, date_saisie, site_id, produit_id, quantite, lot, peremption, saisi_par,
        remarque, controle, valide, created_by, created_by_email)
    values (p_entreprise, p_date, p_site, p_produit, p_quantite, p_lot, p_peremption, p_saisi_par, p_remarque, v, false,
        auth.uid(), auth.jwt()->>'email') returning id into sid;
    perform gfe.inserer_matieres(sid, p_matieres);
  end if;
  return jsonb_build_object('id', sid, 'valide', ok, 'controle', case when ok then 'OK' else v end);
end $$;

-- ---------- Annulation avec motif (la ligne reste visible, barrée ; son effet disparaît)
create or replace function gfe.annuler_saisie(p_table text, p_id uuid, p_motif text) returns jsonb
language plpgsql security definer set search_path = gfe, public as $$
declare eid uuid; n int;
begin
  if p_table not in ('saisies_production', 'saisies_vente', 'saisies_achat', 'saisies_autres') then raise exception 'Table inconnue'; end if;
  execute format('select entreprise_id from gfe.%I where id = $1', p_table) into eid using p_id;
  if eid is null then raise exception 'Ligne introuvable'; end if;
  if not gfe.peut_ecrire(eid) then raise exception 'Accès refusé'; end if;
  if nullif(trim(p_motif), '') is null then raise exception 'Motif d''annulation obligatoire'; end if;
  perform gfe.verrou(eid);
  if p_table = 'saisies_production' and exists (select 1 from gfe.saisies_production p where p.id = p_id and p.valide and not p.annulee)
     and exists (
       select 1 from gfe.saisies_production_matieres m1
       where m1.production_id = p_id and m1.quantite is not null and m1.lot is not null
         and exists (select 1 from gfe.saisies_production_matieres m2 join gfe.saisies_production p2 on p2.id = m2.production_id
                     where m2.production_id <> p_id and p2.valide and not p2.annulee
                       and m2.matiere_id = m1.matiere_id and m2.lot = m1.lot and m2.quantite is null)) then
    raise exception 'Annulation refusée : le lot de cette fabrication est réutilisé par des fabrications suivantes ; annulez-les d''abord';
  end if;
  execute format('update gfe.%I set annulee = true, motif_annulation = $2, annulee_le = now() where id = $1 and not annulee', p_table)
    using p_id, trim(p_motif);
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Cette ligne est déjà annulée'; end if;
  delete from gfe.mouvements_stock where source_id = p_id;
  perform gfe.recalculer(eid);
  return jsonb_build_object('annulee', true);
end $$;

-- ---------- Colonnes d'analyse de production (saisies par le comptable)
create or replace function gfe.definir_analyse(p_production uuid, p_a1 numeric, p_a2 numeric) returns void
language plpgsql security definer set search_path = gfe, public as $$
declare eid uuid;
begin
  select entreprise_id into eid from gfe.saisies_production where id = p_production;
  if eid is null or not gfe.est_comptable_de(eid) then raise exception 'Réservé au comptable de cette entreprise'; end if;
  update gfe.saisies_production set analyse1 = p_a1, analyse2 = p_a2 where id = p_production;
end $$;
revoke all on function gfe.definir_analyse(uuid, numeric, numeric) from public, anon;
grant execute on function gfe.definir_analyse(uuid, numeric, numeric) to authenticated;
revoke all on function gfe.annuler_saisie(text, uuid, text) from public, anon;
grant execute on function gfe.annuler_saisie(text, uuid, text) to authenticated;
grant execute on function gfe.saisir_vente(uuid, date, uuid, uuid, uuid, numeric, numeric, text, text) to authenticated;
grant execute on function gfe.saisir_achat(uuid, date, uuid, uuid, numeric, numeric, text, date, text, text) to authenticated;
grant execute on function gfe.saisir_autres(uuid, date, uuid, text, uuid, numeric, uuid, text, date, text, text, text) to authenticated;
grant execute on function gfe.saisir_production(uuid, date, uuid, uuid, numeric, text, date, text, text, jsonb) to authenticated;
