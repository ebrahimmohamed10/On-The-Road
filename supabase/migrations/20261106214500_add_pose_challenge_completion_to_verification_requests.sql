-- Record when the app's on-device head-pose challenge completed.
-- This is client-reported telemetry, not a server-verified liveness result
-- and not a face-to-ID match.
alter table public.verification_requests
  add column client_pose_challenge_completed_at timestamptz;

comment on column public.verification_requests.client_pose_challenge_completed_at is
  'Client-reported completion time for the on-device ML Kit head-pose challenge. This is not identity matching or server-verified liveness.';

grant insert (client_pose_challenge_completed_at)
  on public.verification_requests to authenticated;
