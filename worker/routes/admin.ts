import { Hono } from "hono";
import type { Env, Variables, AdminUserResponse } from "../types";
import { adminAuth } from "../middleware/auth";
import { adminRateLimit } from "../middleware/rateLimit";

const admin = new Hono<{ Bindings: Env; Variables: Variables }>();

// List all users (admin only)
admin.get("/users", adminAuth(), adminRateLimit, async (c) => {
  const page = parseInt(c.req.query("page") || "1");
  const limit = parseInt(c.req.query("limit") || "50");
  const offset = (page - 1) * limit;

  const users = await c.env.DB.prepare(
    "SELECT u.id, u.email, COUNT(w.id) as wallet_count, u.kyc_status, u.created_at FROM users u LEFT JOIN wallets w ON u.id = w.user_id GROUP BY u.id ORDER BY u.created_at DESC LIMIT ? OFFSET ?"
  ).bind(limit, offset).all();

  const total = await c.env.DB.prepare("SELECT COUNT(*) as count FROM users").first<{ count: number }>();

  return c.json({ users: users.results, total: total?.count || 0, page, limit });
});

// Get user details (admin)
admin.get("/users/:userId", adminAuth(), adminRateLimit, async (c) => {
  const userId = c.req.param("userId");

  const user = await c.env.DB.prepare(
    "SELECT * FROM users WHERE id = ?"
  ).bind(userId).first();

  if (!user) return c.json({ error: "User not found" }, 404);

  const wallets = await c.env.DB.prepare(
    "SELECT * FROM wallets WHERE user_id = ?"
  ).bind(userId).all();

  const cards = await c.env.DB.prepare(
    "SELECT * FROM cards WHERE user_id = ?"
  ).bind(userId).all();

  return c.json({ user, wallets: wallets.results, cards: cards.results });
});

// Freeze user account (admin)
admin.post("/users/:userId/freeze", adminAuth(), adminRateLimit, async (c) => {
  const userId = c.req.param("userId");
  const { reason } = await c.req.json<{ reason: string }>();

  if (!reason) return c.json({ error: "Reason is required" }, 400);

  await c.env.DB.prepare(
    "UPDATE users SET status = 'frozen', freeze_reason = ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(reason, userId).run();

  // Freeze all user's cards
  await c.env.DB.prepare(
    "UPDATE cards SET status = 'frozen' WHERE user_id = ? AND status = 'active'"
  ).bind(userId).run();

  return c.json({ userId, status: "frozen", reason });
});

// Unfreeze user account (admin)
admin.post("/users/:userId/unfreeze", adminAuth(), adminRateLimit, async (c) => {
  const userId = c.req.param("userId");

  await c.env.DB.prepare(
    "UPDATE users SET status = 'active', freeze_reason = NULL, updated_at = datetime('now') WHERE id = ?"
  ).bind(userId).run();

  return c.json({ userId, status: "active" });
});

// Update KYC status (admin)
admin.patch("/users/:userId/kyc", adminAuth(), adminRateLimit, async (c) => {
  const userId = c.req.param("userId");
  const { kycStatus } = await c.req.json<{ kycStatus: "verified" | "rejected" }>();

  if (!["verified", "rejected"].includes(kycStatus)) {
    return c.json({ error: "kycStatus must be verified or rejected" }, 400);
  }

  await c.env.DB.prepare(
    "UPDATE users SET kyc_status = ?, updated_at = datetime('now') WHERE id = ?"
  ).bind(kycStatus, userId).run();

  return c.json({ userId, kycStatus });
});

// Get platform stats (admin)
admin.get("/stats", adminAuth(), adminRateLimit, async (c) => {
  const userCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM users").first<{ count: number }>();
  const walletCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM wallets").first<{ count: number }>();
  const vaultTotal = await c.env.DB.prepare("SELECT SUM(CAST(amount AS REAL)) as total FROM vaults WHERE status = 'active'").first<{ total: number }>();
  const cardCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM cards WHERE status = 'active'").first<{ count: number }>();

  return c.json({
    users: userCount?.count || 0,
    wallets: walletCount?.count || 0,
    activeVaultTvl: vaultTotal?.total?.toFixed(2) || "0.00",
    activeCards: cardCount?.count || 0,
  });
});

// Get system audit log (admin)
admin.get("/audit-log", adminAuth(), adminRateLimit, async (c) => {
  const limit = parseInt(c.req.query("limit") || "100");
  const logs = await c.env.DB.prepare(
    "SELECT * FROM audit_log ORDER BY created_at DESC LIMIT ?"
  ).bind(limit).all();
  return c.json({ logs: logs.results });
});

export default admin;
