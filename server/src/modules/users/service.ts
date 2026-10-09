import bcrypt from "bcrypt";
import prisma from "../../db.js";
import { createUser } from "./repo.js";

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

export async function registerUser(input: RegisterInput) {
  const passwordHash = await bcrypt.hash(input.password, BCRYPT_COST);

  return createUser(prisma, {
    username: normaliseUsername(input.username),
    passwordHash,
    firstName: input.firstName.trim(),
    lastName: input.lastName.trim(),
  });
}
