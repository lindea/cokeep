import { Router } from "express";
import { z } from "zod";
import { prisma } from "../config/db";
import { config } from "../config/env";
import {
  AuthenticatedRequest,
  requireAdmin,
  signAdminToken,
} from "../middleware/auth";
import { AppError } from "../middleware/error";

const router = Router();

const DEFAULT_ID = "default";

async function getOrCreateConfig() {
  return prisma.appLaunchConfig.upsert({
    where: { id: DEFAULT_ID },
    create: { id: DEFAULT_ID },
    update: {},
  });
}

function publicShape(row: Awaited<ReturnType<typeof getOrCreateConfig>>) {
  return {
    enabled: row.enabled,
    title: row.title,
    bodyMarkdown: row.bodyMarkdown,
    blocking: row.blocking,
    forceUpdate: row.forceUpdate,
    minIosVersion: row.minIosVersion,
    updateUrl: row.updateUrl ?? config.appStoreUrl,
    updatedAt: row.updatedAt.toISOString(),
  };
}

/** Public: iOS reads this on every cold start (no auth). */
router.get("/launch-config", async (_req, res, next) => {
  try {
    const row = await getOrCreateConfig();
    res.json(publicShape(row));
  } catch (err) {
    next(err);
  }
});

const loginSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(1),
});

router.post("/admin/login", async (req, res, next) => {
  try {
    if (!config.admin.password) {
      throw new AppError(
        503,
        "Admin login is not configured (set ADMIN_PASSWORD)"
      );
    }
    const body = loginSchema.parse(req.body);
    const userOk = body.username === config.admin.username;
    const passOk = body.password === config.admin.password;
    if (!userOk || !passOk) {
      throw new AppError(401, "Invalid username or password");
    }
    const token = signAdminToken({
      role: "admin",
      username: config.admin.username,
    });
    res.json({ token, username: config.admin.username });
  } catch (err) {
    next(err);
  }
});

router.get(
  "/admin/launch-config",
  requireAdmin,
  async (_req: AuthenticatedRequest, res, next) => {
    try {
      const row = await getOrCreateConfig();
      res.json(publicShape(row));
    } catch (err) {
      next(err);
    }
  }
);

const updateSchema = z.object({
  enabled: z.boolean(),
  title: z.string().max(200),
  bodyMarkdown: z.string().max(20000),
  blocking: z.boolean(),
  forceUpdate: z.boolean(),
  minIosVersion: z
    .string()
    .max(32)
    .nullable()
    .optional()
    .transform((v) => (v && v.trim() ? v.trim() : null)),
  updateUrl: z
    .string()
    .max(500)
    .nullable()
    .optional()
    .transform((v) => (v && v.trim() ? v.trim() : null)),
});

router.put(
  "/admin/launch-config",
  requireAdmin,
  async (req: AuthenticatedRequest, res, next) => {
    try {
      const body = updateSchema.parse(req.body);
      const row = await prisma.appLaunchConfig.upsert({
        where: { id: DEFAULT_ID },
        create: {
          id: DEFAULT_ID,
          enabled: body.enabled,
          title: body.title,
          bodyMarkdown: body.bodyMarkdown,
          blocking: body.blocking,
          forceUpdate: body.forceUpdate,
          minIosVersion: body.minIosVersion ?? null,
          updateUrl: body.updateUrl ?? null,
        },
        update: {
          enabled: body.enabled,
          title: body.title,
          bodyMarkdown: body.bodyMarkdown,
          blocking: body.blocking,
          forceUpdate: body.forceUpdate,
          minIosVersion: body.minIosVersion ?? null,
          updateUrl: body.updateUrl ?? null,
        },
      });
      res.json(publicShape(row));
    } catch (err) {
      next(err);
    }
  }
);

export default router;
