import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import type { User } from "../../../../shared/types.js";
import prisma from "../../db.js";
import { createUser, findByUsername } from "./repo.js";
import { UnauthorizedError } from "../../errors.js";

const BCRYPT_COST = 10;
const JWT_SECRET =
  process.env.JWT_SECRET ??
  (() => {
    throw new Error("JWT_SECRET is not set");
  })();

type RegisterInput = {
  username: string;
  password: string;
  firstName: string;
  lastName: string;
};

// Usernames are case-insensitive (index on lower(username)); the app
// lowercases on the way in so stored values and lookups always agree.
function normaliseUsername(username: string): string {
  return username.trim().toLowerCase();
}

// The row as the repo returns it (shaped by its `select`). Derived rather
// than written out so it stays correct when the select changes.
type UserRow = {
  id: bigint;
  username: string;
  first_name: string;
  last_name: string;
  is_admin: boolean;
};

// Row → wire shape. BigInt id becomes a string; snake_case becomes camelCase.
function toUser(row: UserRow): User {
  return {
    id: row.id.toString(),
    username: row.username,
    firstName: row.first_name,
    lastName: row.last_name,
    isAdmin: row.is_admin,
  };
}

export async function registerUser(input: RegisterInput): Promise<User> {
  const passwordHash = await bcrypt.hash(input.password, BCRYPT_COST);

  const row = await createUser(prisma, {
    username: normaliseUsername(input.username),
    passwordHash,
    firstName: input.firstName.trim(),
    lastName: input.lastName.trim(),
  });

  return toUser(row);
}

export async function loginUser(username: string, password: string) {
  const user = await findByUsername(prisma, normaliseUsername(username));
  if (!user) {
    throw new UnauthorizedError();
  }

  const isMatch = await bcrypt.compare(password, user.password_hash);
  if (!isMatch) {
    throw new UnauthorizedError();
  }

  return jwt.sign(
    { userId: user.id.toString(), isAdmin: user.is_admin },
    JWT_SECRET,
    {
      expiresIn: "7d",
    },
  );
}
