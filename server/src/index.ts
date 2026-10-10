import express from "express";
import cookieParser from "cookie-parser";
import { errorHandler } from "./middleware/errorHandler.js";
import snacksRouter from "./modules/snacks/routes.js";
import usersRouter from "./modules/users/routes.js";

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(cookieParser());

app.use("/snacks", snacksRouter);
app.use("/users", usersRouter);

app.get("/health", (req, res) => {
  res.json({ ok: true });
});

// After every route, so thrown errors from any handler land here.
app.use(errorHandler);

app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
