/** Compares dotted version strings (e.g. "1.2.0" vs "1.10"). */
export function compareVersions(a: string, b: string): number {
  const pa = a.split(".").map((p) => parseInt(p, 10) || 0);
  const pb = b.split(".").map((p) => parseInt(p, 10) || 0);
  const n = Math.max(pa.length, pb.length);
  for (let i = 0; i < n; i++) {
    const x = pa[i] ?? 0;
    const y = pb[i] ?? 0;
    if (x < y) return -1;
    if (x > y) return 1;
  }
  return 0;
}

export type VersionOp = "ANY" | "EQ" | "LT" | "LTE" | "GT" | "GTE" | "BETWEEN";

/** Returns whether `installed` matches the splash version rule. */
export function matchesVersionRule(
  installed: string,
  op: VersionOp,
  versionA: string | null | undefined,
  versionB: string | null | undefined
): boolean {
  const a = versionA?.trim() || "";
  const b = versionB?.trim() || "";

  switch (op) {
    case "ANY":
      return true;
    case "EQ":
      return Boolean(a) && compareVersions(installed, a) === 0;
    case "LT":
      return Boolean(a) && compareVersions(installed, a) < 0;
    case "LTE":
      return Boolean(a) && compareVersions(installed, a) <= 0;
    case "GT":
      return Boolean(a) && compareVersions(installed, a) > 0;
    case "GTE":
      return Boolean(a) && compareVersions(installed, a) >= 0;
    case "BETWEEN":
      return (
        Boolean(a) &&
        Boolean(b) &&
        compareVersions(installed, a) >= 0 &&
        compareVersions(installed, b) <= 0
      );
    default:
      return false;
  }
}
