import cron from "node-cron";
import { prisma } from "../config/db";
import { notifyUser } from "../services/push";
import {
  normalizeAppLang,
  todoDueSoonPushCopy,
  todoOverduePushCopy,
} from "../utils/locale";

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

/** Checks open todos for due-soon (≤7 days) and overdue alerts. */
export async function runDueNotifications(): Promise<void> {
  const now = new Date();
  const weekAhead = new Date(now.getTime() + WEEK_MS);

  const dueSoon = await prisma.todoItem.findMany({
    where: {
      isDone: false,
      dueSoonNotified: false,
      dueDate: { gte: now, lte: weekAhead },
      assigneeId: { not: null },
    },
    include: {
      list: { include: { object: true } },
      assignee: { select: { preferredLanguage: true } },
    },
  });

  for (const item of dueSoon) {
    if (!item.assigneeId || !item.dueDate) continue;
    const lang = normalizeAppLang(item.assignee?.preferredLanguage);
    const copy = todoDueSoonPushCopy(lang, item.name, item.list.object.name);
    await notifyUser(item.assigneeId, "TODO_DUE_SOON", {
      title: copy.title,
      body: copy.body,
      data: {
        type: "todo_due_soon",
        todoItemId: item.id,
        listId: item.listId,
        objectId: item.list.objectId,
      },
    });
    await prisma.todoItem.update({
      where: { id: item.id },
      data: { dueSoonNotified: true },
    });
  }

  const overdue = await prisma.todoItem.findMany({
    where: {
      isDone: false,
      overdueNotified: false,
      dueDate: { lt: now },
      assigneeId: { not: null },
    },
    include: {
      list: { include: { object: true } },
      assignee: { select: { preferredLanguage: true } },
    },
  });

  for (const item of overdue) {
    if (!item.assigneeId) continue;
    const lang = normalizeAppLang(item.assignee?.preferredLanguage);
    const copy = todoOverduePushCopy(lang, item.name, item.list.object.name);
    await notifyUser(item.assigneeId, "TODO_OVERDUE", {
      title: copy.title,
      body: copy.body,
      data: {
        type: "todo_overdue",
        todoItemId: item.id,
        listId: item.listId,
        objectId: item.list.objectId,
      },
    });
    await prisma.todoItem.update({
      where: { id: item.id },
      data: { overdueNotified: true },
    });
  }
}

export function startNotificationJobs(): void {
  // Every hour
  cron.schedule("0 * * * *", () => {
    runDueNotifications().catch((err) =>
      console.error("Due notification job failed:", err)
    );
  });
}
