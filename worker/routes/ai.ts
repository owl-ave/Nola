import { Hono } from "hono";
import type { Env, Variables, ChatRequest, ChatResponse } from "../types";
import { privyAuth } from "../middleware/auth";
import { aiRateLimit } from "../middleware/rateLimit";

const ai = new Hono<{ Bindings: Env; Variables: Variables }>();

// Chat with AI financial assistant
ai.post("/chat", privyAuth(), aiRateLimit, async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<ChatRequest>();

  if (!body.message || body.message.trim().length === 0) {
    return c.json({ error: "Message cannot be empty" }, 400);
  }

  if (body.message.length > 2000) {
    return c.json({ error: "Message too long. Maximum 2000 characters" }, 400);
  }

  const conversationId = body.conversationId || crypto.randomUUID();

  // Store message
  await c.env.DB.prepare(
    "INSERT INTO chat_messages (id, user_id, conversation_id, role, content, created_at) VALUES (?, ?, ?, 'user', ?, datetime('now'))"
  ).bind(crypto.randomUUID(), userId, conversationId, body.message).run();

  // Call OpenAI
  const aiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${c.env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: "You are Nola, a helpful financial assistant. Help users with their wallet, card, and vault operations. Never share sensitive financial advice without disclaimers.",
        },
        { role: "user", content: body.message },
      ],
      max_tokens: 1000,
    }),
  });

  const data = (await aiResponse.json()) as {
    choices: Array<{ message: { content: string } }>;
  };

  const reply = data.choices[0]?.message?.content || "I'm sorry, I couldn't process that.";

  // Store response
  await c.env.DB.prepare(
    "INSERT INTO chat_messages (id, user_id, conversation_id, role, content, created_at) VALUES (?, ?, ?, 'assistant', ?, datetime('now'))"
  ).bind(crypto.randomUUID(), userId, conversationId, reply).run();

  const response: ChatResponse = {
    reply,
    conversationId,
    suggestedActions: [],
  };
  return c.json(response);
});

// Get conversation history
ai.get("/conversations", privyAuth(), aiRateLimit, async (c) => {
  const userId = c.get("userId");
  const conversations = await c.env.DB.prepare(
    "SELECT DISTINCT conversation_id, MAX(created_at) as last_message FROM chat_messages WHERE user_id = ? GROUP BY conversation_id ORDER BY last_message DESC LIMIT 20"
  ).bind(userId).all();
  return c.json({ conversations: conversations.results });
});

// Get messages in a conversation
ai.get("/conversations/:conversationId", privyAuth(), aiRateLimit, async (c) => {
  const userId = c.get("userId");
  const conversationId = c.req.param("conversationId");

  const messages = await c.env.DB.prepare(
    "SELECT role, content, created_at FROM chat_messages WHERE user_id = ? AND conversation_id = ? ORDER BY created_at ASC"
  ).bind(userId, conversationId).all();
  return c.json({ messages: messages.results });
});

// Delete conversation
ai.delete("/conversations/:conversationId", privyAuth(), async (c) => {
  const userId = c.get("userId");
  const conversationId = c.req.param("conversationId");

  await c.env.DB.prepare(
    "DELETE FROM chat_messages WHERE user_id = ? AND conversation_id = ?"
  ).bind(userId, conversationId).run();

  return c.json({ deleted: true });
});

export default ai;
