import { Router } from "express";
import { z } from "zod";
import { prisma } from "../config/db";
import { config } from "../config/env";
import { AuthenticatedRequest, requireAuth } from "../middleware/auth";
import { AppError } from "../middleware/error";
import { requireObjectMember, requireObjectOwner } from "../services/access";
import { notifyUser } from "../services/push";
import { markInviteNotificationsRead } from "../services/badge";
import { normalizePhone, publicUser } from "../utils/helpers";

const router = Router();

router.use(requireAuth);

router.post("/objects/:objectId/invites", async (req: AuthenticatedRequest, res, next) => {
  try {
    await requireObjectMember(req.params.objectId, req.user!.userId);
    const body = z
      .object({
        phone: z.string().min(4).max(20),
        countryCode: z.string().min(1).max(6).default("+47"),
      })
      .parse(req.body);

    const phoneE164 = normalizePhone(body.phone, body.countryCode);
    const inviter = await prisma.user.findUniqueOrThrow({
      where: { id: req.user!.userId },
    });
    const object = await prisma.sharedObject.findUniqueOrThrow({
      where: { id: req.params.objectId },
    });

    if (phoneE164 === inviter.phoneE164) {
      throw new AppError(400, "You cannot invite yourself");
    }

    const existingUser = await prisma.user.findUnique({ where: { phoneE164 } });

    if (existingUser) {
      const membership = await prisma.objectMembership.findUnique({
        where: {
          objectId_userId: {
            objectId: object.id,
            userId: existingUser.id,
          },
        },
      });
      if (membership?.status === "ACTIVE") {
        throw new AppError(409, "User is already a member of this object");
      }
    }

    const invite = await prisma.invite.create({
      data: {
        objectId: object.id,
        invitedById: inviter.id,
        phoneE164,
        recipientUserId: existingUser?.id,
        status: "PENDING",
      },
    });

    const inviteUrl = `${config.appStoreUrl}?invite=${invite.token}`;

    if (existingUser) {
      await notifyUser(existingUser.id, "INVITE", {
        title: "CoKeep",
        body: `${inviter.firstName} invited you to join “${object.name}”`,
        data: {
          type: "invite",
          inviteId: invite.id,
          objectId: object.id,
        },
      });
    }

    res.status(201).json({
      invite: {
        id: invite.id,
        phoneE164: invite.phoneE164,
        status: invite.status,
        recipientExists: Boolean(existingUser),
        inviteUrl: existingUser ? null : inviteUrl,
        createdAt: invite.createdAt,
      },
    });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.get("/pending", async (req: AuthenticatedRequest, res, next) => {
  try {
    const user = await prisma.user.findUniqueOrThrow({
      where: { id: req.user!.userId },
    });

    const invites = await prisma.invite.findMany({
      where: {
        status: "PENDING",
        OR: [{ recipientUserId: user.id }, { phoneE164: user.phoneE164 }],
      },
      include: {
        object: true,
        invitedBy: true,
      },
      orderBy: { createdAt: "desc" },
    });

    res.json({
      invites: invites.map((i) => ({
        id: i.id,
        status: i.status,
        createdAt: i.createdAt,
        object: {
          id: i.object.id,
          name: i.object.name,
          template: i.object.template,
          imageUrl: i.object.imageUrl,
        },
        invitedBy: publicUser(i.invitedBy),
      })),
    });
  } catch (err) {
    next(err);
  }
});

router.post("/:inviteId/respond", async (req: AuthenticatedRequest, res, next) => {
  try {
    const body = z
      .object({ accept: z.boolean() })
      .parse(req.body);

    const user = await prisma.user.findUniqueOrThrow({
      where: { id: req.user!.userId },
    });

    const invite = await prisma.invite.findUnique({
      where: { id: req.params.inviteId },
    });
    if (!invite || invite.status !== "PENDING") {
      throw new AppError(404, "Invite not found");
    }
    if (invite.phoneE164 !== user.phoneE164 && invite.recipientUserId !== user.id) {
      throw new AppError(403, "This invite is not for you");
    }

    if (!body.accept) {
      await prisma.invite.update({
        where: { id: invite.id },
        data: { status: "DECLINED", respondedAt: new Date(), recipientUserId: user.id },
      });
      await markInviteNotificationsRead(user.id);
      res.json({ ok: true, accepted: false });
      return;
    }

    await prisma.$transaction([
      prisma.objectMembership.upsert({
        where: {
          objectId_userId: { objectId: invite.objectId, userId: user.id },
        },
        create: {
          objectId: invite.objectId,
          userId: user.id,
          role: "MEMBER",
          status: "ACTIVE",
        },
        update: { status: "ACTIVE", leftAt: null },
      }),
      prisma.invite.update({
        where: { id: invite.id },
        data: {
          status: "ACCEPTED",
          respondedAt: new Date(),
          recipientUserId: user.id,
        },
      }),
    ]);

    await markInviteNotificationsRead(user.id);
    res.json({ ok: true, accepted: true, objectId: invite.objectId });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.get("/objects/:objectId/invites", async (req: AuthenticatedRequest, res, next) => {
  try {
    await requireObjectOwner(req.params.objectId, req.user!.userId);
    const invites = await prisma.invite.findMany({
      where: { objectId: req.params.objectId },
      orderBy: { createdAt: "desc" },
    });
    res.json({ invites });
  } catch (err) {
    next(err);
  }
});

export default router;
