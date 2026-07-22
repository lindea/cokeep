import { Router } from "express";
import { config } from "../config/env";
import { runDueNotifications } from "../jobs/notifications";
import { AppError } from "../middleware/error";

const router = Router();

/**
 * External cron trigger (e.g. Heroku Scheduler) so due pushes still fire
 * after a sleeping dyno wakes on the HTTP request.
 *
 * POST /api/internal/run-due-notifications
 * Header: X-Cron-Secret: <CRON_SECRET>
 */
router.post("/run-due-notifications", async (req, res, next) => {
  try {
    if (!config.cronSecret) {
      throw new AppError(404, "Not found");
    }
    const provided = req.header("x-cron-secret") || "";
    if (provided !== config.cronSecret) {
      throw new AppError(401, "Unauthorized");
    }

    await runDueNotifications();
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

export default router;
