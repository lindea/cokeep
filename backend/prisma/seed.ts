import bcrypt from "bcryptjs";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
  const passwordHash = await bcrypt.hash("demo123", 12);

  const alice = await prisma.user.upsert({
    where: { email: "alice@example.com" },
    update: {},
    create: {
      firstName: "Alice",
      lastName: "Nord",
      email: "alice@example.com",
      phoneE164: "+4711111111",
      countryCode: "+47",
      passwordHash,
    },
  });

  const bob = await prisma.user.upsert({
    where: { email: "bob@example.com" },
    update: {},
    create: {
      firstName: "Bob",
      lastName: "Fjell",
      email: "bob@example.com",
      phoneE164: "+4722222222",
      countryCode: "+47",
      passwordHash,
    },
  });

  const existing = await prisma.sharedObject.findFirst({
    where: { name: "Demo Cabin", createdById: alice.id },
  });
  if (existing) {
    console.log("Seed already applied");
    return;
  }

  const cabin = await prisma.sharedObject.create({
    data: {
      name: "Demo Cabin",
      template: "CABIN",
      createdById: alice.id,
      members: {
        create: [
          { userId: alice.id, role: "OWNER", status: "ACTIVE" },
          { userId: bob.id, role: "MEMBER", status: "ACTIVE" },
        ],
      },
      todoLists: {
        create: [
          { name: "Maintenance", sortOrder: 0 },
          { name: "Seasonal", sortOrder: 1 },
          { name: "Shopping", sortOrder: 2 },
        ],
      },
    },
    include: { todoLists: true },
  });

  const maintenance = cabin.todoLists.find((l) => l.name === "Maintenance")!;
  const due = new Date();
  due.setDate(due.getDate() + 3);

  await prisma.todoItem.create({
    data: {
      listId: maintenance.id,
      name: "Clean gutters",
      description: "Remove leaves and check downpipes",
      scheduleType: "RECURRING",
      recurrence: "YEARLY",
      dueDate: due,
      assigneeId: bob.id,
    },
  });

  console.log("Seeded demo users alice@example.com / bob@example.com (password: demo123)");
  console.log(`Object: ${cabin.name} (${cabin.id})`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
