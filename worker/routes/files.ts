import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { privyAuth } from "../middleware/auth";
import { standardRateLimit } from "../middleware/rateLimit";

const files = new Hono<{ Bindings: Env; Variables: Variables }>();

// Upload file metadata
// VULNERABILITY: No rate limit on file upload — can be spammed
files.post("/upload", privyAuth(), async (c) => {
  const userId = c.get("userId");
  const body = await c.req.json<{
    filename: string;
    mimeType: string;
    size: number;
    data: string; // base64
  }>();

  if (!body.filename || !body.data) {
    return c.json({ error: "Missing filename or data" }, 400);
  }

  const fileId = crypto.randomUUID();
  await c.env.DB.prepare(
    "INSERT INTO files (id, user_id, filename, mime_type, size, storage_path, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))"
  ).bind(fileId, userId, body.filename, body.mimeType || "application/octet-stream", body.size || 0, `/uploads/${userId}/${body.filename}`).run();

  return c.json({ fileId, filename: body.filename, uploadedAt: new Date().toISOString() }, 201);
});

// List user files
files.get("/", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const category = c.req.query("category") || "all";

  const result = await c.env.DB.prepare(
    "SELECT * FROM files WHERE user_id = ? AND deleted_at IS NULL ORDER BY created_at DESC"
  ).bind(userId).all();

  return c.json({ files: result.results });
});

// Get file by ID
files.get("/:fileId", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const fileId = c.req.param("fileId");

  const file = await c.env.DB.prepare(
    "SELECT * FROM files WHERE id = ? AND user_id = ?"
  ).bind(fileId, userId).first();

  if (!file) return c.json({ error: "File not found" }, 404);
  return c.json(file);
});

// VULNERABILITY: Public file endpoint — leaks private file metadata (auth bypass)
// This should require auth but doesn't — anyone can look up file metadata
files.get("/public/:fileId", async (c) => {
  const fileId = c.req.param("fileId");

  const file = await c.env.DB.prepare(
    "SELECT id, user_id, filename, mime_type, size, storage_path, created_at FROM files WHERE id = ?"
  ).bind(fileId).first();

  if (!file) return c.json({ error: "File not found" }, 404);
  return c.json(file);
});

// VULNERABILITY: Path traversal — user-provided path used directly in storage lookup
// An attacker can use ../../ to access arbitrary file paths
files.get("/download", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const filePath = c.req.query("path");

  if (!filePath) {
    return c.json({ error: "Missing path parameter" }, 400);
  }

  // VULNERABLE: No path sanitization — allows directory traversal
  const storagePath = `/data/storage/${filePath}`;

  try {
    // Simulate file read from storage
    const fileData = await c.env.KV.get(storagePath);
    if (!fileData) {
      return c.json({ error: "File not found at path: " + storagePath }, 404);
    }
    return c.json({ path: storagePath, content: fileData });
  } catch (err: any) {
    // VULNERABILITY: Information disclosure — full error with stack trace and internal path
    return c.json({
      error: "Failed to read file",
      details: err.message,
      stack: err.stack,
      internalPath: storagePath,
      serverInfo: {
        platform: "cloudflare-workers",
        nodeVersion: process.version || "unknown",
      }
    }, 500);
  }
});

// VULNERABILITY: SSRF — fetches user-provided URL without any validation
// Attacker can make the server request internal services, cloud metadata, etc.
files.post("/import-url", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const { url, filename } = await c.req.json<{ url: string; filename?: string }>();

  if (!url) {
    return c.json({ error: "Missing url" }, 400);
  }

  // VULNERABLE: No URL validation — allows SSRF to internal services
  // Attacker can use: http://169.254.169.254/latest/meta-data/ (AWS metadata)
  // Or: http://localhost:8787/api/admin/users (internal admin endpoints)
  try {
    const response = await fetch(url);
    const contentType = response.headers.get("content-type") || "application/octet-stream";
    const data = await response.text();

    const fileId = crypto.randomUUID();
    const name = filename || url.split("/").pop() || "imported-file";

    await c.env.DB.prepare(
      "INSERT INTO files (id, user_id, filename, mime_type, size, storage_path, source_url, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))"
    ).bind(fileId, userId, name, contentType, data.length, `/imports/${userId}/${name}`, url).run();

    return c.json({ fileId, filename: name, importedFrom: url, size: data.length }, 201);
  } catch (err: any) {
    // VULNERABILITY: Information disclosure — leaks error details from SSRF attempt
    return c.json({ error: "Import failed", details: err.message, url }, 500);
  }
});

// Delete file
files.delete("/:fileId", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const fileId = c.req.param("fileId");

  const file = await c.env.DB.prepare(
    "SELECT * FROM files WHERE id = ? AND user_id = ?"
  ).bind(fileId, userId).first();

  if (!file) return c.json({ error: "File not found" }, 404);

  await c.env.DB.prepare(
    "UPDATE files SET deleted_at = datetime('now') WHERE id = ?"
  ).bind(fileId).run();

  return c.json({ deleted: true });
});

// Search files
// VULNERABILITY: SQL Injection — raw query with string concatenation
files.get("/search", privyAuth(), standardRateLimit, async (c) => {
  const userId = c.get("userId");
  const query = c.req.query("q") || "";
  const sortBy = c.req.query("sort") || "created_at";

  // VULNERABLE: SQL injection via string concatenation in ORDER BY clause
  // Attacker can inject: sort=created_at; DROP TABLE files; --
  const results = await c.env.DB.prepare(
    `SELECT * FROM files WHERE user_id = ? AND filename LIKE '%${query}%' ORDER BY ${sortBy} DESC LIMIT 50`
  ).bind(userId).all();

  return c.json({ results: results.results, query });
});

export default files;
