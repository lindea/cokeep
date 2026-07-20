import { NotificationType, Prisma } from "@prisma/client";
import apn from "@parse/node-apn";
import fs from "fs";
import { prisma } from "../config/db";
import { config } from "../config/env";
import { getUnreadBadgeCount } from "./badge";

interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

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

/** Initializes APNs delivery when credentials are configured. */
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
  } else {
    console.log("[push] No APNs credentials configured; notifications are logged only");
  }
}

async function sendApns(
  deviceToken: string,
  payload: PushPayload,
  badge: number,
  data: Record<string, string>
): Promise<string | undefined> {
  if (!apnsProvider) return undefined;

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
    return response?.reason ?? "APNs send failed";
  }
  return undefined;
}

/** Persists in-app notification and attempts push delivery via APNs. */
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

  const badge = await getUnreadBadgeCount(userId);
  const data: Record<string, string> = {
    type: payload.data?.type ?? "general",
    badge: String(badge),
    ...payload.data,
  };

  if (!apnsProvider) {
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
      const reason = await sendApns(device.token, payload, badge, data);
      if (reason) {
        console.error(`[push] failed (ios/${preview}): ${reason}`);
        if (reason === "BadDeviceToken" || reason === "Unregistered") {
          await prisma.deviceToken.delete({ where: { id: device.id } }).catch(() => undefined);
        }
        continue;
      }
      console.log(`[push] apns → ios/${preview}: ${payload.title} (badge ${badge})`);
    } catch (err) {
      console.error(`[push] failed (ios/${preview}):`, err);
    }
  }
}
