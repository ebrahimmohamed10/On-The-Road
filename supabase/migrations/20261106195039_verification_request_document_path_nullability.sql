-- Document paths are copied into verification_documents by the AFTER INSERT
-- trigger, then cleared from verification_requests to keep private paths out
-- of the request row. These columns must therefore allow NULL.
begin;

alter table public.verification_requests
  alter column id_front_path drop not null,
  alter column id_back_path drop not null,
  alter column selfie_path drop not null,
  alter column license_front_path drop not null,
  alter column license_back_path drop not null;

commit;
