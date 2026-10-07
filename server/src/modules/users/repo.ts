import type { Db } from "../../db.js";

export function findByUsername(db: Db, username: string) {
  return db.users.findFirst({ where: { username } });
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
    select: {
      username: true,
      first_name: true,
      last_name: true,
    },
  });
}
