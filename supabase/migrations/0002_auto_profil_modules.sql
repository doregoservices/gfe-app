-- Création automatique du profil à l'inscription
create or replace function gfe.creer_profil()
returns trigger language plpgsql security definer set search_path = gfe, public as $$
begin
  insert into gfe.profils (id, nom) values (new.id, coalesce(new.raw_user_meta_data->>'nom', new.email));
  return new;
end $$;

drop trigger if exists on_auth_user_cree on auth.users;
create trigger on_auth_user_cree after insert on auth.users
  for each row execute function gfe.creer_profil();

-- À la création d'une entreprise, les 3 modules existent, désactivés par défaut
create or replace function gfe.modules_par_defaut()
returns trigger language plpgsql security definer set search_path = gfe, public as $$
begin
  insert into gfe.modules_actifs (entreprise_id, module, actif)
  values (new.id, 'stock', false), (new.id, 'comptabilite', false), (new.id, 'rh_paie', false);
  return new;
end $$;

drop trigger if exists entreprise_modules on gfe.entreprises;
create trigger entreprise_modules after insert on gfe.entreprises
  for each row execute function gfe.modules_par_defaut();
