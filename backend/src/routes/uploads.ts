import { Router } from "express";
import fs from "fs";
import multer from "multer";
import path from "path";
import { randomUUID } from "crypto";
import { config } from "../config/env";
import { AuthenticatedRequest, requireAuth } from "../middleware/auth";
import { AppError } from "../middleware/error";
import { isS3Configured, uploadImageToS3 } from "../services/s3";

const router = Router();

if (!fs.existsSync(config.uploadDir)) {
  fs.mkdirSync(config.uploadDir, { recursive: true });
}

const diskStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, config.uploadDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase() || ".jpg";
    cb(null, `${randomUUID()}${ext}`);
  },
});

const upload = multer({
  storage: isS3Configured() ? multer.memoryStorage() : diskStorage,
  limits: { fileSize: config.maxUploadMb * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith("image/")) {
      cb(new AppError(400, "Only image uploads are allowed"));
      return;
    }
    cb(null, true);
  },
});

router.post("/", requireAuth, upload.single("file"), async (req: AuthenticatedRequest, res, next) => {
  try {
    if (!req.file) {
      throw new AppError(400, "No file uploaded");
    }

    if (isS3Configured()) {
      if (!req.file.buffer) {
        throw new AppError(500, "Upload buffer missing");
      }
      const { url, key } = await uploadImageToS3(
        req.file.buffer,
        req.file.originalname,
        req.file.mimetype
      );
      res.status(201).json({
        url,
        filename: key,
        size: req.file.size,
        mimeType: req.file.mimetype,
        storage: "s3",
      });
      return;
    }

    const url = `${config.appBaseUrl}/uploads/${req.file.filename}`;
    res.status(201).json({
      url,
      filename: req.file.filename,
      size: req.file.size,
      mimeType: req.file.mimetype,
      storage: "local",
    });
  } catch (err) {
    next(err);
  }
});

export default router;
