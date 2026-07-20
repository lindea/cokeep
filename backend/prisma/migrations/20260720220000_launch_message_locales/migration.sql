-- AlterTable: rename English fields and add Norwegian
ALTER TABLE "AppLaunchMessage" RENAME COLUMN "title" TO "titleEn";
ALTER TABLE "AppLaunchMessage" RENAME COLUMN "bodyMarkdown" TO "bodyMarkdownEn";
ALTER TABLE "AppLaunchMessage" ADD COLUMN "titleNb" TEXT NOT NULL DEFAULT '';
ALTER TABLE "AppLaunchMessage" ADD COLUMN "bodyMarkdownNb" TEXT NOT NULL DEFAULT '';
