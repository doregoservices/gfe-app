-- Gestion des comptes clients par le comptable de l'entreprise.
-- Un client est un profil de rôle 'entreprise' rattaché à une entreprise (appartenances).

-- Le comptable voit les rattachements de ses entreprises
create policy "comptable voit les rattachements de ses entreprises" on gfe.appartenances
  for select to authenticated using (gfe.est_comptable_de(entreprise_id));

-- Rattacher un client existant (compte créé par e-mail) à une entreprise
create or replace function gfe.ajouter_client(p_entreprise uuid, p_email text) returns text
language plpgsql security definer set search_path = gfe, public, auth as $$
declare pid uuid; prole text;
begin
  if not gfe.est_comptable_de(p_entreprise) then
    raise exception 'Seul le comptable de cette entreprise peut ajouter un client';
  end if;
  select u.id into pid from auth.users u where lower(u.email) = lower(trim(p_email));
  if pid is null then
    raise exception 'Aucun compte pour cet e-mail. Créez-le d''abord.';
  end if;
  select role into prole from gfe.profils where id = pid;
  if prole = 'comptable' then
    raise exception 'Ce compte est un comptable, il ne peut pas être client';
  end if;
  insert into gfe.appartenances (profil_id, entreprise_id, role)
  values (pid, p_entreprise, 'utilisateur')
  on conflict (profil_id, entreprise_id) do nothing;
  return 'ok';
end $$;

-- Retirer un client d'une entreprise
create or replace function gfe.retirer_client(p_entreprise uuid, p_profil uuid) returns void
language plpgsql security definer set search_path = gfe, public as $$
begin
  if not gfe.est_comptable_de(p_entreprise) then
    raise exception 'Seul le comptable de cette entreprise peut retirer un client';
  end if;
  delete from gfe.appartenances where entreprise_id = p_entreprise and profil_id = p_profil;
end $$;

-- Lister les clients d'une entreprise (réservé au comptable)
create or replace function gfe.lister_clients(p_entreprise uuid)
returns table(profil_id uuid, nom text, email text)
language plpgsql stable security definer set search_path = gfe, public, auth as $$
begin
  if not gfe.est_comptable_de(p_entreprise) then
    raise exception 'Réservé au comptable de cette entreprise';
  end if;
  return query
    select a.profil_id, p.nom, u.email::text
    from gfe.appartenances a
    join gfe.profils p on p.id = a.profil_id
    join auth.users u on u.id = a.profil_id
    where a.entreprise_id = p_entreprise
    order by u.email;
end $$;

grant execute on function gfe.ajouter_client(uuid, text) to authenticated;
grant execute on function gfe.retirer_client(uuid, uuid) to authenticated;
grant execute on function gfe.lister_clients(uuid) to authenticated;
revoke all on function gfe.ajouter_client(uuid, text) from anon, public;
revoke all on function gfe.retirer_client(uuid, uuid) from anon, public;
revoke all on function gfe.lister_clients(uuid) from anon, public;
