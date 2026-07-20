import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { randomUUID } from "crypto";
import path from "path";
import { config } from "../config/env";

let s3: S3Client | null = null;

/** True when AWS S3 credentials and bucket are configured. */
export function isS3Configured(): boolean {
  return Boolean(
    config.s3.bucket &&
      config.s3.region &&
      config.s3.accessKeyId &&
      config.s3.secretAccessKey
  );
}

function getClient(): S3Client {
  if (!s3) {
    s3 = new S3Client({
      region: config.s3.region,
      credentials: {
        accessKeyId: config.s3.accessKeyId,
        secretAccessKey: config.s3.secretAccessKey,
      },
    });
  }
  return s3;
}

/** Public URL for an object key (custom CDN/base URL or virtual-hosted–style S3 URL). */
export function publicUrlForKey(key: string): string {
  if (config.s3.publicBaseUrl) {
    return `${config.s3.publicBaseUrl.replace(/\/$/, "")}/${key}`;
  }
  return `https://${config.s3.bucket}.s3.${config.s3.region}.amazonaws.com/${key}`;
}

/**
 * Uploads an image buffer to S3 and returns its public URL.
 * Keys are namespaced under `cokeep/` for easy cleanup.
 */
export async function uploadImageToS3(
  buffer: Buffer,
  originalName: string,
  mimeType: string
): Promise<{ url: string; key: string }> {
  const ext = path.extname(originalName).toLowerCase() || ".jpg";
  const key = `cokeep/${randomUUID()}${ext}`;

  await getClient().send(
    new PutObjectCommand({
      Bucket: config.s3.bucket,
      Key: key,
      Body: buffer,
      ContentType: mimeType,
      CacheControl: "public, max-age=31536000",
    })
  );

  return { url: publicUrlForKey(key), key };
}
