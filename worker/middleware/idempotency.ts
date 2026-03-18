import { createMiddleware } from "hono/factory";
import type { Env, Variables } from "../types";

/**
 * Idempotency middleware. Checks for x-idempotency-key header
 * and returns cached response if the same key was used before.
 */
export const idempotent = createMiddleware<{
  Bindings: Env;
  Variables: Variables;
}>(async (c, next) => {
  const key = c.req.header("x-idempotency-key");
  if (!key) {
    await next();
    return;
  }

  const cacheKey = `idempotent:${c.req.path}:${key}`;
  const cached = await c.env.KV.get(cacheKey);
  if (cached) {
    const parsed = JSON.parse(cached);
    return c.json(parsed.body, parsed.status);
  }

  await next();

  // Cache the response for 24 hours
  if (c.res.status >= 200 && c.res.status < 300) {
    const body = await c.res.clone().json();
    await c.env.KV.put(
      cacheKey,
      JSON.stringify({ body, status: c.res.status }),
      { expirationTtl: 86400 }
    );
  }
});
