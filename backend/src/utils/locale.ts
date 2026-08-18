/** App languages — same rules as iOS LocalizationStore / L10n.appLanguageCode. */
export type AppLang = "en" | "nb";

export function normalizeAppLang(raw: string | undefined | null): AppLang {
  const lang = (raw || "en").trim().toLowerCase();
  if (lang.startsWith("nb") || lang.startsWith("nn") || lang.startsWith("no")) {
    return "nb";
  }
  return "en";
}

type PushCopy = { title: string; body: string };

/** Localized push / in-app notification strings. */
export function invitePushCopy(
  lang: AppLang,
  inviterName: string,
  objectName: string
): PushCopy {
  if (lang === "nb") {
    return {
      title: "CoKeep",
      body: `${inviterName} har invitert deg til «${objectName}»`,
    };
  }
  return {
    title: "CoKeep",
    body: `${inviterName} invited you to join "${objectName}"`,
  };
}

export function todoDueSoonPushCopy(
  lang: AppLang,
  itemName: string,
  objectName: string
): PushCopy {
  if (lang === "nb") {
    return {
      title: "CoKeep",
      body: `«${itemName}» på ${objectName} forfaller innen en uke`,
    };
  }
  return {
    title: "CoKeep",
    body: `"${itemName}" on ${objectName} is due within a week`,
  };
}

export function todoOverduePushCopy(
  lang: AppLang,
  itemName: string,
  objectName: string
): PushCopy {
  if (lang === "nb") {
    return {
      title: "CoKeep",
      body: `«${itemName}» på ${objectName} er forfalt`,
    };
  }
  return {
    title: "CoKeep",
    body: `"${itemName}" on ${objectName} is overdue`,
  };
}

export function todoAssignedPushCopy(
  lang: AppLang,
  assignerName: string,
  itemName: string,
  objectName: string
): PushCopy {
  if (lang === "nb") {
    return {
      title: "CoKeep",
      body: `${assignerName} har satt deg som ansvarlig for «${itemName}» på ${objectName}`,
    };
  }
  return {
    title: "CoKeep",
    body: `${assignerName} assigned you to "${itemName}" on ${objectName}`,
  };
}
