import cv2
import rclpy
from cv_bridge import CvBridge
from rclpy.node import Node
from sensor_msgs.msg import Image


class Camera(Node):
    def __init__(self):
        super().__init__("camera")
        url = self.declare_parameter("url", "").value
        self.frame_id = self.declare_parameter("frame_id", "camera_optical_frame").value
        publish_rate = self.declare_parameter("publish_rate", 30.0).value

        self.bridge = CvBridge()
        self.capture = cv2.VideoCapture(url, cv2.CAP_FFMPEG)
        if not self.capture.isOpened():
            raise RuntimeError(f"could not open camera stream at {url}")

        self.image_pub = self.create_publisher(Image, "image_raw", 10)
        self.create_timer(1.0 / publish_rate, self.publish_frame)
        self.get_logger().info(f"streaming from {url}")

    def publish_frame(self):
        ok, frame = self.capture.read()
        if not ok:
            self.get_logger().warn("dropped frame from camera stream")
            return
        message = self.bridge.cv2_to_imgmsg(frame, encoding="bgr8")
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        self.image_pub.publish(message)

    def shutdown(self):
        self.capture.release()


def main():
    rclpy.init()
    node = Camera()
    try:
        rclpy.spin(node)
    finally:
        node.shutdown()
        node.destroy_node()
        rclpy.shutdown()
