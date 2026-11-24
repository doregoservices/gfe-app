-- 0015 : module 2, étape 2 : opérations, tiers, paramètres et moteur d'écritures.
-- Règles reprises des formules du modèle « GFE - COMPTABLE - MODELE VIERGE »
-- (feuille MOTEUR, lignes 6 à 13 : 3 écritures de 2 lignes par opération ; SAISIE colonnes S à Y).
-- Remise / versement du dirigeant (REM, VER) : aucune écriture ; ils agissent seulement sur la caisse ou la banque.
-- Idempotente.

-- 1. Paramètres de référence par entreprise (PARAM B11 à B24 du modèle)
create table if not exists gfe.parametres_entreprise (
  entreprise_id uuid primary key references gfe.entreprises(id) on delete cascade,
  caisse text not null default '57110000',
  banque text not null default '52110000',
  intermediaire text not null default '58500000',
  attente text not null default '47100000',
  proprietaire text not null default '46210000',
  clients text not null default '41110000',
  fournisseurs text not null default '40110000',
  personnel text not null default '42200000',
  avances text not null default '42110000',
  cnps text not null default '43100000',
  its text not null default '44700000',
  plafond_especes numeric not null default 250000
);
alter table gfe.parametres_entreprise enable row level security;
drop policy if exists "param voit membre" on gfe.parametres_entreprise;
create policy "param voit membre" on gfe.parametres_entreprise for select to authenticated using (gfe.est_membre(entreprise_id));
drop policy if exists "param modifie comptable" on gfe.parametres_entreprise;
create policy "param modifie comptable" on gfe.parametres_entreprise for all to authenticated
  using (gfe.est_comptable_de(entreprise_id)) with check (gfe.est_comptable_de(entreprise_id));

-- 2. Tiers (clients, fournisseurs, personnel) par entreprise
create table if not exists gfe.tiers (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  code text not null,
  nom text not null,
  type text not null default 'Client' check (type in ('Client','Fournisseur','Autre')),
  compte_tiers text,       -- sous-compte (compte de tiers)
  compte_general text,     -- compte général du tiers (41x / 40x)
  unique (entreprise_id, code)
);
alter table gfe.tiers enable row level security;
drop policy if exists "tiers voit membre" on gfe.tiers;
create policy "tiers voit membre" on gfe.tiers for select to authenticated using (gfe.est_membre(entreprise_id));
drop policy if exists "tiers modifie comptable" on gfe.tiers;
create policy "tiers modifie comptable" on gfe.tiers for all to authenticated
  using (gfe.est_comptable_de(entreprise_id)) with check (gfe.est_comptable_de(entreprise_id));

-- 3. Opérations saisies (saisie client)
create table if not exists gfe.operations (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  date_operation date not null,
  type_code text not null references gfe.types_operation(code),
  mode text not null check (mode in ('Espèces','Banque')),
  libelle text not null,
  categorie text,            -- numero_interne du plan de comptes
  tiers_id uuid references gfe.tiers(id),
  montant numeric not null check (montant > 0),
  piece text,
  retenu boolean not null default true,
  created_at timestamptz not null default now()
);
alter table gfe.operations enable row level security;
drop policy if exists "operations voit membre" on gfe.operations;
create policy "operations voit membre" on gfe.operations for select to authenticated using (gfe.est_membre(entreprise_id));
drop policy if exists "operations saisit membre" on gfe.operations;
create policy "operations saisit membre" on gfe.operations for insert to authenticated
  with check (gfe.est_membre(entreprise_id));
drop policy if exists "operations modifie comptable" on gfe.operations;
create policy "operations modifie comptable" on gfe.operations for update to authenticated
  using (gfe.est_comptable_de(entreprise_id)) with check (gfe.est_comptable_de(entreprise_id));

