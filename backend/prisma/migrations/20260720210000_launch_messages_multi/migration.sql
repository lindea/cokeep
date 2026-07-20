-- CreateEnum
CREATE TYPE "LaunchVersionOp" AS ENUM ('ANY', 'EQ', 'LT', 'LTE', 'GT', 'GTE', 'BETWEEN');

-- CreateTable
CREATE TABLE "AppLaunchMessage" (
    "id" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "title" TEXT NOT NULL DEFAULT '',
    "bodyMarkdown" TEXT NOT NULL DEFAULT '',
    "blocking" BOOLEAN NOT NULL DEFAULT false,
    "forceUpdate" BOOLEAN NOT NULL DEFAULT false,
    "versionOp" "LaunchVersionOp" NOT NULL DEFAULT 'ANY',
    "versionA" TEXT,
    "versionB" TEXT,
    "updateUrl" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AppLaunchMessage_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AppLaunchMessage_enabled_sortOrder_idx" ON "AppLaunchMessage"("enabled", "sortOrder");

-- Migrate any previously enabled singleton splash into the new table.
INSERT INTO "AppLaunchMessage" (
  "id", "enabled", "title", "bodyMarkdown", "blocking", "forceUpdate",
  "versionOp", "versionA", "versionB", "updateUrl", "sortOrder", "updatedAt", "createdAt"
)
SELECT
  'migrated-' || "id",
  true,
  "title",
  "bodyMarkdown",
  "blocking",
  "forceUpdate",
  CASE
    WHEN "minIosVersion" IS NOT NULL AND "minIosVersion" <> '' THEN 'LT'::"LaunchVersionOp"
    ELSE 'ANY'::"LaunchVersionOp"
  END,
  NULLIF("minIosVersion", ''),
  NULL,
  "updateUrl",
  0,
  "updatedAt",
  "createdAt"
FROM "AppLaunchConfig"
WHERE "enabled" = true
  AND (
    "title" <> ''
    OR "bodyMarkdown" <> ''
    OR "forceUpdate" = true
  );

DROP TABLE IF EXISTS "AppLaunchConfig";
