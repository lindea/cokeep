import { config } from "../config/env";

/** Sends SMS. Uses console logging when Twilio is not configured. */
export async function sendSms(toE164: string, body: string): Promise<void> {
  if (!config.twilio.accountSid || !config.twilio.authToken || !config.twilio.fromNumber) {
    console.log(`[sms:dev] to=${toE164}\n${body}`);
    return;
  }

  const auth = Buffer.from(
    `${config.twilio.accountSid}:${config.twilio.authToken}`
  ).toString("base64");

  const params = new URLSearchParams({
    To: toE164,
    From: config.twilio.fromNumber,
    Body: body,
  });

  const response = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${config.twilio.accountSid}/Messages.json`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${auth}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params,
    }
  );

  if (!response.ok) {
    const errText = await response.text();
    console.error("Twilio SMS failed:", errText);
    throw new Error("Failed to send SMS");
  }
}
