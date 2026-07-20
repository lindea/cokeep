import { LaunchVersionOp, Prisma } from "@prisma/client";
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
import { matchesVersionRule, VersionOp } from "../utils/version";

const router = Router();

const versionOpSchema = z.nativeEnum(LaunchVersionOp);

function publicShape(row: {
  id: string;
  enabled: boolean;
  title: string;
  bodyMarkdown: string;
  blocking: boolean;
  forceUpdate: boolean;
  versionOp: LaunchVersionOp;
  versionA: string | null;
  versionB: string | null;
  updateUrl: string | null;
  sortOrder: number;
  updatedAt: Date;
  createdAt: Date;
}) {
  return {
    id: row.id,
    enabled: row.enabled,
    title: row.title,
    bodyMarkdown: row.bodyMarkdown,
    blocking: row.blocking,
    forceUpdate: row.forceUpdate,
    versionOp: row.versionOp,
    versionA: row.versionA,
    versionB: row.versionB,
    updateUrl: row.updateUrl ?? config.appStoreUrl,
    sortOrder: row.sortOrder,
    updatedAt: row.updatedAt.toISOString(),
    createdAt: row.createdAt.toISOString(),
  };
}

function sortMessages<T extends { forceUpdate: boolean; sortOrder: number; updatedAt: Date | string }>(
  rows: T[]
): T[] {
  return [...rows].sort((a, b) => {
    if (a.forceUpdate !== b.forceUpdate) return a.forceUpdate ? -1 : 1;
    if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
    const at = typeof a.updatedAt === "string" ? a.updatedAt : a.updatedAt.toISOString();
    const bt = typeof b.updatedAt === "string" ? b.updatedAt : b.updatedAt.toISOString();
    return bt.localeCompare(at);
  });
}

/** Public: enabled splash messages (optional ?iosVersion= filters server-side). */
router.get("/launch-messages", async (req, res, next) => {
  try {
    const iosVersion =
      typeof req.query.iosVersion === "string" ? req.query.iosVersion.trim() : "";

    const rows = await prisma.appLaunchMessage.findMany({
      where: { enabled: true },
    });

    const filtered = iosVersion
      ? rows.filter((row) =>
          matchesVersionRule(
            iosVersion,
            row.versionOp as VersionOp,
            row.versionA,
            row.versionB
          )
        )
      : rows;

    res.json({
      messages: sortMessages(filtered).map(publicShape),
      defaultUpdateUrl: config.appStoreUrl,
    });
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

const messageBodySchema = z
  .object({
    enabled: z.boolean(),
    title: z.string().max(200),
    bodyMarkdown: z.string().max(20000),
    blocking: z.boolean(),
    forceUpdate: z.boolean(),
    versionOp: versionOpSchema,
    versionA: z
      .string()
      .max(32)
      .nullable()
      .optional()
      .transform((v) => (v && v.trim() ? v.trim() : null)),
    versionB: z
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
    sortOrder: z.number().int().min(0).max(9999).optional().default(0),
  })
  .superRefine((data, ctx) => {
    if (data.versionOp !== "ANY" && !data.versionA) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "versionA is required for this version rule",
        path: ["versionA"],
      });
    }
    if (data.versionOp === "BETWEEN" && !data.versionB) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "versionB is required for BETWEEN",
        path: ["versionB"],
      });
    }
  });

router.get(
  "/admin/launch-messages",
  requireAdmin,
  async (_req: AuthenticatedRequest, res, next) => {
    try {
      const rows = await prisma.appLaunchMessage.findMany();
      res.json({ messages: sortMessages(rows).map(publicShape) });
    } catch (err) {
      next(err);
    }
  }
);

router.post(
  "/admin/launch-messages",
  requireAdmin,
  async (req: AuthenticatedRequest, res, next) => {
    try {
      const body = messageBodySchema.parse(req.body);
      const row = await prisma.appLaunchMessage.create({
        data: {
          enabled: body.enabled,
          title: body.title,
          bodyMarkdown: body.bodyMarkdown,
          blocking: body.blocking,
          forceUpdate: body.forceUpdate,
          versionOp: body.versionOp,
          versionA: body.versionA,
          versionB: body.versionOp === "BETWEEN" ? body.versionB : null,
          updateUrl: body.updateUrl,
          sortOrder: body.sortOrder,
        },
      });
      res.status(201).json(publicShape(row));
    } catch (err) {
      next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
    }
  }
);

router.put(
  "/admin/launch-messages/:id",
  requireAdmin,
  async (req: AuthenticatedRequest, res, next) => {
    try {
      const body = messageBodySchema.parse(req.body);
      const row = await prisma.appLaunchMessage.update({
        where: { id: req.params.id },
        data: {
          enabled: body.enabled,
          title: body.title,
          bodyMarkdown: body.bodyMarkdown,
          blocking: body.blocking,
          forceUpdate: body.forceUpdate,
          versionOp: body.versionOp,
          versionA: body.versionA,
          versionB: body.versionOp === "BETWEEN" ? body.versionB : null,
          updateUrl: body.updateUrl,
          sortOrder: body.sortOrder,
        },
      });
      res.json(publicShape(row));
    } catch (err) {
      if (
        err instanceof Prisma.PrismaClientKnownRequestError &&
        err.code === "P2025"
      ) {
        next(new AppError(404, "Message not found"));
        return;
      }
      next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
    }
  }
);

router.delete(
  "/admin/launch-messages/:id",
  requireAdmin,
  async (req: AuthenticatedRequest, res, next) => {
    try {
      await prisma.appLaunchMessage.delete({ where: { id: req.params.id } });
      res.json({ ok: true });
    } catch (err) {
      if (
        err instanceof Prisma.PrismaClientKnownRequestError &&
        err.code === "P2025"
      ) {
        next(new AppError(404, "Message not found"));
        return;
      }
      next(err);
    }
  }
);

export default router;
