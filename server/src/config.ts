import "dotenv/config";

// Read an environment variable or refuse to start. A missing secret must
// stop the server, never weaken it (e.g. signing tokens with "").
function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

export const JWT_SECRET = requireEnv("JWT_SECRET");
