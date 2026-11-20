-- Rôles : comptable (cabinet) et entreprise (client).
-- Une entreprise est TOUJOURS attribuée à un comptable (NOT NULL + clé étrangère).
alter table gfe.profils add column if not exists role text not null default 'entreprise'
  check (role in ('comptable','entreprise'));

alter table gfe.entreprises add column if not exists comptable_id uuid references gfe.profils(id);

-- Reprise des données existantes : le compte admin de test devient comptable de GFE Test
update gfe.profils set role = 'comptable' where id = 'ac5d7220-889d-495b-b38b-01e94d9a420d';
update gfe.entreprises set comptable_id = 'ac5d7220-889d-495b-b38b-01e94d9a420d' where comptable_id is null;
alter table gfe.entreprises alter column comptable_id set not null;

create table if not exists gfe.historique_attributions (
  id uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null references gfe.entreprises(id) on delete cascade,
  ancien_comptable uuid references gfe.profils(id),
  nouveau_comptable uuid not null references gfe.profils(id),
  fait_par uuid references gfe.profils(id),
  date_attribution timestamptz not null default now()
);
alter table gfe.historique_attributions enable row level security;

-- Fonctions de droits
create or replace function gfe.est_comptable() returns boolean
language sql stable security definer set search_path = gfe, public as $$
  select exists (select 1 from gfe.profils p where p.id = auth.uid() and p.role = 'comptable');
$$;

create or replace function gfe.est_comptable_de(eid uuid) returns boolean
language sql stable security definer set search_path = gfe, public as $$
  select exists (select 1 from gfe.entreprises e where e.id = eid and e.comptable_id = auth.uid());
$$;

-- Un membre = le comptable de l'entreprise OU un utilisateur rattaché (tous rôles de client)
create or replace function gfe.est_membre(eid uuid) returns boolean
language sql stable security definer set search_path = gfe, public as $$
  select gfe.est_comptable_de(eid) or exists (
    select 1 from gfe.appartenances a where a.entreprise_id = eid and a.profil_id = auth.uid());
$$;

-- Écriture : le comptable de l'entreprise, ou un administrateur/utilisateur rattaché
create or replace function gfe.peut_ecrire(eid uuid) returns boolean
language sql stable security definer set search_path = gfe, public as $$
  select gfe.est_comptable_de(eid) or exists (
    select 1 from gfe.appartenances a where a.entreprise_id = eid and a.profil_id = auth.uid()
      and a.role in ('admin','utilisateur'));
$$;

create or replace function gfe.mon_role() returns text
language sql stable security definer set search_path = gfe, public as $$
  select p.role from gfe.profils p where p.id = auth.uid();
$$;

-- Création d'entreprise : réservée aux comptables ; l'entreprise leur est attribuée
create or replace function gfe.creer_entreprise(p_nom text) returns uuid
language plpgsql security definer set search_path = gfe, public as $$
declare eid uuid;
begin
  if not gfe.est_comptable() then raise exception 'Réservé aux comptables'; end if;
  if nullif(trim(p_nom), '') is null then raise exception 'Nom de l''entreprise obligatoire'; end if;
  insert into gfe.entreprises (nom, comptable_id) values (trim(p_nom), auth.uid()) returning id into eid;
  return eid;
end $$;

-- Liste des comptables (pour la réattribution)
create or replace function gfe.lister_comptables() returns table(id uuid, nom text)
language sql stable security definer set search_path = gfe, public as $$
  select p.id, p.nom from gfe.profils p where p.role = 'comptable' and gfe.est_comptable() order by p.nom;
$$;

-- Réattribution : seul le comptable actuel peut transférer l'entreprise à un autre comptable
create or replace function gfe.reattribuer_entreprise(p_entreprise uuid, p_nouveau uuid) returns void
language plpgsql security definer set search_path = gfe, public as $$
declare ancien uuid;
begin
  if not gfe.est_comptable_de(p_entreprise) then
    raise exception 'Seul le comptable actuel peut réattribuer cette entreprise';
  end if;
  if not exists (select 1 from gfe.profils where id = p_nouveau and role = 'comptable') then
    raise exception 'Le destinataire doit être un comptable';
  end if;
  select comptable_id into ancien from gfe.entreprises where id = p_entreprise;
  update gfe.entreprises set comptable_id = p_nouveau where id = p_entreprise;
  -- L'ancien comptable perd tout accès, sauf rattachement explicite comme utilisateur client
  delete from gfe.appartenances where entreprise_id = p_entreprise and profil_id = ancien;
  insert into gfe.historique_attributions (entreprise_id, ancien_comptable, nouveau_comptable, fait_par)
  values (p_entreprise, ancien, p_nouveau, auth.uid());
end $$;

-- Mise à jour des droits de lecture des entreprises pour le comptable
drop policy if exists "membre voit son entreprise" on gfe.entreprises;
create policy "membre voit son entreprise" on gfe.entreprises for select to authenticated using (gfe.est_membre(id));
drop policy if exists "membre voit son profil" on gfe.profils;
create policy "membre voit son profil" on gfe.profils for select to authenticated using (id = auth.uid());

create policy "comptable lit historique" on gfe.historique_attributions for select to authenticated
  using (gfe.est_comptable_de(entreprise_id));

grant select on gfe.historique_attributions to authenticated;
grant execute on function gfe.est_comptable_de(uuid) to authenticated;
grant execute on function gfe.est_comptable() to authenticated;
grant execute on function gfe.mon_role() to authenticated;
grant execute on function gfe.creer_entreprise(text) to authenticated;
grant execute on function gfe.lister_comptables() to authenticated;
grant execute on function gfe.reattribuer_entreprise(uuid, uuid) to authenticated;
revoke all on function gfe.creer_entreprise(text) from anon;
revoke all on function gfe.reattribuer_entreprise(uuid, uuid) from anon;
