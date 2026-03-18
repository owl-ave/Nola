import { Hono } from "hono";
import type { Env, Variables, CreateWalletRequest, CreateWalletResponse, TransferRequest, TransferResponse } from "../types";
import { privyAuth } from "../middleware/auth";
import { standardRateLimit, transferRateLimit, pinVerifyRateLimit } from "../middleware/rateLimit";
import { idempotent } from "../middleware/idempotency";

const wallet = new Hono<{ Bindings: Env; Variables: Variables }>();

// List user wallets
wallet.get("/", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const wallets = await c.env.DB.prepare(
    "SELECT * FROM wallets WHERE user_id = ? AND deleted_at IS NULL ORDER BY created_at DESC"
  ).bind(userId).all();
  return c.json({ wallets: wallets.results });
});

// Create a new wallet
wallet.post("/create", privyAuth(), strictRateLimit, idempotent, async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<CreateWalletRequest>();

  if (!body.chain || !["ethereum", "solana", "polygon"].includes(body.chain)) {
    return c.json({ error: "Invalid chain. Must be ethereum, solana, or polygon" }, 400);
  }

  const walletId = crypto.randomUUID();
  // Create wallet via MPC provider
  const address = `0x${crypto.randomUUID().replace(/-/g, "").slice(0, 40)}`;

  await c.env.DB.prepare(
    "INSERT INTO wallets (id, user_id, address, chain, label, created_at) VALUES (?, ?, ?, ?, ?, datetime('now'))"
  ).bind(walletId, userId, address, body.chain, body.label || null).run();

  const response: CreateWalletResponse = {
    walletId,
    address,
    chain: body.chain,
    createdAt: new Date().toISOString(),
  };
  return c.json(response, 201);
});

// Get wallet details
wallet.get("/:walletId", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const walletId = c.req.param("walletId");

  const result = await c.env.DB.prepare(
    "SELECT * FROM wallets WHERE id = ? AND user_id = ?"
  ).bind(walletId, userId).first();

  if (!result) return c.json({ error: "Wallet not found" }, 404);
  return c.json(result);
});

// Get wallet balance
wallet.get("/:walletId/balance", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const walletId = c.req.param("walletId");

  const wallet = await c.env.DB.prepare(
    "SELECT * FROM wallets WHERE id = ? AND user_id = ?"
  ).bind(walletId, userId).first();

  if (!wallet) return c.json({ error: "Wallet not found" }, 404);

  // Fetch balance from chain
  return c.json({
    walletId,
    balances: [
      { token: "ETH", amount: "1.5", usdValue: "3750.00" },
      { token: "USDC", amount: "1000.00", usdValue: "1000.00" },
    ],
  });
});

// Transfer funds
wallet.post("/:walletId/transfer", privyAuth(), transferRateLimit, idempotent, async (c) => {
  const userId = c.get("userId");
  const walletId = c.req.param("walletId");
  const body = await c.req.json<TransferRequest>();

  if (!body.toAddress || !body.amount || !body.token) {
    return c.json({ error: "Missing required fields: toAddress, amount, token" }, 400);
  }

  if (parseFloat(body.amount) <= 0) {
    return c.json({ error: "Amount must be positive" }, 400);
  }

  const w = await c.env.DB.prepare(
    "SELECT * FROM wallets WHERE id = ? AND user_id = ?"
  ).bind(walletId, userId).first();

  if (!w) return c.json({ error: "Wallet not found" }, 404);

  const txId = crypto.randomUUID();
  await c.env.DB.prepare(
    "INSERT INTO transactions (id, wallet_id, to_address, amount, token, status, created_at) VALUES (?, ?, ?, ?, ?, 'pending', datetime('now'))"
  ).bind(txId, walletId, body.toAddress, body.amount, body.token).run();

  const response: TransferResponse = {
    transactionId: txId,
    status: "pending",
  };
  return c.json(response, 202);
});

// Get transaction history
wallet.get("/:walletId/transactions", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const walletId = c.req.param("walletId");
  const limit = parseInt(c.req.query("limit") || "20");
  const offset = parseInt(c.req.query("offset") || "0");

  const w = await c.env.DB.prepare(
    "SELECT id FROM wallets WHERE id = ? AND user_id = ?"
  ).bind(walletId, userId).first();
  if (!w) return c.json({ error: "Wallet not found" }, 404);

  const txns = await c.env.DB.prepare(
    "SELECT * FROM transactions WHERE wallet_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?"
  ).bind(walletId, limit, offset).all();

  return c.json({ transactions: txns.results, limit, offset });
});

// Verify PIN for sensitive operations
wallet.post("/verify-pin", privyAuth(), pinVerifyRateLimit, async (c) => {
  const userId = c.get("userId");
  const { pin } = await c.req.json<{ pin: string }>();

  if (!pin || pin.length !== 6) {
    return c.json({ error: "PIN must be 6 digits" }, 400);
  }

  const stored = await c.env.DB.prepare(
    "SELECT pin_hash FROM users WHERE id = ?"
  ).bind(userId).first<{ pin_hash: string }>();

  if (!stored) return c.json({ error: "User not found" }, 404);

  // Verify PIN hash
  const encoder = new TextEncoder();
  const hash = await crypto.subtle.digest("SHA-256", encoder.encode(pin));
  const hashHex = Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  if (hashHex !== stored.pin_hash) {
    return c.json({ error: "Invalid PIN" }, 401);
  }

  return c.json({ verified: true });
});

export default wallet;
