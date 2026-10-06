import express from "express";
import snacksRouter from "./modules/snacks/routes.js";

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use("/snacks", snacksRouter);

app.get("/health", (req, res) => {
  res.json({ ok: true });
});

app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
