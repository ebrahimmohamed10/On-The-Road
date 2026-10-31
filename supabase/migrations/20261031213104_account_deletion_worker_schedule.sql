begin;

create extension if not exists pg_net;

do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'account-deletion-worker'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'account-deletion-worker',
    '*/15 * * * *',
    $cron$
      select net.http_post(
        url := 'https://chwbyhqcmxedhfezdmfi.supabase.co/functions/v1/account-deletion-worker',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-account-deletion-token', (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'account_deletion_worker_token'
            limit 1
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 10000
      );
    $cron$
  );
end
$$;

commit;
