import { NotificationType, Prisma } from "@prisma/client";
import admin from "firebase-admin";
import fs from "fs";
import { prisma } from "../config/db";
import { config } from "../config/env";

interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

let messaging: admin.messaging.Messaging | null = null;

/** Initializes Firebase Cloud Messaging when credentials are configured. */
export function initPushService(): void {
  if (!config.fcm.credentialsPath) {
    console.log("[push] FCM_CREDENTIALS_PATH not set; push notifications are logged only");
    return;
  }
  if (!fs.existsSync(config.fcm.credentialsPath)) {
    console.warn(`[push] FCM credentials file not found: ${config.fcm.credentialsPath}`);
    return;
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(config.fcm.credentialsPath),
    });
  }
  messaging = admin.messaging();
  console.log(`[push] FCM enabled (${config.fcm.credentialsPath})`);
}

async function countPendingInviteBadge(userId: string): Promise<number> {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) return 0;

  return prisma.invite.count({
    where: {
      status: "PENDING",
      OR: [{ recipientUserId: userId }, { phoneE164: user.phoneE164 }],
    },
  });
}

function isStaleTokenError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const code = "code" in err ? String(err.code) : "";
  if (code === "messaging/registration-token-not-registered") return true;
  if (code === "messaging/invalid-argument") return true;
  const message = "message" in err ? String(err.message).toLowerCase() : "";
  return message.includes("not found") || message.includes("unregistered");
}

/** Persists in-app notification and attempts FCM delivery. */
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

  const badge = await countPendingInviteBadge(userId);
  const data: Record<string, string> = {
    type: payload.data?.type ?? "general",
    badge: String(badge),
    ...payload.data,
  };

  if (!messaging) {
    for (const t of tokens) {
      console.log(
        `[push:dev] token=${t.token.slice(0, 12)}… ${payload.title}: ${payload.body} (badge ${badge})`
      );
    }
    return;
  }

  for (const device of tokens) {
    const preview = device.token.slice(0, 12);
    try {
      await messaging.send({
        token: device.token,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data,
        apns: {
          headers: {
            "apns-priority": "10",
            "apns-push-type": "alert",
          },
          payload: {
            aps: {
              alert: {
                title: payload.title,
                body: payload.body,
              },
              sound: "default",
              badge,
            },
          },
        },
      });
      console.log(`[push] fcm → ${device.platform}/${preview}: ${payload.title} (badge ${badge})`);
    } catch (err) {
      console.error(`[push] fcm failed (${device.platform}/${preview}):`, err);
      if (isStaleTokenError(err)) {
        await prisma.deviceToken.delete({ where: { id: device.id } }).catch(() => undefined);
      }
    }
  }
}
