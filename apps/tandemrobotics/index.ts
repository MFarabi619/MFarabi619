import * as docker from "@pulumi/docker";
import { createCaddy } from "./caddy.ts";
import { createBehaviorLifecycleManager } from "./nodes/behavior-lifecycle-manager.ts";
import { createBehaviorServer } from "./nodes/behavior-server.ts";
import { createFoxgloveBridge } from "./nodes/foxglove-bridge.ts";
import { createLichtblick } from "./lichtblick.ts";
import { buildRobotImage } from "./robot.ts";
// import { createTalker } from "./nodes/talker.ts";
import { createTwistMux } from "./nodes/twist-mux.ts";
import { createZenohRouter } from "./zenoh-router.ts";

const network = new docker.Network("proxy", {
    name: "proxy",
    labels: [{ label: "managed-by", value: "pulumi" }],
});

const robotImage = buildRobotImage();

createCaddy(network);
createZenohRouter(network);
// createTalker(network, robotImage);
createFoxgloveBridge(network, robotImage);
createLichtblick(network);
createTwistMux(network, robotImage, "robot1");
createBehaviorServer(network, robotImage, "robot1");
createBehaviorLifecycleManager(network, robotImage, "robot1");
