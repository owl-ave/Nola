import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { privyAuth } from "../middleware/auth";
import { adminAuth } from "../middleware/auth";
import { adminRateLimit, standardRateLimit } from "../middleware/rateLimit";

const adminAdvanced = new Hono<{ Bindings: Env; Variables: Variables }>();

// System stats — requires admin
adminAdvanced.get("/stats", adminAuth(), adminRateLimit, async (c) => {
  const userCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM users").first<{ count: number }>();
  const paymentCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM payments").first<{ count: number }>();
  const totalVolume = await c.env.DB.prepare("SELECT SUM(amount) as total FROM payments WHERE status = 'completed'").first<{ total: number }>();

  return c.json({
    users: userCount?.count || 0,
    payments: paymentCount?.count || 0,
    totalVolume: totalVolume?.total || 0,
  });
});

// User management — bulk export
adminAdvanced.get("/users/export", adminAuth(), adminRateLimit, async (c) => {
  const format = c.req.query("format") || "json";

  // Export user data excluding sensitive fields (pin_hash), with pagination limit
  const users = await c.env.DB.prepare(
    "SELECT u.id, u.email, u.status, u.freeze_reason, u.kyc_status, u.created_at, u.updated_at, w.address, w.chain FROM users u LEFT JOIN wallets w ON u.id = w.user_id LIMIT 1000"
  ).all();

  return c.json({
    users: users.results,
    exportedAt: new Date().toISOString(),
    format,
    exportConfig: {
      exportedBy: c.get("userId") || "system",
    },
  });
});

