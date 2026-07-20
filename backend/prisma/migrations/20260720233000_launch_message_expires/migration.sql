-- AlterTable
ALTER TABLE "AppLaunchMessage" ADD COLUMN "expiresAt" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "AppLaunchMessage_expiresAt_idx" ON "AppLaunchMessage"("expiresAt");
