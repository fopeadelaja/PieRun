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
export class BadRequestError extends Error {
  status = 400;

  constructor(message = "Bad Request") {
    super(message);
    this.name = "BadRequestError";
  }
}
