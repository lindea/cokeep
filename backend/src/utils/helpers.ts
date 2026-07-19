import { parsePhoneNumberFromString } from "libphonenumber-js";
import { AppError } from "../middleware/error";

/** Normalize phone to E.164 using country calling code like "+47". */
export function normalizePhone(phone: string, countryCode: string): string {
  const digits = phone.replace(/[^\d+]/g, "");
  const calling = countryCode.startsWith("+") ? countryCode : `+${countryCode}`;
  const candidate = digits.startsWith("+") ? digits : `${calling}${digits.replace(/^0+/, "")}`;
  const parsed = parsePhoneNumberFromString(candidate);
  if (!parsed || !parsed.isValid()) {
    throw new AppError(400, "Invalid phone number");
  }
  return parsed.format("E.164");
}

export function minutesBetween(start: Date, end: Date): number {
  return Math.max(0, Math.round((end.getTime() - start.getTime()) / 60000));
}

export function publicUser(user: {
  id: string;
  firstName: string;
  lastName: string;
  email: string;
  phoneE164: string;
  countryCode: string;
  avatarUrl: string | null;
}) {
  return {
    id: user.id,
    firstName: user.firstName,
    lastName: user.lastName,
    email: user.email,
    phoneE164: user.phoneE164,
    countryCode: user.countryCode,
    avatarUrl: user.avatarUrl,
  };
}
