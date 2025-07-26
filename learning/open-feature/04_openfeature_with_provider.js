import express from "express";
import Router from "express-promise-router";
import cowsay from "cowsay";
import { OpenFeature, InMemoryProvider } from "@openfeature/server-sdk";

const app = express();
const routes = Router();
app.use((_, res, next) => {
  res.setHeader("content-type", "text/plain");
  next();
}, routes);

const featureFlags = OpenFeature.getClient();

const FLAG_CONFIGURATION = {
  'with-cows': {
    variants: {
      on: true,
      off: false
    },
    disabled: false,
    defaultVariant: "on"
  }
};

const featureFlagProvider = new InMemoryProvider(FLAG_CONFIGURATION);

OpenFeature.setProvider(featureFlagProvider);

routes.get("/", async (_, res) => {
  const withCows = await featureFlags.getBooleanValue("with-cows", false);
  if (withCows) {
    res.send(cowsay.say({ text: "Hello, world!" }));
  } else {
    res.send("Hello, world!");
  }
});

app.listen(3333, () => {
  console.log("Server running at http://localhost:3333");
});
