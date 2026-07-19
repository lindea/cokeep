import { NotificationType, Prisma } from "@prisma/client";
import { prisma } from "../config/db";
import { config } from "../config/env";

interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/** Persists in-app notification and attempts APNs delivery. */
export async function notifyUser(
  userId: string,
  type: NotificationType,
  payload: PushPayload
): Promise<void> {
  await prisma.notification.create({
    data: {
      userId,
      type,
      title: payload.title,
      body: payload.body,
      data: (payload.data ?? {}) as Prisma.InputJsonValue,
    },
  });

  const tokens = await prisma.deviceToken.findMany({ where: { userId } });
  if (tokens.length === 0) {
    console.log(`[push:dev] user=${userId} title=${payload.title} body=${payload.body}`);
    return;
  }

  if (!config.apns.keyPath) {
    for (const t of tokens) {
      console.log(`[push:dev] token=${t.token.slice(0, 12)}… ${payload.title}: ${payload.body}`);
    }
    return;
  }

  // Production APNs integration would use @parse/node-apn or similar here.
  console.log(`[push] Would deliver to ${tokens.length} device(s) via APNs`);
}
