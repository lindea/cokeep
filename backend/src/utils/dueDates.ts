/** Milliseconds in one UTC calendar day. */
const DAY_MS = 24 * 60 * 60 * 1000;

/** UTC midnight for the calendar day of `date`. */
export function startOfUtcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

/** Add `days` to a date in UTC calendar space. */
export function addUtcDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * DAY_MS);
}

/**
 * Inclusive due-soon window: from start of today (UTC) through end of today+7 (UTC).
 * Date-only due dates are stored as noon UTC of the chosen calendar day.
 */
export function dueSoonWindow(now: Date = new Date()): { from: Date; to: Date } {
  const from = startOfUtcDay(now);
  const to = new Date(addUtcDays(from, 8).getTime() - 1);
  return { from, to };
}

/** Overdue once the due calendar day is before today (UTC). */
export function overdueBefore(now: Date = new Date()): Date {
  return startOfUtcDay(now);
}

/** True when `dueDate` falls on today…today+7 (UTC calendar days). */
export function isDueSoon(dueDate: Date, now: Date = new Date()): boolean {
  const { from, to } = dueSoonWindow(now);
  return dueDate >= from && dueDate <= to;
}

/** True when `dueDate`'s UTC calendar day is before today's. */
export function isOverdue(dueDate: Date, now: Date = new Date()): boolean {
  return dueDate < overdueBefore(now);
}
