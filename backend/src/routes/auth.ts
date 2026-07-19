import { Router } from "express";
import bcrypt from "bcryptjs";
import { randomBytes } from "crypto";
import { z } from "zod";
import { prisma } from "../config/db";
import { config } from "../config/env";
import { AuthenticatedRequest, requireAuth, signToken } from "../middleware/auth";
import { AppError } from "../middleware/error";
import { sendEmail } from "../services/email";
import { normalizePhone, publicUser } from "../utils/helpers";

const router = Router();

const registerSchema = z.object({
  firstName: z.string().min(1).max(80),
  lastName: z.string().min(1).max(80),
  email: z.string().email(),
  countryCode: z.string().min(1).max(6),
  phone: z.string().min(4).max(20),
  password: z.string().min(5).max(128),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

router.post("/register", async (req, res, next) => {
  try {
    const body = registerSchema.parse(req.body);
    const phoneE164 = normalizePhone(body.phone, body.countryCode);
    const email = body.email.toLowerCase().trim();

    const existing = await prisma.user.findFirst({
      where: { OR: [{ email }, { phoneE164 }] },
    });
    if (existing) {
      throw new AppError(409, "A user with this email or phone already exists");
    }

    const passwordHash = await bcrypt.hash(body.password, 12);
    const user = await prisma.user.create({
      data: {
        firstName: body.firstName.trim(),
        lastName: body.lastName.trim(),
        email,
        phoneE164,
        countryCode: body.countryCode.startsWith("+")
          ? body.countryCode
          : `+${body.countryCode}`,
        passwordHash,
      },
    });

    // Auto-accept pending invites matching this phone number.
    const pendingInvites = await prisma.invite.findMany({
      where: { phoneE164, status: "PENDING" },
    });

    for (const invite of pendingInvites) {
      await prisma.$transaction([
        prisma.objectMembership.upsert({
          where: {
            objectId_userId: { objectId: invite.objectId, userId: user.id },
          },
          create: {
            objectId: invite.objectId,
            userId: user.id,
            role: "MEMBER",
            status: "ACTIVE",
          },
          update: { status: "ACTIVE", leftAt: null },
        }),
        prisma.invite.update({
          where: { id: invite.id },
          data: {
            status: "ACCEPTED",
            respondedAt: new Date(),
            recipientUserId: user.id,
          },
        }),
      ]);
    }

    const token = signToken({ userId: user.id, email: user.email });
    res.status(201).json({ token, user: publicUser(user) });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.post("/login", async (req, res, next) => {
  try {
    const body = loginSchema.parse(req.body);
    const user = await prisma.user.findUnique({
      where: { email: body.email.toLowerCase().trim() },
    });
    if (!user || !(await bcrypt.compare(body.password, user.passwordHash))) {
      throw new AppError(401, "Invalid email or password");
    }
    const token = signToken({ userId: user.id, email: user.email });
    res.json({ token, user: publicUser(user) });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

router.get("/me", requireAuth, async (req: AuthenticatedRequest, res, next) => {
  try {
    const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.userId } });
    res.json({ user: publicUser(user) });
  } catch (err) {
    next(err);
  }
});

router.post("/forgot-password", async (req, res, next) => {
  try {
    const email = z.string().email().parse(req.body.email).toLowerCase().trim();
    const user = await prisma.user.findUnique({ where: { email } });

    // Always return success to avoid account enumeration.
    if (user) {
      const token = randomBytes(32).toString("hex");
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000);
      await prisma.passwordResetToken.create({
        data: { userId: user.id, token, expiresAt },
      });

      const deepLink = `${config.deepLinkScheme}://reset-password?token=${token}`;
      const webFallback = `${config.appBaseUrl}/reset-password?token=${token}`;
      await sendEmail(
        user.email,
        "Reset your CoKeep password",
        `Reset your password by opening this link in the CoKeep app:\n\n${deepLink}\n\nOr visit: ${webFallback}\n\nThis link expires in 1 hour.`,
        `<p>Reset your password by opening this link in the CoKeep app:</p><p><a href="${deepLink}">${deepLink}</a></p><p>Or <a href="${webFallback}">open in browser</a>.</p><p>This link expires in 1 hour.</p>`
      );
    }

    res.json({ ok: true, message: "If that email exists, a reset link has been sent." });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid email") : err);
  }
});

router.post("/reset-password", async (req, res, next) => {
  try {
    const body = z
      .object({
        token: z.string().min(10),
        password: z.string().min(5).max(128),
      })
      .parse(req.body);

    const reset = await prisma.passwordResetToken.findUnique({
      where: { token: body.token },
    });
    if (!reset || reset.usedAt || reset.expiresAt < new Date()) {
      throw new AppError(400, "Invalid or expired reset token");
    }

    const passwordHash = await bcrypt.hash(body.password, 12);
    await prisma.$transaction([
      prisma.user.update({
        where: { id: reset.userId },
        data: { passwordHash },
      }),
      prisma.passwordResetToken.update({
        where: { id: reset.id },
        data: { usedAt: new Date() },
      }),
    ]);

    res.json({ ok: true });
  } catch (err) {
    next(err instanceof z.ZodError ? new AppError(400, "Invalid input", err.flatten()) : err);
  }
});

export default router;
