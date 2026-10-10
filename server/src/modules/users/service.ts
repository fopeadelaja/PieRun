import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
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

export async function registerUser(input: RegisterInput) {
  const passwordHash = await bcrypt.hash(input.password, BCRYPT_COST);

  return createUser(prisma, {
    username: normaliseUsername(input.username),
    passwordHash,
    firstName: input.firstName.trim(),
    lastName: input.lastName.trim(),
  });
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
