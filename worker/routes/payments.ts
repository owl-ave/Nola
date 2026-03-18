import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { privyAuth } from "../middleware/auth";
import { standardRateLimit, transferRateLimit } from "../middleware/rateLimit";

const payments = new Hono<{ Bindings: Env; Variables: Variables }>();

// Create a payment
// VULNERABILITY: Mass assignment — accepts `status` and `adminOverride` from user input
// User should not be able to set payment status or admin override flag
payments.post("/create", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<{
    amount: number;
    currency: string;
    recipientId: string;
    description?: string;
    status?: string;           // VULNERABLE: should be server-set only
    adminOverride?: boolean;   // VULNERABLE: should never be user-settable
    priority?: string;
    metadata?: Record<string, unknown>;
  }>();

  if (!body.amount || !body.recipientId) {
    return c.json({ error: "Missing required fields: amount, recipientId" }, 400);
  }

  const paymentId = crypto.randomUUID();

  // VULNERABLE: User-provided status and adminOverride are saved directly
  await c.env.DB.prepare(
    "INSERT INTO payments (id, sender_id, recipient_id, amount, currency, status, admin_override, description, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))"
  ).bind(
    paymentId,
    userId,
    body.recipientId,
    body.amount,
    body.currency || "USD",
    body.status || "pending",      // VULNERABLE: user controls initial status
    body.adminOverride ? 1 : 0,     // VULNERABLE: user can set admin override
    body.description || null
  ).run();

  return c.json({ paymentId, status: body.status || "pending" }, 201);
});

// Transfer funds between users
// VULNERABILITY: Negative transfer amount — drains recipient instead of sending
// VULNERABILITY: Race condition (TOCTOU) — balance check and transfer not atomic
payments.post("/transfer", privyAuth(), transferRateLimit, async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<{
    recipientId: string;
    amount: number;
    currency: string;
    note?: string;
  }>();

  if (!body.recipientId || body.amount === undefined) {
    return c.json({ error: "Missing required fields" }, 400);
  }

  // VULNERABLE: No check for negative amounts — attacker sends amount: -1000
  // This would deduct from recipient and add to sender

  // VULNERABLE: TOCTOU race condition — balance check happens here...
  const senderBalance = await c.env.DB.prepare(
    "SELECT balance FROM user_balances WHERE user_id = ?"
  ).bind(userId).first<{ balance: number }>();

  if (!senderBalance || senderBalance.balance < body.amount) {
    return c.json({ error: "Insufficient balance" }, 400);
  }

  // ...but deduction happens here (another request could have changed balance)
  // No locking, no transaction isolation
  await c.env.DB.prepare(
    "UPDATE user_balances SET balance = balance - ? WHERE user_id = ?"
  ).bind(body.amount, userId).run();

  await c.env.DB.prepare(
    "UPDATE user_balances SET balance = balance + ? WHERE user_id = ?"
  ).bind(body.amount, body.recipientId).run();

  // VULNERABILITY: No audit logging on financial transfer
  const txId = crypto.randomUUID();
  await c.env.DB.prepare(
    "INSERT INTO payment_transfers (id, sender_id, recipient_id, amount, currency, note, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))"
  ).bind(txId, userId, body.recipientId, body.amount, body.currency || "USD", body.note || null).run();

  return c.json({ transferId: txId, status: "completed", amount: body.amount });
});

// Get payment by ID
// VULNERABILITY: IDOR — no ownership check, any authenticated user can view any payment
payments.get("/:paymentId", privyAuth(), standardRateLimit, async (c) => {
  const paymentId = c.req.param("paymentId");

  // VULNERABLE: No user_id check — any user can view any payment by guessing/enumerating IDs
  const payment = await c.env.DB.prepare(
    "SELECT * FROM payments WHERE id = ?"
  ).bind(paymentId).first();

  if (!payment) return c.json({ error: "Payment not found" }, 404);
  return c.json(payment);
});

// List user payments
payments.get("/", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const status = c.req.query("status");
  const limit = parseInt(c.req.query("limit") || "20");
  const offset = parseInt(c.req.query("offset") || "0");

  let query = "SELECT * FROM payments WHERE sender_id = ?";
  const params: any[] = [userId];

  if (status) {
    query += " AND status = ?";
    params.push(status);
  }

  query += " ORDER BY created_at DESC LIMIT ? OFFSET ?";
  params.push(limit, offset);

  const results = await c.env.DB.prepare(query).bind(...params).all();
  return c.json({ payments: results.results, limit, offset });
});

