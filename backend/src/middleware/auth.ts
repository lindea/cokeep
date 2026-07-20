import { NextFunction, Request, Response } from "express";
import jwt from "jsonwebtoken";
import { config } from "../config/env";
import { AppError } from "./error";

export interface AuthPayload {
  userId: string;
  email: string;
}

export interface AdminPayload {
  role: "admin";
  username: string;
}

export interface AuthenticatedRequest extends Request {
  user?: AuthPayload;
  admin?: AdminPayload;
}

export function signToken(payload: AuthPayload): string {
  return jwt.sign(payload, config.jwtSecret, {
    expiresIn: config.jwtExpiresIn,
  } as jwt.SignOptions);
}

export function signAdminToken(payload: AdminPayload): string {
  return jwt.sign(payload, config.jwtSecret, {
    expiresIn: "12h",
  } as jwt.SignOptions);
}

export function requireAuth(
  req: AuthenticatedRequest,
  _res: Response,
  next: NextFunction
): void {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    next(new AppError(401, "Authentication required"));
    return;
  }

  try {
    const token = header.slice(7);
    const decoded = jwt.verify(token, config.jwtSecret) as AuthPayload & Partial<AdminPayload>;
    if (decoded.role === "admin") {
      next(new AppError(401, "User authentication required"));
      return;
    }
    if (!decoded.userId) {
      next(new AppError(401, "Invalid or expired token"));
      return;
    }
    req.user = { userId: decoded.userId, email: decoded.email };
    next();
  } catch {
    next(new AppError(401, "Invalid or expired token"));
  }
}

export function requireAdmin(
  req: AuthenticatedRequest,
  _res: Response,
  next: NextFunction
): void {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    next(new AppError(401, "Admin authentication required"));
    return;
  }

  try {
    const token = header.slice(7);
    const decoded = jwt.verify(token, config.jwtSecret) as AdminPayload;
    if (decoded.role !== "admin") {
      next(new AppError(403, "Admin access required"));
      return;
    }
    req.admin = decoded;
    next();
  } catch {
    next(new AppError(401, "Invalid or expired admin token"));
  }
}
