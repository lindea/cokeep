-- CreateTable
CREATE TABLE "TodoItemPhoto" (
    "id" TEXT NOT NULL,
    "todoItemId" TEXT NOT NULL,
    "imageUrl" TEXT NOT NULL,
    "caption" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TodoItemPhoto_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "TodoItemPhoto_todoItemId_idx" ON "TodoItemPhoto"("todoItemId");

-- AddForeignKey
ALTER TABLE "TodoItemPhoto" ADD CONSTRAINT "TodoItemPhoto_todoItemId_fkey" FOREIGN KEY ("todoItemId") REFERENCES "TodoItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
