import dotenv from "dotenv";
import path from "path";

dotenv.config();

function required(name: string, fallback?: string): string {
  const value = process.env[name] ?? fallback;
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

export const config = {
  port: Number(process.env.PORT ?? 3000),
  nodeEnv: process.env.NODE_ENV ?? "development",
  databaseUrl: required("DATABASE_URL", "postgresql://cokeep:cokeep@localhost:5432/cokeep?schema=public"),
  jwtSecret: required("JWT_SECRET", "dev-secret-change-me"),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN ?? "30d",
  appBaseUrl: process.env.APP_BASE_URL ?? "http://localhost:3000",
  deepLinkScheme: process.env.APP_DEEP_LINK_SCHEME ?? "cokeep",
  appStoreUrl: process.env.APP_STORE_URL ?? "https://apps.apple.com/app/cokeep",
  uploadDir: path.resolve(process.env.UPLOAD_DIR ?? "./uploads"),
  maxUploadMb: Number(process.env.MAX_UPLOAD_MB ?? 10),
  s3: {
    bucket: process.env.AWS_S3_BUCKET || "",
    region: process.env.AWS_S3_REGION || process.env.AWS_REGION || "",
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || "",
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || "",
    /** Optional CDN or custom base, e.g. https://cdn.example.com — defaults to S3 virtual-hosted URL */
    publicBaseUrl: process.env.AWS_S3_PUBLIC_BASE_URL || "",
  },
  smtp: {
    host: process.env.SMTP_HOST || "",
    port: Number(process.env.SMTP_PORT ?? 587),
    user: process.env.SMTP_USER || "",
    pass: process.env.SMTP_PASS || "",
    from: process.env.SMTP_FROM ?? "CoKeep <noreply@cokeep.app>",
  },
  twilio: {
    accountSid: process.env.TWILIO_ACCOUNT_SID || "",
    authToken: process.env.TWILIO_AUTH_TOKEN || "",
    fromNumber: process.env.TWILIO_FROM_NUMBER || "",
  },
  fcm: {
    credentialsPath: process.env.FCM_CREDENTIALS_PATH || "",
  },
  apns: {
    keyId: process.env.APNS_KEY_ID || "",
    teamId: process.env.APNS_TEAM_ID || "",
    bundleId: process.env.APNS_BUNDLE_ID ?? "app.cokeep.CoKeep",
    /** Raw .p8 key contents (for Heroku). Supports literal newlines or `\\n` escapes. */
    key: process.env.APNS_KEY || "",
    keyPath: process.env.APNS_KEY_PATH || "",
  },
};
