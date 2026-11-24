-- 0017 : module 2, étape 4 : contrôles de saisie, dates de saisie, activation des modules.
-- Contrôles repris du modèle (SAISIE colonnes AA à AN : mode, catégorie, tiers, plafond espèces, période).
-- Une opération non conforme est refusée à l'enregistrement (message précis pour le client).
-- Idempotente.

-- 1. Période de saisie et mode optionnel (types sans mode : VCR, DCR, OD, RETB, VERB)
alter table gfe.parametres_entreprise add column if not exists saisie_du date;
alter table gfe.parametres_entreprise add column if not exists saisie_au date;
alter table gfe.operations alter column mode drop not null;
alter table gfe.operations drop constraint if exists operations_mode_check;
alter table gfe.operations add constraint operations_mode_check check (mode is null or mode in ('Espèces','Banque'));

-- 2. Module actif
create or replace function gfe.module_actif(eid uuid, m text) returns boolean
language sql stable security definer set search_path = gfe, public as $$
  select exists (select 1 from gfe.modules_actifs ma where ma.entreprise_id = eid and ma.module = m and ma.actif);
$$;
grant execute on function gfe.module_actif(uuid, text) to authenticated;

-- Saisie des opérations : seulement si le module comptabilité est actif pour l'entreprise
drop policy if exists "operations saisit membre" on gfe.operations;
create policy "operations saisit membre" on gfe.operations for insert to authenticated
  with check (gfe.est_membre(entreprise_id) and gfe.module_actif(entreprise_id, 'comptabilite'));

-- 3. Contrôles à l'enregistrement
create or replace function gfe.controle_operation() returns trigger
language plpgsql security definer set search_path = gfe, public as $$
declare ty gfe.types_operation%rowtype; pa gfe.parametres_entreprise%rowtype; t gfe.tiers%rowtype;
begin
  select * into ty from gfe.types_operation where code = new.type_code;
  select * into pa from gfe.parametres_entreprise where entreprise_id = new.entreprise_id;
  if new.montant is null or new.montant <= 0 then raise exception 'Montant obligatoire (supérieur à 0)'; end if;
  if pa.saisie_du is not null and new.date_operation < pa.saisie_du then
    raise exception 'Date hors période : la saisie est ouverte à partir du %', pa.saisie_du;
  end if;
  if pa.saisie_au is not null and new.date_operation > pa.saisie_au then
    raise exception 'Date hors période : la saisie est ouverte jusqu''au %', pa.saisie_au;
  end if;
  if ty.mode_requis = 1 and new.mode is null then raise exception 'Mode (Espèces ou Banque) obligatoire pour ce type'; end if;
  if ty.mode_requis = 0 and new.mode is not null then raise exception 'Mode non utilisé pour ce type d''opération'; end if;
  if ty.categorie_requise = 1 and new.categorie is null then raise exception 'Catégorie obligatoire pour ce type'; end if;
  if ty.categorie_requise = 0 and new.categorie is not null then raise exception 'Catégorie non utilisée pour ce type'; end if;
  if new.categorie is not null and not exists (select 1 from gfe.plan_comptes pc
       where pc.entreprise_id = new.entreprise_id and pc.numero_interne = new.categorie) then
    raise exception 'Catégorie absente du plan de comptes';
  end if;
  if ty.tiers = 1 and new.tiers_id is null then raise exception 'Tiers obligatoire pour ce type'; end if;
  if ty.tiers = 0 and new.tiers_id is not null then raise exception 'Tiers non utilisé pour ce type'; end if;
  if new.tiers_id is not null then
    select * into t from gfe.tiers where id = new.tiers_id;
    if t.entreprise_id <> new.entreprise_id then raise exception 'Tiers d''une autre entreprise'; end if;
    if coalesce(t.compte_tiers, '') = '' or coalesce(t.compte_general, '') = '' then
      raise exception 'Tiers incomplet : compte de tiers et compte général obligatoires (%)', t.nom;
    end if;
  end if;
  if ty.sortie_especes and new.mode = 'Espèces' and new.montant > pa.plafond_especes then
    raise exception 'Sortie en espèces refusée : au-delà du plafond de % F', pa.plafond_especes;
  end if;
  return new;
end $$;

drop trigger if exists trg_controle_operation on gfe.operations;
create trigger trg_controle_operation before insert or update on gfe.operations
  for each row execute function gfe.controle_operation();

-- 4. Activation d'un module : chef uniquement
create or replace function gfe.activer_module(p_entreprise uuid, p_module text, p_actif boolean) returns void
language plpgsql security definer set search_path = gfe, public as $$
begin
  if not gfe.est_chef() then raise exception 'Réservé aux chefs (chef comptable ou chef du cabinet)'; end if;
  if p_module not in ('stock','comptabilite','rh_paie') then raise exception 'Module inconnu'; end if;
  insert into gfe.modules_actifs (entreprise_id, module, actif) values (p_entreprise, p_module, p_actif)
  on conflict (entreprise_id, module) do update set actif = excluded.actif;
end $$;
grant execute on function gfe.activer_module(uuid, text, boolean) to authenticated;
revoke all on function gfe.activer_module(uuid, text, boolean) from anon, public;

-- 5. Activer la comptabilité pour les entreprises de test (les chefs peuvent le faire depuis l'écran)
insert into gfe.modules_actifs (entreprise_id, module, actif)
select id, 'comptabilite', true from gfe.entreprises
on conflict (entreprise_id, module) do update set actif = true;
