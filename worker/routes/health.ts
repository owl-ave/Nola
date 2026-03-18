import { Hono } from "hono";
import type { Env, Variables } from "../types";

const health = new Hono<{ Bindings: Env; Variables: Variables }>();

// Public health check - no auth required
health.get("/", async (c) => {
  return c.json({
    status: "ok",
    service: "nola-api",
    version: "1.0.0",
    timestamp: new Date().toISOString(),
  });
});

// Detailed health check - no auth required
health.get("/ready", async (c) => {
  try {
    // Check DB connectivity
    await c.env.DB.prepare("SELECT 1").first();
    // Check KV
    await c.env.KV.get("health-check");

    return c.json({
      status: "ready",
      checks: {
        database: "ok",
        kv: "ok",
      },
    });
  } catch (error) {
    return c.json(
      {
        status: "degraded",
        checks: {
          database: error instanceof Error ? error.message : "unknown",
        },
      },
      503
    );
  }
});

export default health;