-- 4. Moteur d'écritures : 2 lignes par écriture, 3 écritures au plus par opération
create or replace view gfe.v_ecritures with (security_invoker = true) as
with base as (
  select o.id as operation_id, o.entreprise_id, o.date_operation, o.type_code, o.mode, o.libelle, o.piece,
         o.montant, o.categorie, ty.est_od,
         (select pc.numero_interne from gfe.plan_comptes pc where pc.entreprise_id = o.entreprise_id
            and pc.numero_affiche = split_part(ty.compte_od_debit, ' ', 1)) as od_debit,
         (select pc.numero_interne from gfe.plan_comptes pc where pc.entreprise_id = o.entreprise_id
            and pc.numero_affiche = split_part(ty.compte_od_credit, ' ', 1)) as od_credit,
         p.caisse, p.banque, p.intermediaire, p.attente, p.proprietaire, p.clients, p.fournisseurs,
         p.personnel, p.avances, p.cnps, p.its,
         coalesce(t.compte_general, '') as tg, coalesce(t.compte_tiers, '') as tc, coalesce(t.nom, '') as tn,
         case when o.mode = 'Banque' then p.banque else p.caisse end as cb,
         case when o.mode = 'Banque' then 'BQ' else 'CA' end as jcb
  from gfe.operations o
  join gfe.types_operation ty on ty.code = o.type_code
  join gfe.parametres_entreprise p on p.entreprise_id = o.entreprise_id
  left join gfe.tiers t on t.id = o.tiers_id
  where o.retenu
),
lignes as (
  -- Écriture 1 : opération principale (MOTEUR lignes 6 et 7)
  select b.*, 1 as ecr,
    case b.type_code when 'VC' then 'VT' when 'VCR' then 'VT' when 'DC' then 'AC' when 'DCR' then 'AC'
                     when 'RETB' then 'BQ' when 'VERB' then 'CA' when 'ODAM' then 'OD' when 'ODCAP' then 'OD' when 'ODTEE' then 'OD'
                     else b.jcb end as journal,
    case b.type_code
      when 'VC'   then coalesce(nullif(b.tg,''), b.clients)
      when 'ENC'  then b.cb
      when 'VCR'  then b.tg
      when 'DC'   then b.categorie
      when 'DCR'  then b.categorie
      when 'REG'  then b.tg
      when 'SAL'  then b.personnel
      when 'AVA'  then b.avances
      when 'CNPS' then b.cnps
      when 'ITS'  then b.its
      when 'AUT'  then b.attente
      when 'RETB' then b.intermediaire
      when 'VERB' then b.intermediaire
      when 'ODAM' then b.od_debit when 'ODCAP' then b.od_debit when 'ODTEE' then b.od_debit
    end as compte_d,
    case b.type_code
      when 'VC'   then b.categorie
      when 'ENC'  then nullif(b.tg,'')
      when 'VCR'  then b.categorie
      when 'DC'   then coalesce(nullif(b.tg,''), b.fournisseurs)
      when 'DCR'  then nullif(b.tg,'')
      when 'REG'  then b.cb
      when 'SAL'  then b.cb
      when 'AVA'  then b.cb
      when 'CNPS' then b.cb
      when 'ITS'  then b.cb
      when 'AUT'  then b.cb
      when 'RETB' then b.banque
      when 'VERB' then b.caisse
      when 'ODAM' then b.od_credit when 'ODCAP' then b.od_credit when 'ODTEE' then b.od_credit
    end as compte_c
  from base b
  where b.type_code not in ('REM','VER')
  union all
  -- Écriture 2 : virements internes RETB (caisse ← intermédiaire) et VERB (banque ← intermédiaire)
  select b.*, 2,
    case when b.type_code = 'RETB' then 'CA' else 'BQ' end,
    case when b.type_code = 'RETB' then b.caisse else b.banque end,
    b.intermediaire
  from base b where b.type_code in ('RETB','VERB')
  union all
  -- Écriture 3 : règlement comptant (VC : caisse/banque ← client ; DC : fournisseur ← caisse/banque)
  select b.*, 3, b.jcb,
    case b.type_code when 'VC' then b.cb when 'DC' then coalesce(nullif(b.tg,''), b.fournisseurs) end,
    case b.type_code when 'VC' then coalesce(nullif(b.tg,''), b.clients) when 'DC' then b.cb end
  from base b where b.type_code in ('VC','DC')
),
ecr as (
  select l.operation_id, l.entreprise_id, l.date_operation, l.piece, l.libelle, l.ecr, l.journal,
         l.compte_d, l.compte_c, l.montant, l.tg, l.tc, l.tn
  from lignes l where l.compte_d is not null and l.compte_c is not null and l.compte_d <> ''
)
select e.operation_id, e.entreprise_id, e.ecr, e.journal, e.date_operation, e.piece, e.libelle,
       'D'::text as cote, e.compte_d as compte,
       case when e.compte_d = e.tg and e.tg <> '' then e.tc else null end as compte_tiers,
       case when e.compte_d = e.tg and e.tg <> '' then e.tn else null end as tiers,
       e.montant as debit, 0::numeric as credit
from ecr e
union all
select e.operation_id, e.entreprise_id, e.ecr, e.journal, e.date_operation, e.piece, e.libelle,
       'C', e.compte_c,
       case when e.compte_c = e.tg and e.tg <> '' then e.tc else null end,
       case when e.compte_c = e.tg and e.tg <> '' then e.tn else null end,
       0, e.montant
from ecr e;

-- 5. Contrôle : chaque écriture doit être équilibrée (débit = crédit)
create or replace view gfe.v_controle_equilibre with (security_invoker = true) as
select entreprise_id, operation_id, ecr, sum(debit) as total_debit, sum(credit) as total_credit,
       (sum(debit) = sum(credit)) as equilibre
from gfe.v_ecritures group by entreprise_id, operation_id, ecr;

grant select on gfe.v_ecritures, gfe.v_controle_equilibre to authenticated;
