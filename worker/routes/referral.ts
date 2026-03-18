import { Hono } from "hono";
import type { Env, Variables, CreateReferralRequest, ReferralResponse } from "../types";
import { privyAuth } from "../middleware/auth";
import { standardRateLimit } from "../middleware/rateLimit";

const referral = new Hono<{ Bindings: Env; Variables: Variables }>();

// Get my referral info
referral.get("/", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");

  const ref = await c.env.DB.prepare(
    "SELECT * FROM referrals WHERE user_id = ?"
  ).bind(userId).first();

  if (!ref) return c.json({ error: "No referral code found. Create one first." }, 404);

  const count = await c.env.DB.prepare(
    "SELECT COUNT(*) as count FROM referral_uses WHERE referral_id = ?"
  ).bind((ref as Record<string, unknown>).id).first<{ count: number }>();

  return c.json({
    referralCode: (ref as Record<string, unknown>).code,
    referralCount: count?.count || 0,
    earnings: (ref as Record<string, unknown>).earnings || "0.00",
    tier: getTier(count?.count || 0),
  });
});

// Create referral code
referral.post("/create", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<CreateReferralRequest>();

  // Check if user already has a code
  const existing = await c.env.DB.prepare(
    "SELECT id FROM referrals WHERE user_id = ?"
  ).bind(userId).first();

  if (existing) return c.json({ error: "You already have a referral code" }, 409);

  const code = body.code || generateCode();

  // Check uniqueness
  const taken = await c.env.DB.prepare(
    "SELECT id FROM referrals WHERE code = ?"
  ).bind(code).first();

  if (taken) return c.json({ error: "This code is already taken" }, 409);

  const id = crypto.randomUUID();
  await c.env.DB.prepare(
    "INSERT INTO referrals (id, user_id, code, earnings, created_at) VALUES (?, ?, ?, '0.00', datetime('now'))"
  ).bind(id, userId, code).run();

  return c.json({ referralCode: code }, 201);
});

// Apply referral code (for new users)
referral.post("/apply", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const { code } = await c.req.json<{ code: string }>();

  if (!code) return c.json({ error: "Referral code is required" }, 400);

  // Check if already used a referral
  const alreadyUsed = await c.env.DB.prepare(
    "SELECT id FROM referral_uses WHERE referred_user_id = ?"
  ).bind(userId).first();

  if (alreadyUsed) return c.json({ error: "You have already used a referral code" }, 409);

  const ref = await c.env.DB.prepare(
    "SELECT * FROM referrals WHERE code = ?"
  ).bind(code).first<{ id: string; user_id: string }>();

  if (!ref) return c.json({ error: "Invalid referral code" }, 404);
  if (ref.user_id === userId) return c.json({ error: "Cannot use your own referral code" }, 400);

  await c.env.DB.prepare(
    "INSERT INTO referral_uses (id, referral_id, referred_user_id, created_at) VALUES (?, ?, ?, datetime('now'))"
  ).bind(crypto.randomUUID(), ref.id, userId).run();

  return c.json({ applied: true, referralCode: code });
});

// Get referral leaderboard (public)
referral.get("/leaderboard", async (c) => {
  const top = await c.env.DB.prepare(
    "SELECT r.code, COUNT(ru.id) as referral_count FROM referrals r LEFT JOIN referral_uses ru ON r.id = ru.referral_id GROUP BY r.id ORDER BY referral_count DESC LIMIT 10"
  ).all();

  return c.json({ leaderboard: top.results });
});

function getTier(count: number): ReferralResponse["tier"] {
  if (count >= 50) return "platinum";
  if (count >= 20) return "gold";
  if (count >= 5) return "silver";
  return "bronze";
}

function generateCode(): string {
  return `NOLA-${Math.random().toString(36).substring(2, 8).toUpperCase()}`;
}

export default referral;
