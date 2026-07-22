import { Router } from "express";
import { z } from "zod";
import { prisma } from "../config/db";
import { AuthenticatedRequest, requireAuth } from "../middleware/auth";
import { AppError } from "../middleware/error";
import { scheduleDueNotifications } from "../jobs/notifications";
import { getTodoItemForUser, requireObjectMember } from "../services/access";
import { serializeTodoItem, totalWorkMinutes } from "../services/todoSerializer";
import { minutesBetween, publicUser } from "../utils/helpers";
import { getUnreadAlertSummary } from "../services/badge";

const router = Router();

router.use(requireAuth);

const scheduleSchema = z.discriminatedUnion("scheduleType", [
  z.object({
    scheduleType: z.literal("ONE_OFF"),
    dueDate: z.string().datetime().nullable().optional(),
    recurrence: z.null().optional(),
  }),
  z.object({
    scheduleType: z.literal("RECURRING"),
    dueDate: z.string().datetime().nullable().optional(),
    recurrence: z.enum([
      "DAILY",
      "WEEKLY",
      "BIWEEKLY",
      "MONTHLY",
      "QUARTERLY",
      "YEARLY",
    ]),
  }),
]);

router.get(
  "/objects/:objectId/todo-lists",
  async (req: AuthenticatedRequest, res, next) => {
    try {
      await requireObjectMember(req.params.objectId, req.user!.userId);
      const [lists, alertSummary] = await Promise.all([
        prisma.todoList.findMany({
          where: { objectId: req.params.objectId },
          include: {
            items: {
              include: {
                assignee: true,
                workLogs: true,
              },
            },
          },
          orderBy: { sortOrder: "asc" },
        }),
        getUnreadAlertSummary(req.user!.userId),
      ]);
      const unreadItemIds = new Set(alertSummary.unreadTodoItemIds);

      res.json({
        lists: lists.map((list) => {
          const open = list.items
            .filter((i) => !i.isDone)
            .sort((a, b) => {
              if (!a.dueDate) return 1;
              if (!b.dueDate) return -1;
              return a.dueDate.getTime() - b.dueDate.getTime();
            });
          const done = list.items
            .filter((i) => i.isDone)
            .sort(
              (a, b) =>
                (b.completedAt?.getTime() ?? 0) - (a.completedAt?.getTime() ?? 0)
            );

          const openItems = open.map((item) => ({
            ...serializeTodoItem(item),
            hasUnreadAlert: unreadItemIds.has(item.id),
          }));
          const doneItems = done.map((item) => ({
            ...serializeTodoItem(item),
            hasUnreadAlert: unreadItemIds.has(item.id),
          }));

          return {
            id: list.id,
            objectId: list.objectId,
            name: list.name,
            sortOrder: list.sortOrder,
            unreadAlertCount: openItems.filter((i) => i.hasUnreadAlert).length,
            openItems,
            doneItems,
          };
        }),
      });
    } catch (err) {
      next(err);
    }
  }
);

router.post(
  "/objects/:objectId/todo-lists",
  async (req: AuthenticatedRequest, res, next) => {
    try {
      await requireObjectMember(req.params.objectId, req.user!.userId);
      const body = z.object({ name: z.string().min(1).max(100) }).parse(req.body);
      const count = await prisma.todoList.count({
        where: { objectId: req.params.objectId },
      });
      const list = await prisma.todoList.create({
        data: {
          objectId: req.params.objectId,
          name: body.name.trim(),
          sortOrder: count,
        },
      });
      res.status(201).json({ list });
    } catch (err) {
      next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
    }
  }
);

