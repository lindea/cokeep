import { Prisma } from "@prisma/client";
import { prisma } from "../config/db";

type NotificationData = {
  type?: string;
  todoItemId?: string;
  listId?: string;
  objectId?: string;
  inviteId?: string;
};

/** Counts unread push notifications for the app icon badge. */
export async function getUnreadBadgeCount(userId: string): Promise<number> {
  return prisma.notification.count({
    where: { userId, readAt: null },
  });
}

function asData(value: Prisma.JsonValue | null | undefined): NotificationData {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as NotificationData;
}

/** Summarizes unread alerts for UI badges on objects, lists, and items. */
export async function getUnreadAlertSummary(userId: string): Promise<{
  badge: number;
  unreadInviteCount: number;
  unreadTodoItemIds: string[];
  byObject: Record<string, number>;
  byList: Record<string, number>;
}> {
  const notifications = await prisma.notification.findMany({
    where: { userId, readAt: null },
    select: { type: true, data: true },
  });

  const unreadTodoItemIds = new Set<string>();
  const byObject: Record<string, number> = {};
  const byList: Record<string, number> = {};
  let unreadInviteCount = 0;

  for (const notification of notifications) {
    const data = asData(notification.data);
    if (notification.type === "INVITE") {
      unreadInviteCount += 1;
      continue;
    }

    if (data.todoItemId) unreadTodoItemIds.add(data.todoItemId);
    if (data.objectId) byObject[data.objectId] = (byObject[data.objectId] ?? 0) + 1;
    if (data.listId) byList[data.listId] = (byList[data.listId] ?? 0) + 1;
  }

  return {
    badge: notifications.length,
    unreadInviteCount,
    unreadTodoItemIds: [...unreadTodoItemIds],
    byObject,
    byList,
  };
}

/** Marks todo-related unread notifications as viewed. Returns new badge count. */
export async function markTodoNotificationsRead(
  userId: string,
  todoItemId: string
): Promise<number> {
  await prisma.notification.updateMany({
    where: {
      userId,
      readAt: null,
      type: { in: ["TODO_DUE_SOON", "TODO_OVERDUE"] },
      data: {
        path: ["todoItemId"],
        equals: todoItemId,
      },
    },
    data: { readAt: new Date() },
  });
  return getUnreadBadgeCount(userId);
}

/** Marks invite unread notifications as viewed. Returns new badge count. */
export async function markInviteNotificationsRead(userId: string): Promise<number> {
  await prisma.notification.updateMany({
    where: {
      userId,
      readAt: null,
      type: "INVITE",
    },
    data: { readAt: new Date() },
  });
  return getUnreadBadgeCount(userId);
}
