import test from "node:test";
import assert from "node:assert/strict";
import {
  addUtcDays,
  dueSoonWindow,
  isDueSoon,
  isOverdue,
  overdueBefore,
  startOfUtcDay,
} from "./dueDates";

test("startOfUtcDay strips time", () => {
  const d = new Date("2026-07-22T20:21:00.000Z");
  assert.equal(startOfUtcDay(d).toISOString(), "2026-07-22T00:00:00.000Z");
});

test("dueSoonWindow covers today through today+7 inclusive", () => {
  const now = new Date("2026-07-22T20:21:00.000Z");
  const { from, to } = dueSoonWindow(now);
  assert.equal(from.toISOString(), "2026-07-22T00:00:00.000Z");
  assert.equal(to.toISOString(), "2026-07-29T23:59:59.999Z");
});

test("item due 29.07.2026 is due soon on 22.07.2026", () => {
  const now = new Date("2026-07-22T18:00:00.000Z");
  // Date-only due dates are stored as noon UTC of the selected day.
  const due = new Date("2026-07-29T12:00:00.000Z");
  assert.equal(isDueSoon(due, now), true);
  assert.equal(isOverdue(due, now), false);
});

test("item due 30.07.2026 is not yet due soon on 22.07.2026", () => {
  const now = new Date("2026-07-22T18:00:00.000Z");
  const due = new Date("2026-07-30T12:00:00.000Z");
  assert.equal(isDueSoon(due, now), false);
});

test("item due yesterday is overdue", () => {
  const now = new Date("2026-07-22T08:00:00.000Z");
  const due = new Date("2026-07-21T12:00:00.000Z");
  assert.equal(isOverdue(due, now), true);
  assert.equal(isDueSoon(due, now), false);
  assert.ok(due < overdueBefore(now));
});

test("item due today is due soon, not overdue", () => {
  const now = new Date("2026-07-22T20:00:00.000Z");
  const due = new Date("2026-07-22T12:00:00.000Z");
  assert.equal(isDueSoon(due, now), true);
  assert.equal(isOverdue(due, now), false);
});

test("addUtcDays crosses month boundary", () => {
  const start = new Date("2026-07-28T00:00:00.000Z");
  assert.equal(addUtcDays(start, 5).toISOString(), "2026-08-02T00:00:00.000Z");
});
