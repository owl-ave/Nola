import { Hono } from "hono";
import type { Env, Variables, NotificationPreferences } from "../types";
import { privyAuth } from "../middleware/auth";
import { apiKeyAuth } from "../middleware/auth";
import { standardRateLimit } from "../middleware/rateLimit";

const notifications = new Hono<{ Bindings: Env; Variables: Variables }>();

// Get notification preferences
notifications.get("/preferences", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");

  const prefs = await c.env.DB.prepare(
    "SELECT * FROM notification_preferences WHERE user_id = ?"
  ).bind(userId).first();

  if (!prefs) {
    // Return defaults
    return c.json({
      email: true,
      push: true,
      sms: false,
      categories: {
        transactions: true,
        security: true,
        marketing: false,
        rewards: true,
      },
    });
  }

  return c.json(prefs);
});

// Update notification preferences
notifications.put("/preferences", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<NotificationPreferences>();

  await c.env.DB.prepare(
    "INSERT INTO notification_preferences (user_id, email, push, sms, categories, updated_at) VALUES (?, ?, ?, ?, ?, datetime('now')) ON CONFLICT(user_id) DO UPDATE SET email = ?, push = ?, sms = ?, categories = ?, updated_at = datetime('now')"
  ).bind(
    userId,
    body.email ? 1 : 0, body.push ? 1 : 0, body.sms ? 1 : 0, JSON.stringify(body.categories),
    body.email ? 1 : 0, body.push ? 1 : 0, body.sms ? 1 : 0, JSON.stringify(body.categories)
  ).run();

  return c.json({ updated: true });
});

// Get notification history
notifications.get("/", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const unreadOnly = c.req.query("unread") === "true";

  let query = "SELECT * FROM notifications WHERE user_id = ?";
  if (unreadOnly) query += " AND read_at IS NULL";
  query += " ORDER BY created_at DESC LIMIT 50";

  const notifs = await c.env.DB.prepare(query).bind(userId).all();
  return c.json({ notifications: notifs.results });
});

// Mark notification as read
notifications.post("/:notificationId/read", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const notificationId = c.req.param("notificationId");

  await c.env.DB.prepare(
    "UPDATE notifications SET read_at = datetime('now') WHERE id = ? AND user_id = ?"
  ).bind(notificationId, userId).run();

  return c.json({ read: true });
});

// Mark all as read
notifications.post("/read-all", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");

  await c.env.DB.prepare(
    "UPDATE notifications SET read_at = datetime('now') WHERE user_id = ? AND read_at IS NULL"
  ).bind(userId).run();

  return c.json({ readAll: true });
});

// Send notification (service-to-service, API key auth)
notifications.post("/send", apiKeyAuth, standardRateLimit, async (c) => {
  const body = await c.req.json<{
    userId: string;
    title: string;
    message: string;
    category: string;
    data?: Record<string, unknown>;
  }>();

  if (!body.userId || !body.title || !body.message || !body.category) {
    return c.json({ error: "Missing required fields" }, 400);
  }

  const id = crypto.randomUUID();
  await c.env.DB.prepare(
    "INSERT INTO notifications (id, user_id, title, message, category, data, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))"
  ).bind(id, body.userId, body.title, body.message, body.category, JSON.stringify(body.data || {})).run();

  return c.json({ notificationId: id }, 201);
});

// Get unread count
notifications.get("/unread-count", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const count = await c.env.DB.prepare(
    "SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND read_at IS NULL"
  ).bind(userId).first<{ count: number }>();
  return c.json({ count: count?.count || 0 });
});

export default notifications;
