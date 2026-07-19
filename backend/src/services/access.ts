import { MembershipStatus } from "@prisma/client";
import { prisma } from "../config/db";
import { AppError } from "../middleware/error";

/** Ensures the user is an active member of the object; returns membership. */
export async function requireObjectMember(objectId: string, userId: string) {
  const membership = await prisma.objectMembership.findUnique({
    where: { objectId_userId: { objectId, userId } },
    include: { object: true },
  });

  if (!membership || membership.status !== MembershipStatus.ACTIVE) {
    throw new AppError(403, "You do not have access to this object");
  }

  return membership;
}

export async function requireObjectOwner(objectId: string, userId: string) {
  const membership = await requireObjectMember(objectId, userId);
  if (membership.role !== "OWNER") {
    throw new AppError(403, "Only the object creator can perform this action");
  }
  return membership;
}

export async function getTodoItemForUser(todoItemId: string, userId: string) {
  const item = await prisma.todoItem.findUnique({
    where: { id: todoItemId },
    include: {
      list: true,
      assignee: true,
      workLogs: { include: { user: true }, orderBy: { startedAt: "desc" } },
    },
  });

  if (!item) {
    throw new AppError(404, "Todo item not found");
  }

  await requireObjectMember(item.list.objectId, userId);
  return item;
}
