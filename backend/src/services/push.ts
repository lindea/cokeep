import { NotificationType, Prisma } from "@prisma/client";
import apn from "@parse/node-apn";
import admin from "firebase-admin";
import fs from "fs";
import { prisma } from "../config/db";
import { config } from "../config/env";
import { getUnreadBadgeCount } from "./badge";

interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

let messaging: admin.messaging.Messaging | null = null;
let apnsProvider: apn.Provider | null = null;

/** Resolves APNs .p8 material from APNS_KEY (inline) or APNS_KEY_PATH (file). */
function resolveApnsKeyMaterial(): string | null {
  const inline = config.apns.key.trim();
  if (inline) {
    return inline.replace(/\\n/g, "\n");
  }

  if (config.apns.keyPath) {
    if (!fs.existsSync(config.apns.keyPath)) {
      console.warn(`[push] APNs key file not found: ${config.apns.keyPath}`);
      return null;
    }
    return fs.readFileSync(config.apns.keyPath, "utf8");
  }

  return null;
}

/** Initializes APNs and/or FCM delivery when credentials are configured. */
export function initPushService(): void {
  const apnsKey = resolveApnsKeyMaterial();
  if (apnsKey && config.apns.keyId && config.apns.teamId) {
    apnsProvider = new apn.Provider({
      token: {
        key: apnsKey,
        keyId: config.apns.keyId,
        teamId: config.apns.teamId,
      },
      production: config.nodeEnv === "production",
    });
    const source = config.apns.key.trim() ? "APNS_KEY env" : config.apns.keyPath;
    console.log(`[push] APNs enabled (${config.apns.bundleId}, key from ${source})`);
  }

  if (config.fcm.credentialsPath) {
    if (!fs.existsSync(config.fcm.credentialsPath)) {
      console.warn(`[push] FCM credentials file not found: ${config.fcm.credentialsPath}`);
    } else {
      if (!admin.apps.length) {
        admin.initializeApp({
          credential: admin.credential.cert(config.fcm.credentialsPath),
        });
      }
      messaging = admin.messaging();
      console.log(`[push] FCM enabled (${config.fcm.credentialsPath})`);
    }
  }

  if (!apnsProvider && !messaging) {
    console.log("[push] No push credentials configured; notifications are logged only");
  }
}

function isStaleFcmTokenError(err: unknown): boolean {
  if (!err || typeof err !== "object") return false;
  const code = "code" in err ? String(err.code) : "";
  if (code === "messaging/registration-token-not-registered") return true;
  if (code === "messaging/invalid-argument") return true;
  const message = "message" in err ? String(err.message).toLowerCase() : "";
  return message.includes("not found") || message.includes("unregistered");
}

function isApnsDeviceToken(token: string): boolean {
  return /^[0-9a-f]{64}$/i.test(token);
}

async function sendApns(
  deviceToken: string,
  payload: PushPayload,
  badge: number,
  data: Record<string, string>
): Promise<void> {
  if (!apnsProvider) return;

  const note = new apn.Notification();
  note.topic = config.apns.bundleId;
  note.alert = { title: payload.title, body: payload.body };
  note.sound = "default";
  note.badge = badge;
  note.payload = data;

  const result = await apnsProvider.send(note, deviceToken);
  if (result.failed.length > 0) {
    const failure = result.failed[0];
    const response = failure.response as { reason?: string } | undefined;
    throw new Error(response?.reason ?? "APNs send failed");
  }
}

async function sendFcm(
  device: { id: string; token: string; platform: string },
  payload: PushPayload,
  badge: number,
  data: Record<string, string>
): Promise<void> {
  if (!messaging) return;

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
}

/** Persists in-app notification and attempts push delivery. */
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

  // Badge = unread notifications (including the one just created).
  const badge = await getUnreadBadgeCount(userId);
  const data: Record<string, string> = {
    type: payload.data?.type ?? "general",
    badge: String(badge),
    ...payload.data,
  };

  if (!apnsProvider && !messaging) {
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
      if (device.platform === "ios" && apnsProvider && isApnsDeviceToken(device.token)) {
        await sendApns(device.token, payload, badge, data);
        console.log(`[push] apns → ios/${preview}: ${payload.title} (badge ${badge})`);
        continue;
      }

      if (messaging) {
        await sendFcm(device, payload, badge, data);
        console.log(`[push] fcm → ${device.platform}/${preview}: ${payload.title} (badge ${badge})`);
        continue;
      }

      console.log(
        `[push:dev] token=${preview}… ${payload.title}: ${payload.body} (badge ${badge})`
      );
    } catch (err) {
      console.error(`[push] failed (${device.platform}/${preview}):`, err);
      const reason =
        err && typeof err === "object" && "reason" in err ? String(err.reason) : "";
      if (isStaleFcmTokenError(err) || reason === "BadDeviceToken" || reason === "Unregistered") {
        await prisma.deviceToken.delete({ where: { id: device.id } }).catch(() => undefined);
      }
    }
  }
}
