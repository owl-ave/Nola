import { createMiddleware } from "hono/factory";
import type { Env, Variables } from "../types";

/**
 * Privy JWT authentication middleware.
 * Verifies the Bearer token against Privy's JWKS endpoint.
 * Sets userId and userEmail on context variables.
 */
export const privyAuth = () =>
  createMiddleware<{ Bindings: Env; Variables: Variables }>(async (c, next) => {
    const authHeader = c.req.header("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return c.json({ error: "Missing or invalid authorization header" }, 401);
    }

    const token = authHeader.slice(7);
    try {
      // Verify JWT with Privy
      const response = await fetch(
        `https://auth.privy.io/api/v1/token/verify`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "privy-app-id": c.env.PRIVY_APP_ID,
            Authorization: `Basic ${btoa(
              `${c.env.PRIVY_APP_ID}:${c.env.PRIVY_APP_SECRET}`
            )}`,
          },
          body: JSON.stringify({ token }),
        }
      );

      if (!response.ok) {
        return c.json({ error: "Invalid or expired token" }, 401);
      }

      const data = (await response.json()) as {
        userId: string;
        email?: string;
      };
      c.set("userId", data.userId);
      c.set("userEmail", data.email || "");
    } catch {
      return c.json({ error: "Authentication failed" }, 401);
    }

    await next();
  });

/**
 * API key authentication for service-to-service calls.
 * Checks x-api-key header against SERVICE_API_KEY env var.
 */
export const apiKeyAuth = createMiddleware<{
  Bindings: Env;
  Variables: Variables;
}>(async (c, next) => {
  const apiKey = c.req.header("x-api-key");
  if (!apiKey || apiKey !== c.env.SERVICE_API_KEY) {
    return c.json({ error: "Invalid API key" }, 401);
  }
  await next();
});

/**
 * Admin authentication. Requires both Privy JWT and admin role.
 */
export const adminAuth = () =>
  createMiddleware<{ Bindings: Env; Variables: Variables }>(async (c, next) => {
    // First verify JWT
    const authHeader = c.req.header("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return c.json({ error: "Missing authorization" }, 401);
    }

    const adminKey = c.req.header("x-admin-key");
    if (!adminKey || adminKey !== c.env.ADMIN_API_KEY) {
      return c.json({ error: "Insufficient permissions" }, 403);
    }

    c.set("isAdmin", true);
    await next();
  });

/**
 * HMAC signature verification for webhook callbacks.
 */
export const hmacAuth = (secretEnvKey: keyof Env) =>
  createMiddleware<{ Bindings: Env; Variables: Variables }>(async (c, next) => {
    const signature = c.req.header("x-signature-256");
    if (!signature) {
      return c.json({ error: "Missing signature" }, 401);
    }

    const body = await c.req.text();
    const secret = c.env[secretEnvKey] as string;

    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    );
    const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
    const expected = `sha256=${Array.from(new Uint8Array(sig))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")}`;

    if (signature !== expected) {
      return c.json({ error: "Invalid signature" }, 401);
    }

    await next();
  });
