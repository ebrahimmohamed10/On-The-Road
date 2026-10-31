import { createClient } from "npm:@supabase/supabase-js@2";

const PROJECT_URL = Deno.env.get("SUPABASE_URL");
const SECRET_KEYS = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
const SERVICE_KEY = SECRET_KEYS.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

// Replaced during deployment with the SHA-256 digest of the random token kept in Vault.
const EXPECTED_TOKEN_SHA256 = "02ab90c754148883a9e2b2853b942f4d330774200f395d7c9d373ace912acffd";
const MAX_BATCH = 20;
const ALLOWED_BUCKETS = new Set([
  "identity-documents",
  "vehicle-documents",
  "avatars",
]);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function safeMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.replace(/[\r\n\t]+/g, " ").slice(0, 500);
}

function retryAt(attempt: number): string {
  const minutes = Math.min(15 * 2 ** Math.max(0, attempt - 1), 24 * 60);
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

async function getOwnedStoragePaths(admin: ReturnType<typeof createClient>, userId: string) {
  const [identity, vehicle, profile] = await Promise.all([
    admin.from("verification_documents").select("storage_path").eq("user_id", userId),
    admin.from("vehicle_documents").select("storage_path").eq("user_id", userId),
    admin.from("profiles").select("avatar_path").eq("id", userId).maybeSingle(),
  ]);
  for (const result of [identity, vehicle, profile]) {
    if (result.error) throw result.error;
  }

  const rows: Array<{ bucket: string; path: string }> = [
    ...(identity.data ?? []).map((row) => ({ bucket: "identity-documents", path: row.storage_path })),
    ...(vehicle.data ?? []).map((row) => ({ bucket: "vehicle-documents", path: row.storage_path })),
  ];
  if (profile.data?.avatar_path) rows.push({ bucket: "avatars", path: profile.data.avatar_path });
  return rows.filter((row) => typeof row.path === "string" && row.path.length > 0);
}

async function getStorageJobsForPaths(
  admin: ReturnType<typeof createClient>,
  ownedPaths: Array<{ bucket: string; path: string }>,
) {
  const result: Array<{ bucket: string; path: string; status: string; delete_after: string }> = [];
  const byBucket = new Map<string, string[]>();
  for (const item of ownedPaths) byBucket.set(item.bucket, [...(byBucket.get(item.bucket) ?? []), item.path]);
  for (const [bucket, paths] of byBucket) {
    const { data, error } = await admin.from("storage_deletion_jobs")
      .select("bucket_id,object_path,status,delete_after")
      .eq("bucket_id", bucket)
      .in("object_path", paths);
    if (error) throw error;
    for (const row of data ?? []) result.push({
      bucket: row.bucket_id,
      path: row.object_path,
      status: row.status,
      delete_after: row.delete_after,
    });
  }
  const found = new Set(result.map((row) => `${row.bucket}\n${row.path}`));
  const missing = ownedPaths.filter((item) => !found.has(`${item.bucket}\n${item.path}`));
  if (missing.length) throw new Error("One or more owned files are missing a retention deletion job; manual review is required.");
  return result;
}

async function finishFailedAccountJob(admin: ReturnType<typeof createClient>, job: any, message: string, terminal = false) {
  const delay = terminal ? 100 * 365 * 24 * 60 * 60 * 1000 : null;
  const { error } = await admin.from("account_deletion_jobs").update({
    status: "failed",
    last_error: message.slice(0, 500),
    available_at: delay ? new Date(Date.now() + delay).toISOString() : retryAt(job.attempts),
  }).eq("id", job.id);
  if (error) throw error;
}

async function hasProtectedHistory(admin: ReturnType<typeof createClient>, userId: string): Promise<string | null> {
  const checks: Array<[string, string]> = [
    ["boarding_events", "recorded_by"],
    ["emergency_incidents", "reporter_id"],
    ["refund_requests", "requester_id"],
    ["report_assignments", "reviewer_id"],
    ["report_evidence", "uploaded_by"],
    ["reports", "reporter_id"],
    ["simulated_payments", "payee_id"],
    ["simulated_payments", "payer_id"],
    ["verification_reviews", "reviewer_id"],
  ];
  for (const [table, column] of checks) {
    const { count, error } = await admin.from(table).select("id", { count: "exact", head: true }).eq(column, userId);
    if (error) throw error;
    if ((count ?? 0) > 0) return `${table}.${column} has retained records; manual anonymization review is required.`;
  }
  return null;
}

async function processStorageJobs(admin: ReturnType<typeof createClient>) {
  const counts = { completed: 0, failed: 0, skipped: 0 };
  const staleAt = new Date(Date.now() - 30 * 60_000).toISOString();
  const recovered = await admin.from("storage_deletion_jobs").update({
    status: "pending",
    last_error: "Recovered an interrupted worker attempt.",
  }).eq("status", "processing").lt("updated_at", staleAt);
  if (recovered.error) throw recovered.error;

  const { data: jobs, error } = await admin.from("storage_deletion_jobs")
    .select("id,bucket_id,object_path,attempts,status,delete_after,updated_at")
    .in("status", ["pending", "failed"])
    .lte("delete_after", new Date().toISOString())
    .order("delete_after", { ascending: true })
    .limit(MAX_BATCH);
  if (error) throw error;

  for (const job of jobs ?? []) {
    if (!ALLOWED_BUCKETS.has(job.bucket_id) || !job.object_path || job.object_path.startsWith("/") || job.object_path.split("/").includes("..")) {
      const invalid = await admin.from("storage_deletion_jobs").update({ status: "failed", attempts: job.attempts + 1, last_error: "Invalid bucket or object path; manual review required." }).eq("id", job.id).eq("status", job.status);
      if (invalid.error) throw invalid.error;
      counts.failed++;
      continue;
    }

    const claimed = await admin.from("storage_deletion_jobs").update({ status: "processing", attempts: job.attempts + 1, last_error: null })
      .eq("id", job.id).eq("status", job.status).select("id").maybeSingle();
    if (claimed.error) throw claimed.error;
    if (!claimed.data) { counts.skipped++; continue; }

    const removed = await admin.storage.from(job.bucket_id).remove([job.object_path]);
    if (removed.error) {
      const updated = await admin.from("storage_deletion_jobs").update({
        status: "failed",
        delete_after: retryAt(job.attempts + 1),
        last_error: safeMessage(removed.error),
      }).eq("id", job.id);
      if (updated.error) throw updated.error;
      counts.failed++;
    } else {
      const updated = await admin.from("storage_deletion_jobs").update({ status: "completed", last_error: null }).eq("id", job.id);
      if (updated.error) throw updated.error;
      counts.completed++;
    }
  }
  return counts;
}

async function processAccountJobs(admin: ReturnType<typeof createClient>) {
  const counts = { disabled: 0, deleted: 0, failed: 0, deferred: 0, skipped: 0 };
  const staleAt = new Date(Date.now() - 30 * 60_000).toISOString();
  const recovered = await admin.from("account_deletion_jobs").update({
    status: "pending",
    available_at: new Date().toISOString(),
    last_error: "Recovered an interrupted worker attempt.",
  }).eq("status", "processing").lt("updated_at", staleAt);
  if (recovered.error) throw recovered.error;

  const { data: jobs, error } = await admin.from("account_deletion_jobs")
    .select("id,request_id,user_id,operation,status,attempts,available_at")
    .in("status", ["pending", "failed"])
    .lte("available_at", new Date().toISOString())
    .order("available_at", { ascending: true })
    .limit(10);
  if (error) throw error;

  for (const job of jobs ?? []) {
    const claimed = await admin.from("account_deletion_jobs").update({ status: "processing", attempts: job.attempts + 1, last_error: null })
      .eq("id", job.id).eq("status", job.status).select("id").maybeSingle();
    if (claimed.error) throw claimed.error;
    if (!claimed.data) { counts.skipped++; continue; }

    try {
      if (job.operation === "disable_auth_user") {
        const { error: banError } = await admin.auth.admin.updateUserById(job.user_id, { ban_duration: "876000h" });
        if (banError) throw banError;

        const ownedPaths = await getOwnedStoragePaths(admin, job.user_id);
        const storageJobs = await getStorageJobsForPaths(admin, ownedPaths);
        const retainUntil = storageJobs.reduce((latest, row) => Math.max(latest, Date.parse(row.delete_after)), Date.now());
        const { error: nextError } = await admin.from("account_deletion_jobs").update({
          operation: "delete_auth_user",
          status: "pending",
          available_at: new Date(retainUntil).toISOString(),
          attempts: 0,
          last_error: null,
        }).eq("id", job.id);
        if (nextError) throw nextError;
        counts.disabled++;
        continue;
      }

      if (job.operation !== "delete_auth_user") throw new Error("Unsupported account deletion operation.");

      const { data: activeTrips, error: tripError } = await admin.from("trips").select("id").eq("driver_id", job.user_id).in("status", ["draft", "published", "in_progress"]).limit(1);
      if (tripError) throw tripError;
      const { data: activeBookings, error: bookingError } = await admin.from("bookings").select("id").eq("passenger_id", job.user_id).in("status", ["pending", "confirmed"]).limit(1);
      if (bookingError) throw bookingError;
      if ((activeTrips?.length ?? 0) || (activeBookings?.length ?? 0)) {
        const deferred = await admin.from("account_deletion_jobs").update({ status: "pending", available_at: retryAt(1), last_error: "Deferred until the user's active trip or booking is resolved." }).eq("id", job.id);
        if (deferred.error) throw deferred.error;
        counts.deferred++;
        continue;
      }

      const ownedPaths = await getOwnedStoragePaths(admin, job.user_id);
      const storageJobs = await getStorageJobsForPaths(admin, ownedPaths);
      const storagePending = storageJobs.some((row) => row.status !== "completed");
      if (storagePending) {
        const deferred = await admin.from("account_deletion_jobs").update({ status: "pending", available_at: retryAt(1), last_error: "Deferred until retained identity and vehicle files are removed." }).eq("id", job.id);
        if (deferred.error) throw deferred.error;
        counts.deferred++;
        continue;
      }

      const { data: adminRoles, error: roleError } = await admin.from("user_roles").select("user_id").eq("role", "admin");
      if (roleError) throw roleError;
      const isAdmin = (adminRoles ?? []).some((row) => row.user_id === job.user_id);
      if (isAdmin && (adminRoles?.length ?? 0) <= 1) {
        await finishFailedAccountJob(admin, { ...job, attempts: job.attempts + 1 }, "Refusing to delete the last administrator. Assign another trusted administrator first.", true);
        counts.failed++;
        continue;
      }

      const protectedHistory = await hasProtectedHistory(admin, job.user_id);
      if (protectedHistory) {
        await finishFailedAccountJob(admin, { ...job, attempts: job.attempts + 1 }, protectedHistory, true);
        counts.failed++;
        continue;
      }

      const { error: deleteError } = await admin.auth.admin.deleteUser(job.user_id);
      if (deleteError && !deleteError.message.toLowerCase().includes("not found")) throw deleteError;
      const { error: completeError } = await admin.from("account_deletion_jobs").update({ status: "completed", last_error: null }).eq("id", job.id);
      if (completeError) throw completeError;
      counts.deleted++;
    } catch (error) {
      await finishFailedAccountJob(admin, { ...job, attempts: job.attempts + 1 }, safeMessage(error));
      counts.failed++;
    }
  }
  return counts;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!PROJECT_URL || !SERVICE_KEY) return json({ error: "Worker is missing its Supabase service configuration." }, 500);

  const suppliedToken = request.headers.get("x-account-deletion-token") ?? "";
  const expectedBytes = Uint8Array.from(EXPECTED_TOKEN_SHA256.match(/.{2}/g) ?? [], (byte) => parseInt(byte, 16));
  if (!suppliedToken || !constantTimeEqual(await sha256(suppliedToken), expectedBytes)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const admin = createClient(PROJECT_URL, SERVICE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const storage = await processStorageJobs(admin);
    const accounts = await processAccountJobs(admin);
    return json({ ok: true, storage, accounts, ranAt: new Date().toISOString() });
  } catch (error) {
    console.error("account-deletion-worker failed", safeMessage(error));
    return json({ error: "Worker run failed. Review the Edge Function logs." }, 500);
  }
});
