import { Router } from "express";
import { z } from "zod";
import { prisma } from "../config/db";
import { AuthenticatedRequest, requireAuth } from "../middleware/auth";
import { AppError } from "../middleware/error";
import { requireObjectMember } from "../services/access";
import { publicUser } from "../utils/helpers";

const router = Router();

router.use(requireAuth);

type CostWithRelations = {
  id: string;
  amountCents: number;
  currency: string;
  description: string | null;
  receiptUrl: string | null;
  spentAt: Date;
  todoItemId: string | null;
  todoItem: { name: string } | null;
  user: Parameters<typeof publicUser>[0];
};

function serializeCost(c: CostWithRelations) {
  return {
    id: c.id,
    amountCents: c.amountCents,
    currency: c.currency,
    description: c.description,
    receiptUrl: c.receiptUrl,
    spentAt: c.spentAt,
    todoItemId: c.todoItemId,
    todoItemName: c.todoItem?.name ?? null,
    user: publicUser(c.user),
  };
}

router.get(
  "/objects/:objectId/costs",
  async (req: AuthenticatedRequest, res, next) => {
    try {
      await requireObjectMember(req.params.objectId, req.user!.userId);
      const costs = await prisma.cost.findMany({
        where: { objectId: req.params.objectId },
        include: { user: true, todoItem: true },
        orderBy: { spentAt: "desc" },
      });

      res.json({
        costs: costs.map(serializeCost),
      });
    } catch (err) {
      next(err);
    }
  }
);

router.post(
  "/objects/:objectId/costs",
  async (req: AuthenticatedRequest, res, next) => {
    try {
      await requireObjectMember(req.params.objectId, req.user!.userId);
      const body = z
        .object({
          amountCents: z.number().int().positive(),
          currency: z.string().length(3).default("NOK"),
          description: z.string().max(500).nullable().optional(),
          receiptUrl: z.string().url().nullable().optional(),
          todoItemId: z.string().uuid().nullable().optional(),
          spentAt: z.string().datetime().optional(),
        })
        .parse(req.body);

      if (body.todoItemId) {
        const item = await prisma.todoItem.findUnique({
          where: { id: body.todoItemId },
          include: { list: true },
        });
        if (!item || item.list.objectId !== req.params.objectId) {
          throw new AppError(400, "Todo item does not belong to this object");
        }
      }

      const cost = await prisma.cost.create({
        data: {
          objectId: req.params.objectId,
          userId: req.user!.userId,
          amountCents: body.amountCents,
          currency: body.currency.toUpperCase(),
          description: body.description ?? null,
          receiptUrl: body.receiptUrl ?? null,
          todoItemId: body.todoItemId ?? null,
          spentAt: body.spentAt ? new Date(body.spentAt) : new Date(),
        },
        include: { user: true, todoItem: true },
      });

      res.status(201).json({
        cost: serializeCost(cost),
      });
    } catch (err) {
      next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
    }
  }
);

router.get("/costs/:costId", async (req: AuthenticatedRequest, res, next) => {
  try {
    const cost = await prisma.cost.findUnique({
      where: { id: req.params.costId },
      include: { user: true, todoItem: true },
    });
    if (!cost) throw new AppError(404, "Cost not found");
    await requireObjectMember(cost.objectId, req.user!.userId);
    res.json({ cost: serializeCost(cost) });
  } catch (err) {
    next(err);
  }
});

router.patch("/costs/:costId", async (req: AuthenticatedRequest, res, next) => {
  try {
    const cost = await prisma.cost.findUnique({
      where: { id: req.params.costId },
      include: { user: true, todoItem: true },
    });
    if (!cost) throw new AppError(404, "Cost not found");
    await requireObjectMember(cost.objectId, req.user!.userId);
    if (cost.userId !== req.user!.userId) {
      throw new AppError(403, "Only the person who logged the cost can edit it");
    }

    const body = z
      .object({
        amountCents: z.number().int().positive().optional(),
        currency: z.string().length(3).optional(),
        description: z.string().max(500).nullable().optional(),
        receiptUrl: z.string().url().nullable().optional(),
        todoItemId: z.string().uuid().nullable().optional(),
        spentAt: z.string().datetime().optional(),
      })
      .parse(req.body);

    if (body.todoItemId) {
      const item = await prisma.todoItem.findUnique({
        where: { id: body.todoItemId },
        include: { list: true },
      });
      if (!item || item.list.objectId !== cost.objectId) {
        throw new AppError(400, "Todo item does not belong to this object");
      }
    }

    const updated = await prisma.cost.update({
      where: { id: cost.id },
      data: {
        amountCents: body.amountCents ?? cost.amountCents,
        currency: body.currency ? body.currency.toUpperCase() : cost.currency,
        description: body.description !== undefined ? body.description : cost.description,
        receiptUrl: body.receiptUrl !== undefined ? body.receiptUrl : cost.receiptUrl,
        todoItemId: body.todoItemId !== undefined ? body.todoItemId : cost.todoItemId,
        spentAt: body.spentAt ? new Date(body.spentAt) : cost.spentAt,
      },
      include: { user: true, todoItem: true },
    });

    res.json({ cost: serializeCost(updated) });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.delete("/costs/:costId", async (req: AuthenticatedRequest, res, next) => {
  try {
    const cost = await prisma.cost.findUnique({ where: { id: req.params.costId } });
    if (!cost) throw new AppError(404, "Cost not found");
    await requireObjectMember(cost.objectId, req.user!.userId);
    if (cost.userId !== req.user!.userId) {
      throw new AppError(403, "Only the person who logged the cost can delete it");
    }
    await prisma.cost.delete({ where: { id: cost.id } });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

export default router;
