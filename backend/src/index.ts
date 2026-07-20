import cors from "cors";
import express from "express";
import fs from "fs";
import helmet from "helmet";
import path from "path";
import rateLimit from "express-rate-limit";
import { config } from "./config/env";
import { startNotificationJobs } from "./jobs/notifications";
import { initPushService } from "./services/push";
import { isS3Configured } from "./services/s3";
import { errorHandler, notFound } from "./middleware/error";
import appRoutes from "./routes/app";
import authRoutes from "./routes/auth";
import costsRoutes from "./routes/costs";
import invitesRoutes from "./routes/invites";
import objectsRoutes from "./routes/objects";
import reportsRoutes from "./routes/reports";
import todosRoutes from "./routes/todos";
import uploadsRoutes from "./routes/uploads";
import usersRoutes from "./routes/users";

const app = express();

if (!fs.existsSync(config.uploadDir)) {
  fs.mkdirSync(config.uploadDir, { recursive: true });
}

app.use(helmet({
  crossOriginResourcePolicy: { policy: "cross-origin" },
  contentSecurityPolicy: false,
}));
app.use(cors());
app.use(express.json({ limit: "2mb" }));
app.use(
  rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 500,
    standardHeaders: true,
    legacyHeaders: false,
  })
);

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "cokeep-api" });
});

app.use("/uploads", express.static(path.resolve(config.uploadDir)));

app.use("/api/auth", authRoutes);
app.use("/api/users", usersRoutes);
app.use("/api/objects", objectsRoutes);
app.use("/api/invites", invitesRoutes);
app.use("/api/app", appRoutes);
app.use("/api", todosRoutes);
app.use("/api", costsRoutes);
app.use("/api", reportsRoutes);
app.use("/api/uploads", uploadsRoutes);

/** Admin UI for launch splash / force-update (secured by ADMIN_* + JWT). */
app.get("/admin", (_req, res) => {
  res
    .type("html")
    .setHeader(
      "Content-Security-Policy",
      "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'self' data:; connect-src 'self'"
    )
    .sendFile(path.join(__dirname, "admin", "launch.html"));
});

/** Simple HTML fallback for password reset when opened in a browser. */
app.get("/reset-password", (req, res) => {
  const token = typeof req.query.token === "string" ? req.query.token : "";
  const deepLink = `${config.deepLinkScheme}://reset-password?token=${encodeURIComponent(token)}`;
  res.type("html").send(`<!doctype html>
<html><head><meta charset="utf-8"><title>CoKeep Reset</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font-family:system-ui;max-width:28rem;margin:3rem auto;padding:1rem;line-height:1.5}
a{color:#0B5FFF}</style></head>
<body>
<h1>Reset password</h1>
<p>Open this link in the CoKeep app to choose a new password.</p>
<p><a href="${deepLink}">Open CoKeep</a></p>
</body></html>`);
});

app.use(notFound);
app.use(errorHandler);

initPushService();
if (isS3Configured()) {
  console.log(`[uploads] S3 enabled (bucket=${process.env.AWS_S3_BUCKET}, region=${process.env.AWS_S3_REGION || process.env.AWS_REGION})`);
} else {
  console.log("[uploads] Using local disk (set AWS_S3_* to enable S3)");
}

app.listen(config.port, () => {
  console.log(`CoKeep API listening on :${config.port}`);
  startNotificationJobs();
});

export default app;
