-- CreateTable
CREATE TABLE "AppLaunchConfig" (
    "id" TEXT NOT NULL DEFAULT 'default',
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "title" TEXT NOT NULL DEFAULT '',
    "bodyMarkdown" TEXT NOT NULL DEFAULT '',
    "blocking" BOOLEAN NOT NULL DEFAULT false,
    "forceUpdate" BOOLEAN NOT NULL DEFAULT false,
    "minIosVersion" TEXT,
    "updateUrl" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AppLaunchConfig_pkey" PRIMARY KEY ("id")
);

INSERT INTO "AppLaunchConfig" ("id", "enabled", "title", "bodyMarkdown", "blocking", "forceUpdate", "updatedAt", "createdAt")
VALUES ('default', false, '', '', false, false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
