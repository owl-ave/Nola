import { createMiddleware } from "hono/factory";
import type { Env, Variables } from "../types";

interface RateLimitConfig {
  max: number;
  window: string; // e.g. "60s", "300s"
}

const createRateLimit = (config: RateLimitConfig) =>
  createMiddleware<{ Bindings: Env; Variables: Variables }>(async (c, next) => {
    const key = `ratelimit:${c.req.path}:${c.get("userId") || c.req.header("cf-connecting-ip")}`;
    const current = await c.env.KV.get(key);
    const count = current ? parseInt(current) : 0;

    if (count >= config.max) {
      return c.json(
        {
          error: "Rate limit exceeded",
          retryAfter: config.window,
        },
        429
      );
    }

    const windowSeconds = parseInt(config.window.replace("s", ""));
    await c.env.KV.put(key, String(count + 1), {
      expirationTtl: windowSeconds,
    });

    await next();
  });

// Pre-configured rate limiters
export const standardRateLimit = createRateLimit({ max: 60, window: "60s" });
export const strictRateLimit = createRateLimit({ max: 10, window: "60s" });
export const transferRateLimit = createRateLimit({ max: 5, window: "300s" });
export const aiRateLimit = createRateLimit({ max: 20, window: "60s" });
export const adminRateLimit = createRateLimit({ max: 100, window: "60s" });
export const pinVerifyRateLimit = createRateLimit({ max: 3, window: "60s" });
