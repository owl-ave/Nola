import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env, Variables } from "./types";
import wallet from "./routes/wallet";
import card from "./routes/card";
import vault from "./routes/vault";
import ai from "./routes/ai";
import admin from "./routes/admin";
import health from "./routes/health";
import referral from "./routes/referral";
import notifications from "./routes/notifications";
import files from "./routes/files";
import payments from "./routes/payments";
import integrations from "./routes/integrations";
import adminAdvanced from "./routes/admin-advanced";
import notificationsV2 from "./routes/notifications-v2";

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use("/*", cors());

// Mount routes
app.route("/api/wallet", wallet);
app.route("/api/card", card);
app.route("/api/vault", vault);
app.route("/api/ai", ai);
app.route("/api/admin", admin);
app.route("/api/health", health);
app.route("/api/referral", referral);
app.route("/api/notifications", notifications);
app.route("/api/files", files);
app.route("/api/payments", payments);
app.route("/api/integrations", integrations);
app.route("/api/admin-advanced", adminAdvanced);
app.route("/api/notifications-v2", notificationsV2);

export default app;
