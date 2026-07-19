import nodemailer from "nodemailer";
import { config } from "../config/env";

export async function sendEmail(to: string, subject: string, text: string, html?: string): Promise<void> {
  if (!config.smtp.host) {
    console.log(`[email:dev] to=${to} subject=${subject}\n${text}`);
    return;
  }

  const transporter = nodemailer.createTransport({
    host: config.smtp.host,
    port: config.smtp.port,
    secure: config.smtp.port === 465,
    auth: config.smtp.user
      ? { user: config.smtp.user, pass: config.smtp.pass }
      : undefined,
  });

  await transporter.sendMail({
    from: config.smtp.from,
    to,
    subject,
    text,
    html: html ?? text,
  });
}
