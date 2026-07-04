import rclpy
from diagnostic_msgs.msg import DiagnosticStatus
from diagnostic_updater import (
    DiagnosedPublisher,
    FrequencyStatusParam,
    TimeStampStatusParam,
    Updater,
)
from nav_msgs.msg import Odometry
from rclpy.node import Node
from sensor_msgs.msg import BatteryState, CameraInfo, Image, NavSatFix, NavSatStatus

from robot.camera_view import intrinsics, render_field
from robot.kinematics import enu_to_geodetic, yaw_from_quaternion

IMAGE_WIDTH = 640
IMAGE_HEIGHT = 400
CAMERA_FOV_DEG = 70.0
CAMERA_HEIGHT = 0.2
LATITUDE_ORIGIN = 45.4215
LONGITUDE_ORIGIN = -75.6972

BASE_FRAME = "base_link"
CAMERA_FRAME = "camera_optical_frame"


class Sim(Node):
    def __init__(self):
        super().__init__("simulator")
        self.x = 0.0
        self.y = 0.0
        self.theta = 0.0
        self.speed = 0.0
        self.battery_percent = 100.0

        self.diagnostics = Updater(self)
        self.diagnostics.setHardwareID("simulator")

        self.image_pub = DiagnosedPublisher(
            self.create_publisher(Image, "camera/image_raw", 10),
            self.diagnostics,
            FrequencyStatusParam({"min": 10.0, "max": 20.0}),
            TimeStampStatusParam(),
        )
        self.camera_info_pub = self.create_publisher(CameraInfo, "camera/camera_info", 10)
        self.gps_pub = self.create_publisher(NavSatFix, "gps/fix", 10)
        self.battery_pub = self.create_publisher(BatteryState, "battery", 10)
        self.diagnostics.add("battery", self.diagnose_battery)

        self.create_subscription(Odometry, "/diff_drive_controller/odom", self.on_odom, 10)
        self.create_timer(1.0 / 15.0, self.publish_camera)
        self.create_timer(0.2, self.publish_gps)
        self.create_timer(1.0, self.publish_battery)
        self.get_logger().info("sim sensors ready, tracking /diff_drive_controller/odom")

    def on_odom(self, msg):
        self.x = msg.pose.pose.position.x
        self.y = msg.pose.pose.position.y
        self.theta = yaw_from_quaternion(
            msg.pose.pose.orientation.z, msg.pose.pose.orientation.w
        )
        self.speed = abs(msg.twist.twist.linear.x) + abs(msg.twist.twist.angular.z)

    def publish_camera(self):
        stamp = self.get_clock().now().to_msg()
        frame = render_field(
            self.x, self.y, self.theta, IMAGE_WIDTH, IMAGE_HEIGHT, CAMERA_FOV_DEG, CAMERA_HEIGHT
        )
        image = Image()
        image.header.stamp = stamp
        image.header.frame_id = CAMERA_FRAME
        image.height = IMAGE_HEIGHT
        image.width = IMAGE_WIDTH
        image.encoding = "rgb8"
        image.is_bigendian = 0
        image.step = IMAGE_WIDTH * 3
        image.data = frame.tobytes()
        self.image_pub.publish(image)
        self.camera_info_pub.publish(self.make_camera_info(stamp))

    def make_camera_info(self, stamp):
        fx, fy, cx, cy = intrinsics(IMAGE_WIDTH, IMAGE_HEIGHT, CAMERA_FOV_DEG)
        info = CameraInfo()
        info.header.stamp = stamp
        info.header.frame_id = CAMERA_FRAME
        info.width = IMAGE_WIDTH
        info.height = IMAGE_HEIGHT
        info.distortion_model = "plumb_bob"
        info.d = [0.0, 0.0, 0.0, 0.0, 0.0]
        info.k = [fx, 0.0, cx, 0.0, fy, cy, 0.0, 0.0, 1.0]
        info.r = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
        info.p = [fx, 0.0, cx, 0.0, 0.0, fy, cy, 0.0, 0.0, 0.0, 1.0, 0.0]
        return info

    def publish_gps(self):
        latitude, longitude = enu_to_geodetic(self.x, self.y, LATITUDE_ORIGIN, LONGITUDE_ORIGIN)
        fix = NavSatFix()
        fix.header.stamp = self.get_clock().now().to_msg()
        fix.header.frame_id = BASE_FRAME
        fix.status.status = NavSatStatus.STATUS_FIX
        fix.status.service = NavSatStatus.SERVICE_GPS
        fix.latitude = latitude
        fix.longitude = longitude
        fix.altitude = 0.0
        fix.position_covariance = [
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 4.0,
        ]
        fix.position_covariance_type = NavSatFix.COVARIANCE_TYPE_DIAGONAL_KNOWN
        self.gps_pub.publish(fix)

    def publish_battery(self):
        self.battery_percent = max(0.0, self.battery_percent - (0.02 + 0.5 * self.speed))
        battery = BatteryState()
        battery.header.stamp = self.get_clock().now().to_msg()
        battery.voltage = 11.5 + 1.2 * (self.battery_percent / 100.0)
        battery.percentage = self.battery_percent / 100.0
        battery.power_supply_status = BatteryState.POWER_SUPPLY_STATUS_DISCHARGING
        battery.present = True
        self.battery_pub.publish(battery)

    def diagnose_battery(self, stat):
        stat.add("percentage", f"{self.battery_percent:.0f}%")
        if self.battery_percent < 10.0:
            stat.summary(DiagnosticStatus.ERROR, f"critical: {self.battery_percent:.0f}%")
        elif self.battery_percent < 30.0:
            stat.summary(DiagnosticStatus.WARN, f"low: {self.battery_percent:.0f}%")
        else:
            stat.summary(DiagnosticStatus.OK, f"{self.battery_percent:.0f}%")
        return stat


def main():
    rclpy.init()
    node = Sim()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
