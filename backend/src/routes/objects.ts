import { Router } from "express";
import { z } from "zod";
import { prisma } from "../config/db";
import { AuthenticatedRequest, requireAuth } from "../middleware/auth";
import { AppError } from "../middleware/error";
import { requireObjectMember, requireObjectOwner } from "../services/access";
import { getUnreadAlertSummary } from "../services/badge";
import { publicUser } from "../utils/helpers";

const router = Router();

router.use(requireAuth);

const CABIN_DEFAULT_LISTS = ["Maintenance", "Seasonal", "Shopping"];
const GENERIC_DEFAULT_LISTS = ["To-do"];

router.get("/", async (req: AuthenticatedRequest, res, next) => {
  try {
    const [memberships, alertSummary] = await Promise.all([
      prisma.objectMembership.findMany({
        where: { userId: req.user!.userId, status: "ACTIVE" },
        include: {
          object: {
            include: {
              members: {
                where: { status: "ACTIVE" },
                include: { user: true },
              },
            },
          },
        },
        orderBy: { joinedAt: "desc" },
      }),
      getUnreadAlertSummary(req.user!.userId),
    ]);

    res.json({
      objects: memberships.map((m) => ({
        ...m.object,
        role: m.role,
        unreadAlertCount: alertSummary.byObject[m.object.id] ?? 0,
        members: m.object.members.map((mem) => ({
          id: mem.id,
          role: mem.role,
          joinedAt: mem.joinedAt,
          user: publicUser(mem.user),
        })),
      })),
    });
  } catch (err) {
    next(err);
  }
});

router.post("/", async (req: AuthenticatedRequest, res, next) => {
  try {
    const body = z
      .object({
        name: z.string().min(1).max(120),
        template: z.enum(["CABIN", "GENERIC"]).default("GENERIC"),
        imageUrl: z.string().url().nullable().optional(),
      })
      .parse(req.body);

    const defaultLists =
      body.template === "CABIN" ? CABIN_DEFAULT_LISTS : GENERIC_DEFAULT_LISTS;

    const object = await prisma.sharedObject.create({
      data: {
        name: body.name.trim(),
        template: body.template,
        imageUrl: body.imageUrl ?? null,
        createdById: req.user!.userId,
        members: {
          create: {
            userId: req.user!.userId,
            role: "OWNER",
            status: "ACTIVE",
          },
        },
        todoLists: {
          create: defaultLists.map((name, index) => ({
            name,
            sortOrder: index,
          })),
        },
      },
      include: {
        members: { include: { user: true } },
        todoLists: true,
      },
    });

    res.status(201).json({
      object: {
        ...object,
        role: "OWNER",
        members: object.members.map((m) => ({
          id: m.id,
          role: m.role,
          joinedAt: m.joinedAt,
          user: publicUser(m.user),
        })),
      },
    });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.get("/:objectId", async (req: AuthenticatedRequest, res, next) => {
  try {
    const membership = await requireObjectMember(req.params.objectId, req.user!.userId);
    const object = await prisma.sharedObject.findUniqueOrThrow({
      where: { id: req.params.objectId },
      include: {
        members: {
          where: { status: "ACTIVE" },
          include: { user: true },
        },
        todoLists: { orderBy: { sortOrder: "asc" } },
      },
    });

    res.json({
      object: {
        ...object,
        role: membership.role,
        members: object.members.map((m) => ({
          id: m.id,
          role: m.role,
          joinedAt: m.joinedAt,
          user: publicUser(m.user),
        })),
      },
    });
  } catch (err) {
    next(err);
  }
});

router.patch("/:objectId", async (req: AuthenticatedRequest, res, next) => {
  try {
    await requireObjectOwner(req.params.objectId, req.user!.userId);
    const body = z
      .object({
        name: z.string().min(1).max(120).optional(),
        imageUrl: z.string().url().nullable().optional(),
      })
      .parse(req.body);

    const object = await prisma.sharedObject.update({
      where: { id: req.params.objectId },
      data: body,
    });
    res.json({ object });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

/** Current user leaves the object. */
router.post("/:objectId/leave", async (req: AuthenticatedRequest, res, next) => {
  try {
    const membership = await requireObjectMember(req.params.objectId, req.user!.userId);
    if (membership.role === "OWNER") {
      const otherOwners = await prisma.objectMembership.count({
        where: {
          objectId: req.params.objectId,
          status: "ACTIVE",
          role: "OWNER",
          NOT: { userId: req.user!.userId },
        },
      });
      if (otherOwners === 0) {
        const activeMembers = await prisma.objectMembership.count({
          where: {
            objectId: req.params.objectId,
            status: "ACTIVE",
            NOT: { userId: req.user!.userId },
          },
        });
        if (activeMembers > 0) {
          throw new AppError(
            400,
            "Transfer ownership or remove other members before leaving"
          );
        }
      }
    }

    await prisma.objectMembership.update({
      where: { id: membership.id },
      data: { status: "LEFT", leftAt: new Date() },
    });

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/** Owner removes a member. */
router.delete(
  "/:objectId/members/:userId",
  async (req: AuthenticatedRequest, res, next) => {
    try {
      await requireObjectOwner(req.params.objectId, req.user!.userId);
      if (req.params.userId === req.user!.userId) {
        throw new AppError(400, "Use leave to remove yourself");
      }

      const membership = await prisma.objectMembership.findUnique({
        where: {
          objectId_userId: {
            objectId: req.params.objectId,
            userId: req.params.userId,
          },
        },
      });
      if (!membership || membership.status !== "ACTIVE") {
        throw new AppError(404, "Member not found");
      }

      await prisma.objectMembership.update({
        where: { id: membership.id },
        data: { status: "REMOVED", leftAt: new Date() },
      });

      res.json({ ok: true });
    } catch (err) {
      next(err);
    }
  }
);

export default router;
