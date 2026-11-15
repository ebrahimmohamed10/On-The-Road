-- Allow authenticated users to read this single field on rows already
-- visible to them under verification_requests RLS policies.
grant select (client_pose_challenge_completed_at)
  on public.verification_requests to authenticated;