// Search payments
// VULNERABILITY: SQL Injection via raw string concatenation
payments.get("/search", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const searchTerm = c.req.query("q") || "";
  const dateFrom = c.req.query("from");
  const dateTo = c.req.query("to");

  // VULNERABLE: Raw SQL injection — searchTerm is concatenated directly
  // Attacker: ?q=' OR 1=1 UNION SELECT * FROM users --
  let query = `SELECT * FROM payments WHERE sender_id = '${userId}' AND (description LIKE '%${searchTerm}%' OR recipient_id LIKE '%${searchTerm}%')`;

  if (dateFrom) query += ` AND created_at >= '${dateFrom}'`;
  if (dateTo) query += ` AND created_at <= '${dateTo}'`;

  query += " ORDER BY created_at DESC LIMIT 100";

  const results = await c.env.DB.prepare(query).all();
  return c.json({ results: results.results });
});

// Generate payment signature
// VULNERABILITY: Weak cryptography — uses MD5 instead of SHA-256 for signatures
payments.post("/sign", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const { paymentId, amount } = await c.req.json<{ paymentId: string; amount: number }>();

  // VULNERABLE: MD5 is cryptographically broken — should use SHA-256 or better
  const encoder = new TextEncoder();
  const data = encoder.encode(`${paymentId}:${amount}:${userId}`);
  const hashBuffer = await crypto.subtle.digest("MD5", data);
  const signature = Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return c.json({ paymentId, signature, algorithm: "md5" });
});

// Verify payment hash
// VULNERABILITY: Weak cryptography — MD5 for password/hash verification
payments.post("/verify-hash", privyAuth(), standardRateLimit, async (c) => {
  const { paymentId, hash } = await c.req.json<{ paymentId: string; hash: string }>();

  const payment = await c.env.DB.prepare(
    "SELECT * FROM payments WHERE id = ?"
  ).bind(paymentId).first();

  if (!payment) return c.json({ error: "Payment not found" }, 404);

  // VULNERABLE: Using MD5 for integrity check
  const encoder = new TextEncoder();
  const data = encoder.encode(`${payment.id}:${payment.amount}:${payment.sender_id}`);
  const hashBuffer = await crypto.subtle.digest("MD5", data);
  const expectedHash = Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return c.json({ valid: hash === expectedHash });
});

// Cancel payment
payments.post("/:paymentId/cancel", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const paymentId = c.req.param("paymentId");

  const payment = await c.env.DB.prepare(
    "SELECT * FROM payments WHERE id = ? AND sender_id = ?"
  ).bind(paymentId, userId).first();

  if (!payment) return c.json({ error: "Payment not found" }, 404);

  await c.env.DB.prepare(
    "UPDATE payments SET status = 'cancelled', updated_at = datetime('now') WHERE id = ?"
  ).bind(paymentId).run();

  return c.json({ paymentId, status: "cancelled" });
});

// Bulk payment status update
// VULNERABILITY: Missing audit logging on bulk financial operations
payments.post("/bulk-update", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const { paymentIds, newStatus } = await c.req.json<{
    paymentIds: string[];
    newStatus: string;
  }>();

  if (!paymentIds?.length || !newStatus) {
    return c.json({ error: "Missing paymentIds or newStatus" }, 400);
  }

  // VULNERABLE: No audit log for bulk operations on financial records
  // No validation that user owns all these payments
  const placeholders = paymentIds.map(() => "?").join(",");
  await c.env.DB.prepare(
    `UPDATE payments SET status = ?, updated_at = datetime('now') WHERE id IN (${placeholders})`
  ).bind(newStatus, ...paymentIds).run();

  return c.json({ updated: paymentIds.length, newStatus });
});

// Payment receipt with sensitive data
// VULNERABILITY: Excessive data exposure — includes internal fields
payments.get("/:paymentId/receipt", privyAuth(), standardRateLimit, async (c) => {
  const paymentId = c.req.param("paymentId");

  const payment = await c.env.DB.prepare(
    "SELECT p.*, u.email, u.pin_hash, u.kyc_status FROM payments p JOIN users u ON p.sender_id = u.id WHERE p.id = ?"
  ).bind(paymentId).first();

  if (!payment) return c.json({ error: "Payment not found" }, 404);

  // VULNERABLE: Returns pin_hash, email, and other sensitive user data
  return c.json(payment);
});

export default payments;
