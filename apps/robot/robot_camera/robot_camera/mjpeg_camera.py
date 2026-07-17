import math
import socket
import threading

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, CompressedImage

START_OF_IMAGE = b"\xff\xd8"
END_OF_IMAGE = b"\xff\xd9"
READ_CHUNK_BYTES = 65536
STREAM_PATH = "/stream"


def pinhole_intrinsics(width, height, fov_deg):
    focal = (width / 2.0) / math.tan(math.radians(fov_deg) / 2.0)
    return focal, focal, width / 2.0, height / 2.0


class MjpegCamera(Node):
    def __init__(self):
        super().__init__("camera")
        self.name = self.declare_parameter("name", "camera_0").value
        self.source = self.declare_parameter("source", "rpi5-16-2:8887").value
        self.image_topic = self.declare_parameter(
            "image_topic", "color/image/compressed"
        ).value
        self.camera_info_topic = self.declare_parameter(
            "camera_info_topic", "color/camera_info"
        ).value
        self.frame_id = self.declare_parameter(
            "frame_id", f"{self.name}_color_optical_frame"
        ).value
        self.stream_path = self.declare_parameter("stream_path", STREAM_PATH).value
        width = self.declare_parameter("width", 1280).value
        height = self.declare_parameter("height", 720).value
        fov_deg = self.declare_parameter("fov_deg", 90.0).value
        self.publish_period = 1.0 / self.declare_parameter("publish_rate", 20.0).value

        self.image_publisher = self.create_publisher(
            CompressedImage, self.image_topic, qos_profile_sensor_data
        )
        self.camera_info_publisher = self.create_publisher(
            CameraInfo, self.camera_info_topic, qos_profile_sensor_data
        )
        self.camera_info = self._build_camera_info(width, height, fov_deg)

        self.stopped = threading.Event()
        self.reader = threading.Thread(target=self._read_loop, daemon=True)
        self.reader.start()

    def _build_camera_info(self, width, height, fov_deg):
        focal_x, focal_y, center_x, center_y = pinhole_intrinsics(width, height, fov_deg)
        info = CameraInfo()
        info.width = int(width)
        info.height = int(height)
        info.distortion_model = "plumb_bob"
        info.d = [0.0] * 5
        info.k = [focal_x, 0.0, center_x, 0.0, focal_y, center_y, 0.0, 0.0, 1.0]
        info.r = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
        info.p = [focal_x, 0.0, center_x, 0.0, 0.0, focal_y, center_y, 0.0, 0.0, 0.0, 1.0, 0.0]
        return info

    def _read_loop(self):
        host, _, port = self.source.partition(":")
        while not self.stopped.is_set() and rclpy.ok():
            try:
                self._stream(host, int(port))
            except OSError as error:
                self.get_logger().warn(f"camera stream {self.source} lost ({error}); retrying")
                self.stopped.wait(1.0)

    def _stream(self, host, port):
        connection = socket.create_connection((host, port), timeout=5.0)
        connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        if self.stream_path:
            connection.sendall(
                f"GET {self.stream_path} HTTP/1.0\r\nHost: {host}:{port}\r\n\r\n".encode()
            )
        self.get_logger().info(f"streaming camera from {host}:{port} -> {self.image_topic}")
        buffer = bytearray()
        last_publish = 0.0
        while not self.stopped.is_set() and rclpy.ok():
            chunk = connection.recv(READ_CHUNK_BYTES)
            if not chunk:
                break
            buffer.extend(chunk)
            for frame in self._take_frames(buffer):
                seconds = self.get_clock().now().nanoseconds / 1e9
                if seconds - last_publish < self.publish_period:
                    continue
                last_publish = seconds
                self._publish(frame)
        connection.close()

    def _take_frames(self, buffer):
        while True:
            start = buffer.find(START_OF_IMAGE)
            if start < 0:
                break
            end = buffer.find(END_OF_IMAGE, start + 2)
            if end < 0:
                break
            end += 2
            frame = bytes(buffer[start:end])
            del buffer[:end]
            yield frame

    def _publish(self, frame):
        stamp = self.get_clock().now().to_msg()
        image = CompressedImage()
        image.header.stamp = stamp
        image.header.frame_id = self.frame_id
        image.format = "jpeg"
        image.data = frame
        self.image_publisher.publish(image)
        self.camera_info.header.stamp = stamp
        self.camera_info.header.frame_id = self.frame_id
        self.camera_info_publisher.publish(self.camera_info)

    def destroy_node(self):
        self.stopped.set()
        super().destroy_node()


def main():
    rclpy.init()
    node = MjpegCamera()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
