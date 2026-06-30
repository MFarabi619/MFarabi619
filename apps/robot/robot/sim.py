import rclpy
from geometry_msgs.msg import TransformStamped, Twist
from nav_msgs.msg import Odometry
from rclpy.node import Node
from sensor_msgs.msg import BatteryState, CameraInfo, Image, JointState, NavSatFix, NavSatStatus
from tf2_ros import StaticTransformBroadcaster, TransformBroadcaster

from robot.camera_view import intrinsics, render_field
from robot.kinematics import enu_to_geodetic, integrate_pose, yaw_to_quaternion

MAX_LINEAR_VELOCITY = 0.6
MAX_ANGULAR_VELOCITY = 1.5
WHEEL_RADIUS = 0.178
WHEEL_HALF_TRACK = 0.527
IMAGE_WIDTH = 640
IMAGE_HEIGHT = 400
CAMERA_FOV_DEG = 70.0
CAMERA_HEIGHT = 0.2
LATITUDE_ORIGIN = 45.4215
LONGITUDE_ORIGIN = -75.6972

MAP_FRAME = "map"
ODOM_FRAME = "odom"
BASE_FRAME = "base_link"
CAMERA_FRAME = "camera_optical_frame"


class Sim(Node):
    def __init__(self):
        super().__init__("sim")
        self.x = 0.0
        self.y = 0.0
        self.theta = 0.0
        self.linear_velocity = 0.0
        self.angular_velocity = 0.0
        self.battery_percent = 100.0
        self.left_wheel_angle = 0.0
        self.right_wheel_angle = 0.0
        self.last_update = self.get_clock().now()

        self.odom_pub = self.create_publisher(Odometry, "odom", 10)
        self.image_pub = self.create_publisher(Image, "camera/image_raw", 10)
        self.camera_info_pub = self.create_publisher(CameraInfo, "camera/camera_info", 10)
        self.gps_pub = self.create_publisher(NavSatFix, "gps/fix", 10)
        self.battery_pub = self.create_publisher(BatteryState, "battery", 10)
        self.joint_pub = self.create_publisher(JointState, "joint_states", 10)

        self.tf_broadcaster = TransformBroadcaster(self)
        self.static_tf_broadcaster = StaticTransformBroadcaster(self)
        self.publish_static_transforms()

        self.create_subscription(Twist, "cmd_vel", self.on_cmd_vel, 10)
        self.create_timer(0.02, self.update)
        self.create_timer(1.0 / 15.0, self.publish_camera)
        self.create_timer(0.2, self.publish_gps)
        self.create_timer(1.0, self.publish_battery)
        self.get_logger().info("sim ready, subscribed to /cmd_vel")

    def on_cmd_vel(self, msg):
        self.linear_velocity = max(-MAX_LINEAR_VELOCITY, min(MAX_LINEAR_VELOCITY, msg.linear.x))
        self.angular_velocity = max(-MAX_ANGULAR_VELOCITY, min(MAX_ANGULAR_VELOCITY, msg.angular.z))

    def update(self):
        now = self.get_clock().now()
        dt = (now - self.last_update).nanoseconds / 1e9
        self.last_update = now
        if dt <= 0.0:
            return
        self.x, self.y, self.theta = integrate_pose(
            self.x, self.y, self.theta,
            self.linear_velocity, self.angular_velocity, dt,
        )
        drain = (0.02 + 0.5 * (abs(self.linear_velocity) + abs(self.angular_velocity))) * dt
        self.battery_percent = max(0.0, self.battery_percent - drain)
        self.publish_odometry(now)
        self.publish_base_transform(now)
        left_speed = self.linear_velocity - self.angular_velocity * WHEEL_HALF_TRACK
        right_speed = self.linear_velocity + self.angular_velocity * WHEEL_HALF_TRACK
        self.left_wheel_angle += left_speed / WHEEL_RADIUS * dt
        self.right_wheel_angle += right_speed / WHEEL_RADIUS * dt
        self.publish_joint_states(now)

    def publish_odometry(self, stamp):
        qx, qy, qz, qw = yaw_to_quaternion(self.theta)
        odom = Odometry()
        odom.header.stamp = stamp.to_msg()
        odom.header.frame_id = ODOM_FRAME
        odom.child_frame_id = BASE_FRAME
        odom.pose.pose.position.x = self.x
        odom.pose.pose.position.y = self.y
        odom.pose.pose.orientation.x = qx
        odom.pose.pose.orientation.y = qy
        odom.pose.pose.orientation.z = qz
        odom.pose.pose.orientation.w = qw
        odom.twist.twist.linear.x = self.linear_velocity
        odom.twist.twist.angular.z = self.angular_velocity
        odom.pose.covariance[0] = 0.001
        odom.pose.covariance[7] = 0.001
        odom.pose.covariance[35] = 0.01
        odom.twist.covariance[0] = 0.001
        odom.twist.covariance[35] = 0.01
        self.odom_pub.publish(odom)

    def publish_base_transform(self, stamp):
        qx, qy, qz, qw = yaw_to_quaternion(self.theta)
        transform = TransformStamped()
        transform.header.stamp = stamp.to_msg()
        transform.header.frame_id = ODOM_FRAME
        transform.child_frame_id = BASE_FRAME
        transform.transform.translation.x = self.x
        transform.transform.translation.y = self.y
        transform.transform.rotation.x = qx
        transform.transform.rotation.y = qy
        transform.transform.rotation.z = qz
        transform.transform.rotation.w = qw
        self.tf_broadcaster.sendTransform(transform)

    def publish_joint_states(self, stamp):
        joint_state = JointState()
        joint_state.header.stamp = stamp.to_msg()
        joint_state.name = ["wheel_fl_joint", "wheel_fr_joint", "wheel_rl_joint", "wheel_rr_joint"]
        joint_state.position = [
            self.left_wheel_angle, self.right_wheel_angle,
            self.left_wheel_angle, self.right_wheel_angle,
        ]
        self.joint_pub.publish(joint_state)

    def publish_static_transforms(self):
        map_to_odom = TransformStamped()
        map_to_odom.header.stamp = self.get_clock().now().to_msg()
        map_to_odom.header.frame_id = MAP_FRAME
        map_to_odom.child_frame_id = ODOM_FRAME
        map_to_odom.transform.rotation.w = 1.0
        self.static_tf_broadcaster.sendTransform([map_to_odom])

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
        battery = BatteryState()
        battery.header.stamp = self.get_clock().now().to_msg()
        battery.voltage = 11.5 + 1.2 * (self.battery_percent / 100.0)
        battery.percentage = self.battery_percent / 100.0
        battery.power_supply_status = BatteryState.POWER_SUPPLY_STATUS_DISCHARGING
        battery.present = True
        self.battery_pub.publish(battery)


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
