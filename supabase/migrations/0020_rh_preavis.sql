-- 0020 : RH, étape 1 : durée du préavis (décret n° 2026-198 du 15 avril 2026, art. 18.4 du Code du travail).
-- Barème modifiable : table gfe.rh_bareme_preavis. Seuils en mois d'ancienneté (borne basse incluse).
-- Idempotente.
--
-- Texte appliqué (loidici.biz, décret 2026-198) :
--  1° payés à l'heure, à la journée, à la semaine ou à la quinzaine, catégories 1 à 5 :
--     8 jours jusqu'à 6 mois ; 15 jours de 6 mois à 1 an ; 1 mois de 1 an à 6 ans ;
--     2 mois de 6 à 11 ans ; 3 mois de 11 à 16 ans ; 4 mois au-delà de 16 ans.
--  2° payés au mois, catégories 1 à 5 : 1 mois jusqu'à 6 ans ; 2 mois de 6 à 11 ans ; 3 mois de 11 à 16 ans ; 4 mois au-delà.
--  3° catégorie 6 et au-delà : 3 mois jusqu'à 16 ans ; 4 mois au-delà.
--  4° incapacité permanente partielle > 40 % : délai normal jusqu'à 6 mois ; deux fois le délai normal au-delà.

create table if not exists gfe.rh_reglages (
  cle text primary key,
  valeur numeric not null,
  libelle text not null,
  source text not null
);
alter table gfe.rh_reglages enable row level security;
drop policy if exists "reglages lisibles" on gfe.rh_reglages;
create policy "reglages lisibles" on gfe.rh_reglages for select to authenticated using (true);

create table if not exists gfe.rh_bareme_preavis (
  mode_paie text not null check (mode_paie in ('mois','heure')),
  categorie text not null check (categorie in ('cat1_5','cat6')),
  seuil_mois numeric not null,          -- ancienneté à partir de laquelle ce préavis s'applique (en mois)
  duree numeric not null,
  unite text not null check (unite in ('jours','mois')),
  primary key (mode_paie, categorie, seuil_mois)
);
alter table gfe.rh_bareme_preavis enable row level security;
drop policy if exists "bareme lisible" on gfe.rh_bareme_preavis;
create policy "bareme lisible" on gfe.rh_bareme_preavis for select to authenticated using (true);

insert into gfe.rh_reglages (cle, valeur, libelle, source) values
  ('preavis_incapacite_seuil_mois', 6, 'Incapacité > 40 % : seuil d''ancienneté pour le doublement (mois)', 'Décret 2026-198, 4°'),
  ('preavis_incapacite_multiplicateur', 2, 'Incapacité > 40 % : multiplicateur après le seuil', 'Décret 2026-198, 4°')
on conflict (cle) do nothing;

insert into gfe.rh_bareme_preavis (mode_paie, categorie, seuil_mois, duree, unite) values
  ('heure','cat1_5',   0,   8, 'jours'),
  ('heure','cat1_5',   6,  15, 'jours'),
  ('heure','cat1_5',  12,   1, 'mois'),
  ('heure','cat1_5',  72,   2, 'mois'),
  ('heure','cat1_5', 132,   3, 'mois'),
  ('heure','cat1_5', 192,   4, 'mois'),
  ('mois', 'cat1_5',   0,   1, 'mois'),
  ('mois', 'cat1_5',  72,   2, 'mois'),
  ('mois', 'cat1_5', 132,   3, 'mois'),
  ('mois', 'cat1_5', 192,   4, 'mois'),
  ('mois', 'cat6',     0,   3, 'mois'),
  ('mois', 'cat6',   192,   4, 'mois')
on conflict (mode_paie, categorie, seuil_mois) do nothing;

-- Durée du préavis pour un salarié. Ancienneté en mois (fractions comptées).
create or replace function gfe.duree_preavis(p_mode text, p_categorie text, p_anciennete_mois numeric, p_incapacite boolean default false)
returns table(duree numeric, unite text)
language plpgsql stable security definer set search_path = gfe, public as $$
declare b gfe.rh_bareme_preavis%rowtype; seuil numeric; mult numeric;
begin
  select * into b from gfe.rh_bareme_preavis
   where mode_paie = p_mode and categorie = p_categorie and seuil_mois <= coalesce(p_anciennete_mois, 0)
   order by seuil_mois desc limit 1;
  if not found then raise exception 'Aucun barème de préavis pour % / %', p_mode, p_categorie; end if;
  duree := b.duree; unite := b.unite;
  if p_incapacite then
    select valeur into seuil from gfe.rh_reglages where cle = 'preavis_incapacite_seuil_mois';
    select valeur into mult from gfe.rh_reglages where cle = 'preavis_incapacite_multiplicateur';
    if coalesce(p_anciennete_mois, 0) > seuil then duree := duree * mult; end if;
  end if;
  return next;
end $$;
grant execute on function gfe.duree_preavis(text, text, numeric, boolean) to authenticated;