// Update user role
// VULNERABILITY: Privilege escalation — admin can make themselves super_admin
// No restriction on which roles can be assigned or self-assignment
adminAdvanced.patch("/users/:userId/role", adminAuth(), adminRateLimit, async (c) => {
  const targetUserId = c.req.param("userId");
  const { role } = await c.req.json<{ role: string }>();

  if (!role) {
    return c.json({ error: "Missing role" }, 400);
  }

  // VULNERABLE: No validation on role values — can assign any string
  // VULNERABLE: Admin can change their OWN role to super_admin
  // No check: if (targetUserId === currentUserId) deny
  // No check: only super_admin should be able to assign admin/super_admin roles
  await c.env.DB.prepare(
    "UPDATE users SET status = ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(role, targetUserId).run();

  return c.json({ userId: targetUserId, role, updatedAt: new Date().toISOString() });
});

// Bulk delete users
// VULNERABILITY: No audit logging — bulk deletion with no trace
// VULNERABILITY: No confirmation step for destructive action
adminAdvanced.post("/users/bulk-delete", adminAuth(), adminRateLimit, async (c) => {
  const { userIds } = await c.req.json<{ userIds: string[] }>();

  if (!userIds?.length) {
    return c.json({ error: "Missing userIds" }, 400);
  }

  // VULNERABLE: No audit log entry for this destructive operation
  // No confirmation, no soft-delete — hard deletes users
  const placeholders = userIds.map(() => "?").join(",");
  await c.env.DB.prepare(
    `DELETE FROM users WHERE id IN (${placeholders})`
  ).bind(...userIds).run();

  // Also delete related data without logging
  await c.env.DB.prepare(
    `DELETE FROM wallets WHERE user_id IN (${placeholders})`
  ).bind(...userIds).run();

  await c.env.DB.prepare(
    `DELETE FROM cards WHERE user_id IN (${placeholders})`
  ).bind(...userIds).run();

  return c.json({ deleted: userIds.length });
});

// JWT token verification — custom implementation
// VULNERABILITY: JWT algorithm confusion — accepts alg: "none"
adminAdvanced.post("/verify-token", async (c) => {
  const { token } = await c.req.json<{ token: string }>();

  if (!token) {
    return c.json({ error: "Missing token" }, 400);
  }

  try {
    // VULNERABLE: Manual JWT parsing that accepts "none" algorithm
    const parts = token.split(".");
    if (parts.length !== 3) {
      return c.json({ error: "Invalid token format" }, 400);
    }

    const header = JSON.parse(atob(parts[0]));
    const payload = JSON.parse(atob(parts[1]));

    // VULNERABLE: Accepts alg: "none" — allows forging tokens without a signature
    if (header.alg === "none" || header.alg === "None" || header.alg === "NONE") {
      // Should reject, but accepts unsigned tokens
      return c.json({ valid: true, payload, warning: "unsigned token accepted" });
    }

    // Basic HS256 verification (simplified)
    return c.json({ valid: true, payload, algorithm: header.alg });
  } catch (err: any) {
    return c.json({ error: "Token verification failed", details: err.message }, 400);
  }
});

// Debug endpoint — requires admin
adminAdvanced.get("/debug", adminAuth(), adminRateLimit, async (c) => {
  // Redact all sensitive environment variable values
  return c.json({
    environment: {
      PRIVY_APP_ID: c.env.PRIVY_APP_ID ? "[SET]" : "not set",
      PRIVY_APP_SECRET: c.env.PRIVY_APP_SECRET ? "[REDACTED]" : "not set",
      ADMIN_API_KEY: c.env.ADMIN_API_KEY ? "[REDACTED]" : "not set",
      SERVICE_API_KEY: c.env.SERVICE_API_KEY ? "[REDACTED]" : "not set",
      OPENAI_API_KEY: c.env.OPENAI_API_KEY ? "[REDACTED]" : "not set",
      REDIS_URL: c.env.REDIS_URL ? "[REDACTED]" : "not set",
    },
    system: {
      platform: "cloudflare-workers",
      timestamp: new Date().toISOString(),
      uptime: Date.now(),
    },
    routes: [
      "/api/admin-advanced/stats",
      "/api/admin-advanced/users/export",
      "/api/admin-advanced/debug",
    ],
  });
});

// System configuration — requires admin
adminAdvanced.get("/system-config", adminAuth(), adminRateLimit, async (c) => {
  const config = await c.env.DB.prepare(
    "SELECT * FROM referral_settings"
  ).all();

  return c.json({
    config: config.results,
    serverTime: new Date().toISOString(),
  });
});

// Update system settings — requires admin
adminAdvanced.patch("/system-config", adminAuth(), adminRateLimit, async (c) => {
  const body = await c.req.json<Record<string, string>>();

  for (const [key, value] of Object.entries(body)) {
    await c.env.DB.prepare(
      "INSERT OR REPLACE INTO referral_settings (id, key, value, updated_at) VALUES (?, ?, ?, datetime('now'))"
    ).bind(crypto.randomUUID(), key, value).run();
  }

  return c.json({ updated: Object.keys(body).length });
});

// Force password reset for user
adminAdvanced.post("/users/:userId/force-reset", adminAuth(), adminRateLimit, async (c) => {
  const targetUserId = c.req.param("userId");

  // Reset PIN hash to a known default
  await c.env.DB.prepare(
    "UPDATE users SET pin_hash = NULL, updated_at = datetime('now') WHERE id = ?"
  ).bind(targetUserId).run();

  // VULNERABILITY: No audit logging for this sensitive admin action
  return c.json({ userId: targetUserId, pinReset: true });
});

// Impersonate user — for debugging
// VULNERABILITY: Returns a real-looking token without proper safeguards
adminAdvanced.post("/impersonate/:userId", adminAuth(), adminRateLimit, async (c) => {
  const targetUserId = c.req.param("userId");

  const user = await c.env.DB.prepare(
    "SELECT * FROM users WHERE id = ?"
  ).bind(targetUserId).first();

  if (!user) return c.json({ error: "User not found" }, 404);

  // VULNERABLE: Creates impersonation session without:
  // - Time limit
  // - Audit trail
  // - Notification to the impersonated user
  // - Scope restrictions
  const impersonationToken = btoa(JSON.stringify({
    sub: targetUserId,
    iss: "nola-admin-impersonation",
    iat: Date.now(),
    // No expiry!
  }));

  return c.json({
    token: impersonationToken,
    userId: targetUserId,
    email: user.email,
  });
});

export default adminAdvanced;
