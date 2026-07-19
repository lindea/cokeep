import { minutesBetween } from "../utils/helpers";

type WorkLogLike = { startedAt: Date; endedAt: Date };

export function totalWorkMinutes(logs: WorkLogLike[]): number {
  return logs.reduce((sum, log) => sum + minutesBetween(log.startedAt, log.endedAt), 0);
}

export function serializeTodoItem(
  item: {
    id: string;
    listId: string;
    name: string;
    description: string | null;
    scheduleType: string;
    dueDate: Date | null;
    recurrence: string | null;
    assigneeId: string | null;
    isDone: boolean;
    completedAt: Date | null;
    completedById: string | null;
    createdAt: Date;
    updatedAt: Date;
    assignee?: {
      id: string;
      firstName: string;
      lastName: string;
      avatarUrl: string | null;
    } | null;
    workLogs?: WorkLogLike[];
  }
) {
  const totalMinutes = item.workLogs ? totalWorkMinutes(item.workLogs) : undefined;
  return {
    id: item.id,
    listId: item.listId,
    name: item.name,
    description: item.description,
    scheduleType: item.scheduleType,
    dueDate: item.dueDate,
    recurrence: item.recurrence,
    assigneeId: item.assigneeId,
    assignee: item.assignee
      ? {
          id: item.assignee.id,
          firstName: item.assignee.firstName,
          lastName: item.assignee.lastName,
          avatarUrl: item.assignee.avatarUrl,
        }
      : null,
    isDone: item.isDone,
    completedAt: item.completedAt,
    completedById: item.completedById,
    totalWorkMinutes: totalMinutes ?? 0,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
  };
}
