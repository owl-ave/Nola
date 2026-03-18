import { Hono } from "hono";
import type { Env, Variables, CreateCardRequest, CardResponse } from "../types";
import { privyAuth } from "../middleware/auth";
import { standardRateLimit, strictRateLimit } from "../middleware/rateLimit";

const card = new Hono<{ Bindings: Env; Variables: Variables }>();

// List user cards
card.get("/", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const cards = await c.env.DB.prepare(
    "SELECT id, last4, card_type, status, spending_limit, current_spend, created_at FROM cards WHERE user_id = ? AND status != 'cancelled'"
  ).bind(userId).all();
  return c.json({ cards: cards.results });
});

// Create a new card
card.post("/create", privyAuth(), strictRateLimit, async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<CreateCardRequest>();

  if (!body.walletId || !body.cardType || !body.spendingLimit) {
    return c.json({ error: "Missing required fields: walletId, cardType, spendingLimit" }, 400);
  }

  if (!["virtual", "physical"].includes(body.cardType)) {
    return c.json({ error: "cardType must be virtual or physical" }, 400);
  }

  if (body.spendingLimit < 10 || body.spendingLimit > 50000) {
    return c.json({ error: "spendingLimit must be between 10 and 50000" }, 400);
  }

  // Verify wallet ownership
  const wallet = await c.env.DB.prepare(
    "SELECT id FROM wallets WHERE id = ? AND user_id = ?"
  ).bind(body.walletId, userId).first();

  if (!wallet) return c.json({ error: "Wallet not found" }, 404);

  const cardId = crypto.randomUUID();
  const last4 = Math.floor(1000 + Math.random() * 9000).toString();

  await c.env.DB.prepare(
    "INSERT INTO cards (id, user_id, wallet_id, last4, card_type, status, spending_limit, currency, created_at) VALUES (?, ?, ?, ?, ?, 'active', ?, ?, datetime('now'))"
  ).bind(cardId, userId, body.walletId, last4, body.cardType, body.spendingLimit, body.currency || "USD").run();

  const response: CardResponse = {
    cardId,
    last4,
    cardType: body.cardType,
    status: "active",
    spendingLimit: body.spendingLimit,
    currentSpend: 0,
  };
  return c.json(response, 201);
});

// Get card details
card.get("/:cardId", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const cardId = c.req.param("cardId");

  const result = await c.env.DB.prepare(
    "SELECT * FROM cards WHERE id = ? AND user_id = ?"
  ).bind(cardId, userId).first();

  if (!result) return c.json({ error: "Card not found" }, 404);
  return c.json(result);
});

// Freeze card
card.post("/:cardId/freeze", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const cardId = c.req.param("cardId");

  const result = await c.env.DB.prepare(
    "UPDATE cards SET status = 'frozen', updated_at = datetime('now') WHERE id = ? AND user_id = ? AND status = 'active'"
  ).bind(cardId, userId).run();

  if (!result.meta.changes) return c.json({ error: "Card not found or not active" }, 404);
  return c.json({ cardId, status: "frozen" });
});

// Unfreeze card
card.post("/:cardId/unfreeze", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const cardId = c.req.param("cardId");

  const result = await c.env.DB.prepare(
    "UPDATE cards SET status = 'active', updated_at = datetime('now') WHERE id = ? AND user_id = ? AND status = 'frozen'"
  ).bind(cardId, userId).run();

  if (!result.meta.changes) return c.json({ error: "Card not found or not frozen" }, 404);
  return c.json({ cardId, status: "active" });
});

// Update spending limit
card.patch("/:cardId/limit", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const cardId = c.req.param("cardId");
  const { spendingLimit } = await c.req.json<{ spendingLimit: number }>();

  if (!spendingLimit || spendingLimit < 10 || spendingLimit > 50000) {
    return c.json({ error: "spendingLimit must be between 10 and 50000" }, 400);
  }

  const result = await c.env.DB.prepare(
    "UPDATE cards SET spending_limit = ?, updated_at = datetime('now') WHERE id = ? AND user_id = ?"
  ).bind(spendingLimit, cardId, userId).run();

  if (!result.meta.changes) return c.json({ error: "Card not found" }, 404);
  return c.json({ cardId, spendingLimit });
});

// Get card transactions
card.get("/:cardId/transactions", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const cardId = c.req.param("cardId");

  const card_check = await c.env.DB.prepare(
    "SELECT id FROM cards WHERE id = ? AND user_id = ?"
  ).bind(cardId, userId).first();
  if (!card_check) return c.json({ error: "Card not found" }, 404);

  const txns = await c.env.DB.prepare(
    "SELECT * FROM card_transactions WHERE card_id = ? ORDER BY created_at DESC LIMIT 50"
  ).bind(cardId).all();

  return c.json({ transactions: txns.results });
});

// Cancel card (permanent)
card.delete("/:cardId", privyAuth(), strictRateLimit, async (c) => {
  const userId = c.get("userId");
  const cardId = c.req.param("cardId");

  const result = await c.env.DB.prepare(
    "UPDATE cards SET status = 'cancelled', updated_at = datetime('now') WHERE id = ? AND user_id = ? AND status != 'cancelled'"
  ).bind(cardId, userId).run();

  if (!result.meta.changes) return c.json({ error: "Card not found or already cancelled" }, 404);
  return c.json({ cardId, status: "cancelled" });
});

export default card;
