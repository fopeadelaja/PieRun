import type { Db } from "../../db.js";

// The columns safe to hand upward. password_hash is deliberately absent;
// only findByUsername returns it, because login must compare against it.
const publicColumns = {
  id: true,
  username: true,
  first_name: true,
  last_name: true,
  is_admin: true,
} as const;

export function findByUsername(db: Db, username: string) {
  return db.users.findFirst({ where: { username } });
}

export function findById(db: Db, id: bigint) {
  return db.users.findUnique({ where: { id }, select: publicColumns });
}

type NewUser = {
  username: string;
  passwordHash: string;
  firstName: string;
  lastName: string;
};

export function createUser(db: Db, user: NewUser) {
  return db.users.create({
    data: {
      username: user.username,
      password_hash: user.passwordHash,
      first_name: user.firstName,
      last_name: user.lastName,
    },
    select: publicColumns,
  });
}
