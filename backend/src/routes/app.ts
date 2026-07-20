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
import { normalizeAppLang } from "../utils/locale";

const router = Router();

const versionOpSchema = z.nativeEnum(LaunchVersionOp);

type LaunchMessageRow = {
  id: string;
  enabled: boolean;
  titleEn: string;
  bodyMarkdownEn: string;
  titleNb: string;
  bodyMarkdownNb: string;
  blocking: boolean;
  forceUpdate: boolean;
  versionOp: LaunchVersionOp;
  versionA: string | null;
  versionB: string | null;
  updateUrl: string | null;
  expiresAt: Date | null;
  sortOrder: number;
  updatedAt: Date;
  createdAt: Date;
};

function isExpired(row: { expiresAt: Date | null }, now = new Date()): boolean {
  return row.expiresAt != null && row.expiresAt.getTime() <= now.getTime();
}

function localizedContent(row: LaunchMessageRow, lang: "en" | "nb") {
  if (lang === "nb") {
    return {
      title: row.titleNb.trim() ? row.titleNb : row.titleEn,
      bodyMarkdown: row.bodyMarkdownNb.trim() ? row.bodyMarkdownNb : row.bodyMarkdownEn,
    };
  }
  return {
    title: row.titleEn,
    bodyMarkdown: row.bodyMarkdownEn,
  };
}

function adminShape(row: LaunchMessageRow) {
  return {
    id: row.id,
    enabled: row.enabled,
    titleEn: row.titleEn,
    bodyMarkdownEn: row.bodyMarkdownEn,
    titleNb: row.titleNb,
    bodyMarkdownNb: row.bodyMarkdownNb,
    blocking: row.blocking,
    forceUpdate: row.forceUpdate,
    versionOp: row.versionOp,
    versionA: row.versionA,
    versionB: row.versionB,
    updateUrl: row.updateUrl ?? config.appStoreUrl,
    expiresAt: row.expiresAt?.toISOString() ?? null,
    expired: isExpired(row),
    sortOrder: row.sortOrder,
    updatedAt: row.updatedAt.toISOString(),
    createdAt: row.createdAt.toISOString(),
  };
}

function publicShape(row: LaunchMessageRow, lang: "en" | "nb") {
  const content = localizedContent(row, lang);
  return {
    id: row.id,
    enabled: row.enabled,
    /** Resolved for the requested lang (with fallback). */
    title: content.title,
    bodyMarkdown: content.bodyMarkdown,
    lang,
    /** Raw locales so the client can re-resolve with Bundle language if needed. */
    titleEn: row.titleEn,
    bodyMarkdownEn: row.bodyMarkdownEn,
    titleNb: row.titleNb,
    bodyMarkdownNb: row.bodyMarkdownNb,
    blocking: row.blocking,
    forceUpdate: row.forceUpdate,
    versionOp: row.versionOp,
    versionA: row.versionA,
    versionB: row.versionB,
    updateUrl: row.updateUrl ?? config.appStoreUrl,
    expiresAt: row.expiresAt?.toISOString() ?? null,
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

/** Public: enabled splash messages (?iosVersion=&lang=en|nb). Also reads Accept-Language. */
router.get("/launch-messages", async (req, res, next) => {
  try {
    const iosVersion =
      typeof req.query.iosVersion === "string" ? req.query.iosVersion.trim() : "";
    const fromQuery =
      typeof req.query.lang === "string" ? req.query.lang : undefined;
    const fromHeader = req.headers["accept-language"];
    const headerLang =
      typeof fromHeader === "string" ? fromHeader.split(",")[0]?.trim() : undefined;
    const lang = normalizeAppLang(fromQuery || headerLang);

    const now = new Date();
    const rows = await prisma.appLaunchMessage.findMany({
      where: {
        enabled: true,
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
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
      messages: sortMessages(filtered).map((row) => publicShape(row, lang)),
      lang,
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
    titleEn: z.string().max(200),
    bodyMarkdownEn: z.string().max(20000),
    titleNb: z.string().max(200).optional().default(""),
    bodyMarkdownNb: z.string().max(20000).optional().default(""),
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
    expiresAt: z
      .string()
      .nullable()
      .optional()
      .transform((v, ctx) => {
        if (v == null || !String(v).trim()) return null;
        const parsed = new Date(String(v).trim());
        if (Number.isNaN(parsed.getTime())) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: "Invalid expiresAt datetime",
          });
          return z.NEVER;
        }
        return parsed;
      }),
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
      res.json({ messages: sortMessages(rows).map(adminShape) });
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
          titleEn: body.titleEn,
          bodyMarkdownEn: body.bodyMarkdownEn,
          titleNb: body.titleNb,
          bodyMarkdownNb: body.bodyMarkdownNb,
          blocking: body.blocking,
          forceUpdate: body.forceUpdate,
          versionOp: body.versionOp,
          versionA: body.versionA,
          versionB: body.versionOp === "BETWEEN" ? body.versionB : null,
          updateUrl: body.updateUrl,
          expiresAt: body.expiresAt,
          sortOrder: body.sortOrder,
        },
      });
      res.status(201).json(adminShape(row));
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
          titleEn: body.titleEn,
          bodyMarkdownEn: body.bodyMarkdownEn,
          titleNb: body.titleNb,
          bodyMarkdownNb: body.bodyMarkdownNb,
          blocking: body.blocking,
          forceUpdate: body.forceUpdate,
          versionOp: body.versionOp,
          versionA: body.versionA,
          versionB: body.versionOp === "BETWEEN" ? body.versionB : null,
          updateUrl: body.updateUrl,
          expiresAt: body.expiresAt,
          sortOrder: body.sortOrder,
        },
      });
      res.json(adminShape(row));
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
