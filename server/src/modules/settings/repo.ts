import type { Db } from "../../db.js";

// R5: exactly one row, id = TRUE, guaranteed by the schema. findUniqueOrThrow
// because a missing row is a broken database, not a user-facing condition.
export function getSettingsRow(db: Db) {
  return db.settings.findUniqueOrThrow({ where: { id: true } });
}
