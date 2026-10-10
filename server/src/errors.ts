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

export class NotFoundError extends Error {
  status = 404;

  constructor(message = "Not Found") {
    super(message);
    this.name = "NotFoundError";
  }
}

// Input that fails a domain rule (format, range, required). Thrown by routes
// for shape problems and by services for rule problems; both are a 400.
export class ValidationError extends Error {
  status = 400;

  constructor(message = "Invalid input") {
    super(message);
    this.name = "ValidationError";
  }
}
