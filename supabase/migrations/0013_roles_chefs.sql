-- 0013 : rôles chef comptable et chef du cabinet.
-- Hiérarchie (validée le 23/11) :
--   chef_cabinet  : voit et fait tout comme le chef comptable ; crée, bloque et supprime les chefs comptables.
--   chef_comptable: crée et attribue les entreprises, crée les comptables, active les modules,
--                   crée et bloque les comptables. Ne crée pas de chef comptable.
--   comptable     : utilise GESTION de ses entreprises (et de celles attribuées).
--   entreprise    : client, saisie seulement.
-- Idempotente. À exécuter une fois dans l'éditeur SQL Supabase (projet GFE).

-- 1. Rôles étendus et blocage de compte
alter table gfe.profils drop constraint if exists profils_role_check;
alter table gfe.profils add constraint profils_role_check
  check (role in ('chef_cabinet','chef_comptable','comptable','entreprise'));
alter table gfe.profils add column if not exists bloque boolean not null default false;

-- 2. Fonctions d'aide
create or replace function gfe.est_chef_cabinet() returns boolean
language sql stable security definer set search_path = gfe, public as $$
  select exists (select 1 from gfe.profils p where p.id = auth.uid() and p.role = 'chef_cabinet' and not p.bloque);
$$;

create or replace function gfe.est_chef() returns boolean
language sql stable security definer set search_path = gfe, public as $$
  select exists (select 1 from gfe.profils p where p.id = auth.uid()
                 and p.role in ('chef_cabinet','chef_comptable') and not p.bloque);
$$;

-- Comptable (ou chef) actif
create or replace function gfe.est_comptable() returns boolean
language sql stable security definer set search_path = gfe, public as $$
  select exists (select 1 from gfe.profils p where p.id = auth.uid()
                 and p.role in ('comptable','chef_comptable','chef_cabinet') and not p.bloque);
$$;

-- Un chef voit et agit sur toutes les entreprises ; un comptable seulement sur les siennes
create or replace function gfe.est_comptable_de(eid uuid) returns boolean
language sql stable security definer set search_path = gfe, public as $$
  select gfe.est_chef() or exists (
    select 1 from gfe.entreprises e where e.id = eid and e.comptable_id = auth.uid()
      and exists (select 1 from gfe.profils p where p.id = auth.uid() and not p.bloque));
$$;

-- mon_role : renvoie 'bloque' si le compte est bloqué
create or replace function gfe.mon_role() returns text
language sql stable security definer set search_path = gfe, public as $$
  select case when p.bloque then 'bloque' else p.role end from gfe.profils p where p.id = auth.uid();
$$;

-- 3. Gestion des comptes (chef comptable et chef du cabinet)
-- Attribue un rôle à un compte existant (créé au préalable par son e-mail).
create or replace function gfe.definir_role(p_email text, p_role text) returns text
language plpgsql security definer set search_path = gfe, public, auth as $$
declare pid uuid; actuel text;
begin
  if p_role not in ('chef_comptable','comptable') then
    raise exception 'Rôle inconnu : %', p_role;
  end if;
  if p_role = 'chef_comptable' and not gfe.est_chef_cabinet() then
    raise exception 'Seul le chef du cabinet peut créer un chef comptable';
  end if;
  if not gfe.est_chef() then
    raise exception 'Réservé aux chefs (chef comptable ou chef du cabinet)';
  end if;
  select u.id into pid from auth.users u where lower(u.email) = lower(trim(p_email));
  if pid is null then raise exception 'Aucun compte pour cet e-mail. Créez-le d''abord.'; end if;
  select role into actuel from gfe.profils where id = pid;
  if actuel = 'chef_cabinet' then raise exception 'Ce compte est le chef du cabinet : rôle non modifiable'; end if;
  if actuel = 'chef_comptable' and not gfe.est_chef_cabinet() then
    raise exception 'Seul le chef du cabinet peut modifier un chef comptable';
  end if;
  if actuel is null then
    insert into gfe.profils (id, nom, role) values (pid, trim(p_email), p_role);
  else
    update gfe.profils set role = p_role where id = pid;
  end if;
  return 'Rôle « ' || p_role || ' » attribué à ' || trim(p_email);
end $$;

-- Bloque ou débloque un compte. Le chef du cabinet peut bloquer un chef comptable.
create or replace function gfe.bloquer_compte(p_profil uuid, p_bloque boolean) returns void
language plpgsql security definer set search_path = gfe, public as $$
declare cible text;
begin
  if not gfe.est_chef() then raise exception 'Réservé aux chefs'; end if;
  select role into cible from gfe.profils where id = p_profil;
  if cible is null then raise exception 'Compte introuvable'; end if;
  if cible = 'chef_cabinet' then raise exception 'Le chef du cabinet ne peut pas être bloqué'; end if;
  if cible = 'chef_comptable' and not gfe.est_chef_cabinet() then
    raise exception 'Seul le chef du cabinet peut bloquer un chef comptable';
  end if;
  update gfe.profils set bloque = p_bloque where id = p_profil;
end $$;

-- Retire le rôle (le compte redevient client). Réservé au chef du cabinet pour un chef comptable.
create or replace function gfe.retirer_role(p_profil uuid) returns void
language plpgsql security definer set search_path = gfe, public as $$
declare cible text;
begin
  if not gfe.est_chef() then raise exception 'Réservé aux chefs'; end if;
  select role into cible from gfe.profils where id = p_profil;
  if cible = 'chef_cabinet' then raise exception 'Le chef du cabinet ne peut pas être retiré'; end if;
  if cible = 'chef_comptable' and not gfe.est_chef_cabinet() then
    raise exception 'Seul le chef du cabinet peut retirer un chef comptable';
  end if;
  update gfe.profils set role = 'entreprise' where id = p_profil;
end $$;

-- Liste des comptes du cabinet (comptables et chefs), pour les écrans d'administration
create or replace function gfe.lister_comptes_cabinet()
returns table(id uuid, email text, role text, bloque boolean)
language plpgsql stable security definer set search_path = gfe, public, auth as $$
begin
  if not gfe.est_chef() then raise exception 'Réservé aux chefs'; end if;
  return query
    select p.id, u.email::text, p.role, p.bloque
    from gfe.profils p join auth.users u on u.id = p.id
    where p.role in ('chef_cabinet','chef_comptable','comptable')
    order by p.role, u.email;
end $$;

-- 4. Droits d'exécution
grant execute on function gfe.est_chef() to authenticated;
grant execute on function gfe.est_chef_cabinet() to authenticated;
grant execute on function gfe.definir_role(text, text) to authenticated;
grant execute on function gfe.bloquer_compte(uuid, boolean) to authenticated;
grant execute on function gfe.retirer_role(uuid) to authenticated;
grant execute on function gfe.lister_comptes_cabinet() to authenticated;
revoke all on function gfe.definir_role(text, text) from anon, public;
revoke all on function gfe.bloquer_compte(uuid, boolean) from anon, public;
revoke all on function gfe.retirer_role(uuid) from anon, public;
revoke all on function gfe.lister_comptes_cabinet() from anon, public;

-- 5. Chef du cabinet : compte à créer ensuite par e-mail (aucun compte créé ici).
-- Exemple à exécuter après création du compte dans Supabase Auth (remplacer l'e-mail) :
-- update gfe.profils set role = 'chef_cabinet'
--   where id = (select id from auth.users where email = 'CHEF@EXEMPLE.COM');