router.patch("/todo-lists/:listId", async (req: AuthenticatedRequest, res, next) => {
  try {
    const list = await prisma.todoList.findUnique({ where: { id: req.params.listId } });
    if (!list) throw new AppError(404, "List not found");
    await requireObjectMember(list.objectId, req.user!.userId);
    const body = z.object({ name: z.string().min(1).max(100) }).parse(req.body);
    const updated = await prisma.todoList.update({
      where: { id: list.id },
      data: { name: body.name.trim() },
    });
    res.json({ list: updated });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.delete("/todo-lists/:listId", async (req: AuthenticatedRequest, res, next) => {
  try {
    const list = await prisma.todoList.findUnique({ where: { id: req.params.listId } });
    if (!list) throw new AppError(404, "List not found");
    await requireObjectMember(list.objectId, req.user!.userId);
    await prisma.todoList.delete({ where: { id: list.id } });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

router.post(
  "/todo-lists/:listId/items",
  async (req: AuthenticatedRequest, res, next) => {
    try {
      const list = await prisma.todoList.findUnique({ where: { id: req.params.listId } });
      if (!list) throw new AppError(404, "List not found");
      await requireObjectMember(list.objectId, req.user!.userId);

      const base = z
        .object({
          name: z.string().min(1).max(200),
          description: z.string().max(2000).nullable().optional(),
          assigneeId: z.string().uuid().nullable().optional(),
        })
        .parse(req.body);

      const schedule = scheduleSchema.parse({
        scheduleType: req.body.scheduleType ?? "ONE_OFF",
        dueDate: req.body.dueDate ?? null,
        recurrence: req.body.recurrence ?? null,
      });

      if (base.assigneeId) {
        await requireObjectMember(list.objectId, base.assigneeId);
      }

      const item = await prisma.todoItem.create({
        data: {
          listId: list.id,
          name: base.name.trim(),
          description: base.description ?? null,
          scheduleType: schedule.scheduleType,
          dueDate: schedule.dueDate ? new Date(schedule.dueDate) : null,
          recurrence: schedule.scheduleType === "RECURRING" ? schedule.recurrence : null,
          assigneeId: base.assigneeId ?? null,
        },
        include: { assignee: true, workLogs: true },
      });

      // Items created already inside the due-soon window should notify without waiting for cron.
      if (item.dueDate && item.assigneeId) {
        scheduleDueNotifications();
      }

      res.status(201).json({ item: serializeTodoItem(item) });
    } catch (err) {
      next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
    }
  }
);

router.get("/todo-items/:itemId", async (req: AuthenticatedRequest, res, next) => {
  try {
    const item = await getTodoItemForUser(req.params.itemId, req.user!.userId);
    res.json({
      item: {
        ...serializeTodoItem(item),
        objectId: item.list.objectId,
        logs: item.workLogs.map((log) => ({
          id: log.id,
          startedAt: log.startedAt,
          endedAt: log.endedAt,
          durationMinutes: minutesBetween(log.startedAt, log.endedAt),
          note: log.note,
          user: publicUser(log.user),
        })),
      },
    });
  } catch (err) {
    next(err);
  }
});

router.patch("/todo-items/:itemId", async (req: AuthenticatedRequest, res, next) => {
  try {
    const existing = await getTodoItemForUser(req.params.itemId, req.user!.userId);
    const body = z
      .object({
        name: z.string().min(1).max(200).optional(),
        description: z.string().max(2000).nullable().optional(),
        assigneeId: z.string().uuid().nullable().optional(),
        scheduleType: z.enum(["ONE_OFF", "RECURRING"]).optional(),
        dueDate: z.string().datetime().nullable().optional(),
        recurrence: z
          .enum(["DAILY", "WEEKLY", "BIWEEKLY", "MONTHLY", "QUARTERLY", "YEARLY"])
          .nullable()
          .optional(),
        isDone: z.boolean().optional(),
      })
      .parse(req.body);

    if (body.assigneeId) {
      await requireObjectMember(existing.list.objectId, body.assigneeId);
    }

    const data: Record<string, unknown> = { ...body };
    let shouldRecheckNotifications = false;

    if (body.dueDate !== undefined) {
      data.dueDate = body.dueDate ? new Date(body.dueDate) : null;
      data.dueSoonNotified = false;
      data.overdueNotified = false;
      shouldRecheckNotifications = true;
    }

    // Re-notify the (new) assignee when responsibility changes.
    if (body.assigneeId !== undefined && body.assigneeId !== existing.assigneeId) {
      data.dueSoonNotified = false;
      data.overdueNotified = false;
      shouldRecheckNotifications = true;
    }

    if (body.isDone === true) {
      data.completedAt = new Date();
      data.completedById = req.user!.userId;
    } else if (body.isDone === false) {
      data.completedAt = null;
      data.completedById = null;
      data.dueSoonNotified = false;
      data.overdueNotified = false;
      shouldRecheckNotifications = true;
    }

    const item = await prisma.todoItem.update({
      where: { id: existing.id },
      data,
      include: { assignee: true, workLogs: true },
    });

    if (shouldRecheckNotifications && item.dueDate && item.assigneeId && !item.isDone) {
      scheduleDueNotifications();
    }

    res.json({ item: serializeTodoItem(item) });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.delete("/todo-items/:itemId", async (req: AuthenticatedRequest, res, next) => {
  try {
    const existing = await getTodoItemForUser(req.params.itemId, req.user!.userId);
    await prisma.todoItem.delete({ where: { id: existing.id } });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

router.post(
  "/todo-items/:itemId/logs",
  async (req: AuthenticatedRequest, res, next) => {
    try {
      const item = await getTodoItemForUser(req.params.itemId, req.user!.userId);
      const body = z
        .object({
          startedAt: z.string().datetime(),
          endedAt: z.string().datetime(),
          note: z.string().max(1000).nullable().optional(),
        })
        .parse(req.body);

      const startedAt = new Date(body.startedAt);
      const endedAt = new Date(body.endedAt);
      if (endedAt <= startedAt) {
        throw new AppError(400, "End time must be after start time");
      }

      const log = await prisma.workLog.create({
        data: {
          todoItemId: item.id,
          userId: req.user!.userId,
          startedAt,
          endedAt,
          note: body.note ?? null,
        },
        include: { user: true },
      });

      const logs = await prisma.workLog.findMany({ where: { todoItemId: item.id } });

      res.status(201).json({
        log: {
          id: log.id,
          startedAt: log.startedAt,
          endedAt: log.endedAt,
          durationMinutes: minutesBetween(log.startedAt, log.endedAt),
          note: log.note,
          user: publicUser(log.user),
        },
        totalWorkMinutes: totalWorkMinutes(logs),
      });
    } catch (err) {
      next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
    }
  }
);

export default router;
