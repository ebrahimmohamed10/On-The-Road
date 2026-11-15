import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405, headers: corsHeaders });
  }

  const authorization = request.headers.get("Authorization");
  const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
  const publishableKey = publishableKeys.default ?? Deno.env.get("SUPABASE_ANON_KEY");
  if (!authorization || !publishableKey) {
    return Response.json({ error: "unauthorized" }, { status: 401, headers: corsHeaders });
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return Response.json({ error: "unauthorized" }, { status: 401, headers: corsHeaders });
  }

  let body: { imageBase64?: unknown; contentType?: unknown };
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "invalid_json" }, { status: 400, headers: corsHeaders });
  }
  const imageBase64 = body.imageBase64;
  const contentType = body.contentType;
  if (typeof imageBase64 !== "string" || imageBase64.length < 100 || imageBase64.length > 7_000_000) {
    return Response.json({ error: "invalid_image" }, { status: 400, headers: corsHeaders });
  }
  if (contentType !== "image/jpeg" && contentType !== "image/png") {
    return Response.json({ error: "unsupported_image_type" }, { status: 415, headers: corsHeaders });
  }

  const googleApiKey = Deno.env.get("GOOGLE_CLOUD_VISION_API_KEY");
  if (!googleApiKey) {
    return Response.json({ error: "ocr_provider_not_configured" }, { status: 503, headers: corsHeaders });
  }

  let visionResponse: Response;
  try {
    visionResponse = await fetch(
      `https://vision.googleapis.com/v1/images:annotate?key=${encodeURIComponent(googleApiKey)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          requests: [{
            image: { content: imageBase64 },
            features: [{ type: "DOCUMENT_TEXT_DETECTION", maxResults: 1 }],
            imageContext: { languageHints: ["ar", "en"] },
          }],
        }),
      },
    );
  } catch {
    // Never log the request or exception: the request URL contains the API key.
    return Response.json({ error: "ocr_provider_unreachable" }, { status: 502, headers: corsHeaders });
  }

  let vision: any;
  try {
    vision = await visionResponse.json();
  } catch {
    return Response.json({ error: "ocr_provider_invalid_response" }, { status: 502, headers: corsHeaders });
  }

  // Return only Google's stable error code and HTTP status. Do not expose its
  // message, the API key, or any recognized identity data in diagnostics.
  const providerError = vision.error ?? vision.responses?.[0]?.error;
  if (!visionResponse.ok || providerError) {
    const allowedCodes = new Set([
      "API_KEY_INVALID",
      "PERMISSION_DENIED",
      "SERVICE_DISABLED",
      "BILLING_DISABLED",
      "RESOURCE_EXHAUSTED",
      "QUOTA_EXCEEDED",
      "INVALID_ARGUMENT",
      "UNAUTHENTICATED",
    ]);
    const rawCode = typeof providerError?.status === "string" ? providerError.status : "";
    const providerCode = allowedCodes.has(rawCode) ? rawCode : "OTHER";
    const allowedReasons = new Set([
      "API_KEY_INVALID",
      "API_KEY_SERVICE_BLOCKED",
      "API_KEY_HTTP_REFERRER_BLOCKED",
      "API_KEY_IP_ADDRESS_BLOCKED",
      "SERVICE_DISABLED",
      "BILLING_DISABLED",
      "CONSUMER_INVALID",
      "CONSUMER_SUSPENDED",
      "ACCESS_TOKEN_SCOPE_INSUFFICIENT",
      "RATE_LIMIT_EXCEEDED",
      "DAILY_LIMIT_EXCEEDED",
    ]);
    const reasonDetails = Array.isArray(providerError?.details)
      ? providerError.details
      : [];
    const rawReason = reasonDetails.find(
      (detail: any) => typeof detail?.reason === "string" && allowedReasons.has(detail.reason),
    )?.reason;
    const providerReason = typeof rawReason === "string" ? rawReason : "UNKNOWN";
    console.error("Google Vision OCR request failed", {
      httpStatus: visionResponse.status,
      providerCode,
      providerReason,
    });
    return Response.json(
      { error: "ocr_provider_failed", providerCode, providerReason },
      { status: 502, headers: corsHeaders },
    );
  }

  const text = vision.responses?.[0]?.fullTextAnnotation?.text ?? "";
  return Response.json({ text }, { headers: corsHeaders });
});
