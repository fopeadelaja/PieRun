import express from "express";

const app = express();

app.use(express.json());

app.get("/health", (req, res) => {
  res.json({ ok: true });    
})


app.listen(3000, () => {
  console.log("Server is running on port 3000");
})