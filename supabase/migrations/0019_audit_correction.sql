-- 0019 : journal d'audit automatique (exigé par la passation : « journal d'audit obligatoire sur les volets comptables et paie »).
-- Chaque création, modification ou suppression d'opération est enregistrée automatiquement (avant / après).
-- Aucune saisie manuelle : le déclencheur écrit seul. Le comptable consulte, personne ne peut l'effacer.
-- Idempotente.

create table if not exists gfe.journal_audit (
  id bigserial primary key,
  entreprise_id uuid,
  nom_table text not null,
  ligne_id uuid,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  utilisateur uuid,
  utilisateur_email text,
  date_action timestamptz not null default now(),
  avant jsonb,
  apres jsonb
);
alter table gfe.journal_audit enable row level security;
drop policy if exists "audit lu par comptable" on gfe.journal_audit;
create policy "audit lu par comptable" on gfe.journal_audit for select to authenticated
  using (gfe.est_comptable_de(entreprise_id));
-- Aucune politique d'écriture : seul le déclencheur (propriétaire) écrit.

create or replace function gfe.audit_operations() returns trigger
language plpgsql security definer set search_path = gfe, public, auth as $$
begin
  insert into gfe.journal_audit (entreprise_id, nom_table, ligne_id, action, utilisateur, utilisateur_email, avant, apres)
  values (
    coalesce(new.entreprise_id, old.entreprise_id), 'operations', coalesce(new.id, old.id), tg_op,
    auth.uid(), (select u.email::text from auth.users u where u.id = auth.uid()),
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

drop trigger if exists trg_audit_operations on gfe.operations;
create trigger trg_audit_operations after insert or update or delete on gfe.operations
  for each row execute function gfe.audit_operations();

-- Les correcteurs (comptable) peuvent modifier une opération : la politique « operations modifie comptable »
-- existe déjà (migration 0015) ; les contrôles de saisie (0017) s'appliquent aussi aux corrections.
grant select on gfe.journal_audit to authenticated;
