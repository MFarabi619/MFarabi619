#!/usr/bin/env python3

import sys
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CompressedImage

CAMERAS = ["camera_0", "camera_1"]
COMPRESSED_SUFFIX = "/color/image/compressed"
FORBIDDEN_SUFFIXES = [
    "/color/image/compressedDepth",
    "/color/image/zstd",
    "/color/image/theora",
]
WARMUP_TIMEOUT_SECONDS = 6.0
COLLECT_SECONDS = 4.0
MINIMUM_RATE_HZ = 5.0


def evaluate(cameras, advertised, frame_counts, window_seconds, minimum_rate_hz):
    failures = []
    for camera in cameras:
        compressed = f"/sensors/{camera}{COMPRESSED_SUFFIX}"
        if compressed not in advertised:
            failures.append(f"{compressed} not advertised (image_bridge down?)")
        for suffix in FORBIDDEN_SUFFIXES:
            junk = f"/sensors/{camera}{suffix}"
            if junk in advertised:
                failures.append(f"forbidden transport advertised: {junk}")
        rate = frame_counts.get(camera, 0) / window_seconds
        if rate < minimum_rate_hz:
            failures.append(f"{camera} compressed {rate:.1f} Hz < {minimum_rate_hz} Hz")
    return failures


class CameraPathCheck(Node):
    def __init__(self):
        super().__init__("camera_path_check")
        self.frame_counts = {camera: 0 for camera in CAMERAS}
        for camera in CAMERAS:
            self.create_subscription(
                CompressedImage,
                f"/sensors/{camera}{COMPRESSED_SUFFIX}",
                lambda message, camera=camera: self.count_frame(camera),
                qos_profile_sensor_data,
            )

    def count_frame(self, camera):
        self.frame_counts[camera] += 1

    def advertised(self):
        return {name for name, _ in self.get_topic_names_and_types()}


def collect(node, seconds):
    deadline = time.monotonic() + seconds
    while rclpy.ok() and time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.1)


def wait_for_first_frame(node, timeout_seconds):
    deadline = time.monotonic() + timeout_seconds
    while rclpy.ok() and time.monotonic() < deadline:
        if any(node.frame_counts.values()):
            return
        rclpy.spin_once(node, timeout_sec=0.1)


def main():
    rclpy.init()
    node = CameraPathCheck()
    wait_for_first_frame(node, WARMUP_TIMEOUT_SECONDS)
    for camera in CAMERAS:
        node.frame_counts[camera] = 0
    collect(node, COLLECT_SECONDS)
    failures = evaluate(
        CAMERAS, node.advertised(), node.frame_counts, COLLECT_SECONDS, MINIMUM_RATE_HZ
    )
    counts = dict(node.frame_counts)
    node.destroy_node()
    rclpy.shutdown()

    if failures:
        print("CAMERA PATH FAIL")
        for failure in failures:
            print(f"  - {failure}")
        sys.exit(1)
    rates = ", ".join(f"{c} {counts[c] / COLLECT_SECONDS:.1f} Hz" for c in CAMERAS)
    print(f"CAMERA PATH OK — compressed flowing ({rates}), no junk transports")


if __name__ == "__main__":
    main()
