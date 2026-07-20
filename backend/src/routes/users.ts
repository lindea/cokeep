import { Router } from "express";
import { z } from "zod";
import { prisma } from "../config/db";
import { AuthenticatedRequest, requireAuth } from "../middleware/auth";
import { AppError } from "../middleware/error";
import { publicUser } from "../utils/helpers";
import {
  getUnreadAlertSummary,
  markInviteNotificationsRead,
  markTodoNotificationsRead,
} from "../services/badge";

const router = Router();

router.use(requireAuth);

router.patch("/me", async (req: AuthenticatedRequest, res, next) => {
  try {
    const body = z
      .object({
        firstName: z.string().min(1).max(80).optional(),
        lastName: z.string().min(1).max(80).optional(),
        email: z.string().email().optional(),
        avatarUrl: z.string().url().nullable().optional(),
      })
      .parse(req.body);

    if (body.email) {
      const email = body.email.toLowerCase().trim();
      const clash = await prisma.user.findFirst({
        where: { email, NOT: { id: req.user!.userId } },
      });
      if (clash) throw new AppError(409, "Email already in use");
      body.email = email;
    }

    const user = await prisma.user.update({
      where: { id: req.user!.userId },
      data: body,
    });

    res.json({ user: publicUser(user) });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.post("/device-token", async (req: AuthenticatedRequest, res, next) => {
  try {
    const body = z
      .object({
        token: z.string().min(10),
        platform: z.enum(["ios", "android"]).default("ios"),
      })
      .parse(req.body);

    const device = await prisma.deviceToken.upsert({
      where: { token: body.token },
      create: {
        userId: req.user!.userId,
        token: body.token,
        platform: body.platform,
      },
      update: {
        userId: req.user!.userId,
        platform: body.platform,
      },
    });

    res.json({ device });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.get("/notifications", async (req: AuthenticatedRequest, res, next) => {
  try {
    const notifications = await prisma.notification.findMany({
      where: { userId: req.user!.userId },
      orderBy: { createdAt: "desc" },
      take: 50,
    });
    res.json({ notifications });
  } catch (err) {
    next(err);
  }
});

router.get("/badge", async (req: AuthenticatedRequest, res, next) => {
  try {
    const summary = await getUnreadAlertSummary(req.user!.userId);
    res.json(summary);
  } catch (err) {
    next(err);
  }
});

router.post("/notifications/mark-read", async (req: AuthenticatedRequest, res, next) => {
  try {
    const body = z
      .object({
        todoItemId: z.string().uuid().optional(),
        invites: z.boolean().optional(),
      })
      .parse(req.body);

    let badge: number;
    if (body.todoItemId) {
      badge = await markTodoNotificationsRead(req.user!.userId, body.todoItemId);
    } else if (body.invites) {
      badge = await markInviteNotificationsRead(req.user!.userId);
    } else {
      throw new AppError(400, "Specify todoItemId or invites");
    }

    res.json({ badge });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.post("/notifications/:id/read", async (req: AuthenticatedRequest, res, next) => {
  try {
    const notification = await prisma.notification.findFirst({
      where: { id: req.params.id, userId: req.user!.userId },
    });
    if (!notification) throw new AppError(404, "Notification not found");
    const updated = await prisma.notification.update({
      where: { id: notification.id },
      data: { readAt: new Date() },
    });
    res.json({ notification: updated });
  } catch (err) {
    next(err);
  }
});

export default router;
