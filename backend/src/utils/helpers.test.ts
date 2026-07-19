import test from "node:test";
import assert from "node:assert/strict";
import { minutesBetween } from "./helpers";

test("minutesBetween rounds duration", () => {
  const start = new Date("2026-01-01T10:00:00Z");
  const end = new Date("2026-01-01T11:30:00Z");
  assert.equal(minutesBetween(start, end), 90);
});

test("minutesBetween never negative", () => {
  const start = new Date("2026-01-01T12:00:00Z");
  const end = new Date("2026-01-01T11:00:00Z");
  assert.equal(minutesBetween(start, end), 0);
});
