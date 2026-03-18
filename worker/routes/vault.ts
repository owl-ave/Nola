import { Hono } from "hono";
import type { Env, Variables, DepositRequest, VaultResponse } from "../types";
import { privyAuth } from "../middleware/auth";
import { standardRateLimit, strictRateLimit } from "../middleware/rateLimit";
import { idempotent } from "../middleware/idempotency";

const vault = new Hono<{ Bindings: Env; Variables: Variables }>();

// List user vaults
vault.get("/", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const vaults = await c.env.DB.prepare(
    "SELECT * FROM vaults WHERE user_id = ? ORDER BY created_at DESC"
  ).bind(userId).all();
  return c.json({ vaults: vaults.results });
});

// Create a deposit (lock funds in vault)
vault.post("/deposit", privyAuth(), strictRateLimit, idempotent, async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<DepositRequest>();

  if (!body.walletId || !body.amount || !body.lockDuration) {
    return c.json({ error: "Missing required fields: walletId, amount, lockDuration" }, 400);
  }

  if (!["30d", "90d", "180d", "365d"].includes(body.lockDuration)) {
    return c.json({ error: "lockDuration must be 30d, 90d, 180d, or 365d" }, 400);
  }

  if (parseFloat(body.amount) < 100) {
    return c.json({ error: "Minimum deposit is 100 USDC" }, 400);
  }

  // APY based on lock duration
  const apyMap: Record<string, number> = {
    "30d": 4.5,
    "90d": 6.0,
    "180d": 8.0,
    "365d": 12.0,
  };

  const vaultId = crypto.randomUUID();
  const days = parseInt(body.lockDuration);
  const lockUntil = new Date(Date.now() + days * 86400000).toISOString();

  await c.env.DB.prepare(
    "INSERT INTO vaults (id, user_id, wallet_id, amount, apy, lock_until, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'active', datetime('now'))"
  ).bind(vaultId, userId, body.walletId, body.amount, apyMap[body.lockDuration], lockUntil).run();

  const response: VaultResponse = {
    vaultId,
    amount: body.amount,
    apy: apyMap[body.lockDuration],
    lockUntil,
    status: "active",
  };
  return c.json(response, 201);
});

// Get vault details
vault.get("/:vaultId", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const vaultId = c.req.param("vaultId");

  const result = await c.env.DB.prepare(
    "SELECT * FROM vaults WHERE id = ? AND user_id = ?"
  ).bind(vaultId, userId).first();

  if (!result) return c.json({ error: "Vault not found" }, 404);
  return c.json(result);
});

// Withdraw from matured vault
vault.post("/:vaultId/withdraw", privyAuth(), strictRateLimit, idempotent, async (c) => {
  const userId = c.get("userId");
  const vaultId = c.req.param("vaultId");

  const v = await c.env.DB.prepare(
    "SELECT * FROM vaults WHERE id = ? AND user_id = ?"
  ).bind(vaultId, userId).first<{ lock_until: string; status: string; amount: string; apy: number }>();

  if (!v) return c.json({ error: "Vault not found" }, 404);
  if (v.status !== "active") return c.json({ error: "Vault is not active" }, 400);

  const lockUntil = new Date(v.lock_until);
  if (lockUntil > new Date()) {
    return c.json({ error: "Vault is still locked", lockUntil: v.lock_until }, 400);
  }

  // Calculate earnings
  const principal = parseFloat(v.amount);
  const earnings = principal * (v.apy / 100);
  const total = (principal + earnings).toFixed(2);

  await c.env.DB.prepare(
    "UPDATE vaults SET status = 'withdrawn', withdrawn_at = datetime('now') WHERE id = ?"
  ).bind(vaultId).run();

  return c.json({ vaultId, principal: v.amount, earnings: earnings.toFixed(2), total, status: "withdrawn" });
});

// Get vault APY rates
vault.get("/rates/current", async (c) => {
  // Public endpoint - no auth required
  return c.json({
    rates: [
      { duration: "30d", apy: 4.5, minDeposit: "100" },
      { duration: "90d", apy: 6.0, minDeposit: "100" },
      { duration: "180d", apy: 8.0, minDeposit: "100" },
      { duration: "365d", apy: 12.0, minDeposit: "100" },
    ],
  });
});

export default vault;
