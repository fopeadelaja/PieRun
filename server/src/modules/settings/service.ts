import type { Db } from "../../db.js";
import { getSettingsRow } from "./repo.js";

export type Weekday = "MON" | "TUE" | "WED" | "THU" | "FRI" | "SAT" | "SUN";

export type FulfillmentSettings = {
  workDays: Weekday[];
  cutoff: { hour: number; minute: number }; // local time in `timezone`
  timezone: string; // IANA name, e.g. "Africa/Lagos"
};

export async function getSettings(db: Db): Promise<FulfillmentSettings> {
  const row = await getSettingsRow(db);
  // Prisma hands a TIME column back as a Date on 1970-01-01 in UTC; only the
  // clock part is meaningful.
  return {
    workDays: row.work_days,
    cutoff: { hour: row.cutoff.getUTCHours(), minute: row.cutoff.getUTCMinutes() },
    timezone: row.timezone,
  };
}

const WEEKDAY_BY_SHORT: Record<string, Weekday> = {
  Mon: "MON",
  Tue: "TUE",
  Wed: "WED",
  Thu: "THU",
  Fri: "FRI",
  Sat: "SAT",
  Sun: "SUN",
};

// The instant `at`, as seen on a wall clock in `timezone`: which weekday it
// is, what time it is, and the calendar date as YYYY-MM-DD.
function localParts(at: Date, timezone: string) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: timezone,
    weekday: "short",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(at);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return {
    weekday: WEEKDAY_BY_SHORT[get("weekday")]!,
    date: `${get("year")}-${get("month")}-${get("day")}`,
    minutesIntoDay: Number(get("hour")) * 60 + Number(get("minute")),
  };
}

// T2/T6/T7: the next workday an order placed at `now` will be fulfilled on.
// Today counts if it is a workday and the cutoff has not passed yet;
// otherwise the next workday after today. Pure: the clock is an argument so
// this can be tested on any date without waiting for it.
export function nextFulfillmentDate(
  now: Date,
  settings: FulfillmentSettings,
): string {
  const cutoffMinutes = settings.cutoff.hour * 60 + settings.cutoff.minute;
  const DAY_MS = 24 * 60 * 60 * 1000;

  for (let offset = 0; offset <= 7; offset++) {
    const candidate = new Date(now.getTime() + offset * DAY_MS);
    const local = localParts(candidate, settings.timezone);
    if (!settings.workDays.includes(local.weekday)) continue;
    if (offset === 0 && local.minutesIntoDay >= cutoffMinutes) continue;
    return local.date;
  }
  // T5 guarantees at least one workday, so this is unreachable with a sane
  // settings row. Fail loudly rather than return a wrong date.
  throw new Error("No workday found within the next 7 days");
}
