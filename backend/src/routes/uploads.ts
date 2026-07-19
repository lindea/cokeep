import { Router } from "express";
import fs from "fs";
import multer from "multer";
import path from "path";
import { randomUUID } from "crypto";
import { config } from "../config/env";
import { AuthenticatedRequest, requireAuth } from "../middleware/auth";
import { AppError } from "../middleware/error";

const router = Router();

if (!fs.existsSync(config.uploadDir)) {
  fs.mkdirSync(config.uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, config.uploadDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase() || ".jpg";
    cb(null, `${randomUUID()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: config.maxUploadMb * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith("image/")) {
      cb(new AppError(400, "Only image uploads are allowed"));
      return;
    }
    cb(null, true);
  },
});

router.post(
  "/",
  requireAuth,
  upload.single("file"),
  (req: AuthenticatedRequest, res, next) => {
    try {
      if (!req.file) {
        throw new AppError(400, "No file uploaded");
      }
      const url = `${config.appBaseUrl}/uploads/${req.file.filename}`;
      res.status(201).json({
        url,
        filename: req.file.filename,
        size: req.file.size,
        mimeType: req.file.mimetype,
      });
    } catch (err) {
      next(err);
    }
  }
);

export default router;
