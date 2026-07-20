import cron from "node-cron";
import { prisma } from "../config/db";
import { notifyUser } from "../services/push";

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
    include: { list: { include: { object: true } } },
  });

  for (const item of dueSoon) {
    if (!item.assigneeId || !item.dueDate) continue;
    await notifyUser(item.assigneeId, "TODO_DUE_SOON", {
      title: "CoKeep",
      body: `“${item.name}” on ${item.list.object.name} is due within a week`,
      data: {
        type: "todo_due_soon",
        todoItemId: item.id,
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
    include: { list: { include: { object: true } } },
  });

  for (const item of overdue) {
    if (!item.assigneeId) continue;
    await notifyUser(item.assigneeId, "TODO_OVERDUE", {
      title: "CoKeep",
      body: `“${item.name}” on ${item.list.object.name} is overdue`,
      data: {
        type: "todo_overdue",
        todoItemId: item.id,
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
