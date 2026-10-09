export class UnauthorizedError extends Error {
  status = 401;

  constructor(message = "Unauthorized") {
    super(message);
    this.name = "UnauthorizedError";
  }
}

export class ConflictError extends Error {
  status = 409;

  constructor(message = "Conflict") {
    super(message);
    this.name = "ConflictError";
  }
}
