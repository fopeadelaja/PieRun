import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import type { User } from "../../../../shared/types.js";
import {
  NAME_RE,
  NAME_RULE,
  USERNAME_MIN_LENGTH,
  USERNAME_RE,
  USERNAME_RULE,
} from "../../../../shared/validation.js";
import { Prisma } from "../../../generated/prisma/client.js";
import { JWT_SECRET } from "../../config.js";
import prisma from "../../db.js";
import { createUser, findById, findByUsername } from "./repo.js";
import {
  ConflictError,
  NotFoundError,
  UnauthorizedError,
  ValidationError,
} from "../../errors.js";

const BCRYPT_COST = 10;

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

// Domain rules for a new account. These live here, not in the route, so
// every caller (route, seed script, test) gets the same rules. The CHECK
// constraints in 003_name_format.sql are the guard behind them.
function validateRegistration(input: {
  username: string;
  firstName: string;
  lastName: string;
}): void {
  if (input.username.length < USERNAME_MIN_LENGTH) {
    throw new ValidationError(
      `username must be at least ${USERNAME_MIN_LENGTH} characters`,
    );
  }
  if (!USERNAME_RE.test(input.username)) {
    throw new ValidationError(`username: ${USERNAME_RULE}`);
  }
  if (!NAME_RE.test(input.firstName)) {
    throw new ValidationError(`firstName: ${NAME_RULE}`);
  }
  if (!NAME_RE.test(input.lastName)) {
    throw new ValidationError(`lastName: ${NAME_RULE}`);
  }
}

export async function registerUser(input: RegisterInput): Promise<User> {
  const username = normaliseUsername(input.username);
  const firstName = input.firstName.trim();
  const lastName = input.lastName.trim();
  validateRegistration({ username, firstName, lastName });

  const passwordHash = await bcrypt.hash(input.password, BCRYPT_COST);

  // No check-then-insert: two concurrent registrations would both pass the
  // check. The unique index on lower(username) is the only atomic guard, so
  // let it decide and translate its violation into a domain error.
  try {
    const row = await createUser(prisma, {
      username,
      passwordHash,
      firstName,
      lastName,
    });
    return toUser(row);
  } catch (err) {
    if (
      err instanceof Prisma.PrismaClientKnownRequestError &&
      err.code === "P2002"
    ) {
      throw new ConflictError("Username already taken");
    }
    throw err;
  }
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

// Ids are strings on the wire and bigint in the database; the conversion
// happens here, at the edge of the module, in one place.
export async function getUserById(id: string): Promise<User> {
  const row = await findById(prisma, BigInt(id));
  if (!row) throw new NotFoundError("User not found");
  return toUser(row);
}
