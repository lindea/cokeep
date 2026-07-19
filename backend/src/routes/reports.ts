import { Router } from "express";
import { z } from "zod";
import { prisma } from "../config/db";
import { AuthenticatedRequest, requireAuth } from "../middleware/auth";
import { AppError } from "../middleware/error";
import { requireObjectMember } from "../services/access";
import { minutesBetween } from "../utils/helpers";

const router = Router();

router.use(requireAuth);

type PeriodPreset = "week" | "month" | "quarter" | "year" | "all" | "custom";

function resolvePeriod(
  preset: PeriodPreset,
  from?: string,
  to?: string
): { from: Date | null; to: Date } {
  const now = new Date();
  const end = to ? new Date(to) : now;

  if (preset === "all") return { from: null, to: end };
  if (preset === "custom") {
    if (!from) throw new AppError(400, "Custom period requires from date");
    return { from: new Date(from), to: end };
  }

  const start = new Date(end);
  switch (preset) {
    case "week":
      start.setDate(start.getDate() - 7);
      break;
    case "month":
      start.setMonth(start.getMonth() - 1);
      break;
    case "quarter":
      start.setMonth(start.getMonth() - 3);
      break;
    case "year":
      start.setFullYear(start.getFullYear() - 1);
      break;
  }
  return { from: start, to: end };
}

const querySchema = z.object({
  period: z.enum(["week", "month", "quarter", "year", "all", "custom"]).default("month"),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
});

router.get(
  "/objects/:objectId/reports/spendings",
  async (req: AuthenticatedRequest, res, next) => {
    try {
      await requireObjectMember(req.params.objectId, req.user!.userId);
      const query = querySchema.parse(req.query);
      const { from, to } = resolvePeriod(query.period, query.from, query.to);

      const costs = await prisma.cost.findMany({
        where: {
          objectId: req.params.objectId,
          spentAt: {
            ...(from ? { gte: from } : {}),
            lte: to,
          },
        },
        include: { user: true },
        orderBy: { spentAt: "desc" },
      });

      const byUserMap = new Map<
        string,
        { userId: string; firstName: string; lastName: string; avatarUrl: string | null; totalCents: number }
      >();

      let totalCents = 0;
      for (const cost of costs) {
        totalCents += cost.amountCents;
        const existing = byUserMap.get(cost.userId);
        if (existing) {
          existing.totalCents += cost.amountCents;
        } else {
          byUserMap.set(cost.userId, {
            userId: cost.userId,
            firstName: cost.user.firstName,
            lastName: cost.user.lastName,
            avatarUrl: cost.user.avatarUrl,
            totalCents: cost.amountCents,
          });
        }
      }

      const byUser = [...byUserMap.values()].sort((a, b) => b.totalCents - a.totalCents);

      res.json({
        period: { preset: query.period, from, to },
        currency: costs[0]?.currency ?? "NOK",
        totalCents,
        byUser,
        items: costs.map((c) => ({
          id: c.id,
          amountCents: c.amountCents,
          currency: c.currency,
          description: c.description,
          spentAt: c.spentAt,
          userId: c.userId,
          firstName: c.user.firstName,
          lastName: c.user.lastName,
        })),
        chart: byUser.map((u) => ({
          label: `${u.firstName} ${u.lastName}`,
          value: u.totalCents / 100,
        })),
      });
    } catch (err) {
      next(err instanceof z.ZodError ? new AppError(400, "Invalid query", err.flatten()) : err);
    }
  }
);

router.get(
  "/objects/:objectId/reports/work",
  async (req: AuthenticatedRequest, res, next) => {
    try {
      await requireObjectMember(req.params.objectId, req.user!.userId);
      const query = querySchema.parse(req.query);
      const { from, to } = resolvePeriod(query.period, query.from, query.to);

      const lists = await prisma.todoList.findMany({
        where: { objectId: req.params.objectId },
        select: { id: true },
      });
      const listIds = lists.map((l) => l.id);

      const logs = await prisma.workLog.findMany({
        where: {
          todoItem: { listId: { in: listIds } },
          startedAt: {
            ...(from ? { gte: from } : {}),
            lte: to,
          },
        },
        include: {
          user: true,
          todoItem: true,
        },
        orderBy: { startedAt: "desc" },
      });

      const byUserMap = new Map<
        string,
        {
          userId: string;
          firstName: string;
          lastName: string;
          avatarUrl: string | null;
          totalMinutes: number;
        }
      >();

      let totalMinutes = 0;
      for (const log of logs) {
        const mins = minutesBetween(log.startedAt, log.endedAt);
        totalMinutes += mins;
        const existing = byUserMap.get(log.userId);
        if (existing) {
          existing.totalMinutes += mins;
        } else {
          byUserMap.set(log.userId, {
            userId: log.userId,
            firstName: log.user.firstName,
            lastName: log.user.lastName,
            avatarUrl: log.user.avatarUrl,
            totalMinutes: mins,
          });
        }
      }

      const byUser = [...byUserMap.values()].sort(
        (a, b) => b.totalMinutes - a.totalMinutes
      );

      res.json({
        period: { preset: query.period, from, to },
        totalMinutes,
        byUser,
        items: logs.map((l) => ({
          id: l.id,
          startedAt: l.startedAt,
          endedAt: l.endedAt,
          durationMinutes: minutesBetween(l.startedAt, l.endedAt),
          todoItemId: l.todoItemId,
          todoItemName: l.todoItem.name,
          userId: l.userId,
          firstName: l.user.firstName,
          lastName: l.user.lastName,
        })),
        chart: byUser.map((u) => ({
          label: `${u.firstName} ${u.lastName}`,
          value: Math.round((u.totalMinutes / 60) * 10) / 10,
        })),
      });
    } catch (err) {
      next(err instanceof z.ZodError ? new AppError(400, "Invalid query", err.flatten()) : err);
    }
  }
);

export default router;
