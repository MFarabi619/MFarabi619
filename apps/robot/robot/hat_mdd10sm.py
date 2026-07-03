import rclpy
import rgpio
from geometry_msgs.msg import Twist
from rclpy.node import Node
from sensor_msgs.msg import JointState

from robot.hat_mdd10sm_parameters import hat_mdd10sm
from robot.kinematics import WHEEL_JOINT_NAMES, wheel_angular_velocities


def clamp_duty_percent(value):
    return max(0.0, min(100.0, value))


class HatMDD10SM(Node):
    def __init__(self):
        super().__init__("hat_mdd10sm")
        self.param_listener = hat_mdd10sm.ParamListener(self)
        self.params = self.param_listener.get_params()

        self.sbc = rgpio.sbc(self.params.rgpiod_host, self.params.rgpiod_port)
        if not self.sbc.connected:
            raise RuntimeError(
                f"could not reach rgpiod at {self.params.rgpiod_host}:{self.params.rgpiod_port}"
            )
        self.gpio_chip_handle = self.sbc.gpiochip_open(self.params.gpio_chip)
        for pin in (
            self.params.left_pwm_pin,
            self.params.right_pwm_pin,
            self.params.left_dir_pin,
            self.params.right_dir_pin,
        ):
            self.sbc.gpio_claim_output(self.gpio_chip_handle, pin, 0)
        self.halt_motors()

        self.create_subscription(Twist, "cmd_vel", self.on_cmd_vel, 10)
        self.linear = 0.0
        self.angular = 0.0
        self.left_wheel_angle = 0.0
        self.right_wheel_angle = 0.0
        self.last_update = self.get_clock().now()
        self.joint_pub = self.create_publisher(JointState, "joint_states", 10)
        self.create_timer(0.02, self.publish_joint_states)
        self.get_logger().info(
            f"ready on {self.params.rgpiod_host}:{self.params.rgpiod_port} chip {self.params.gpio_chip}, subscribed to /cmd_vel"
        )

    def drive_side(self, dir_pin, pwm_pin, forward_level, signed_speed):
        is_forward = signed_speed >= 0.0
        reverse_level = 1 - forward_level
        self.sbc.gpio_write(
            self.gpio_chip_handle, dir_pin, forward_level if is_forward else reverse_level
        )
        self.sbc.tx_pwm(
            self.gpio_chip_handle,
            pwm_pin,
            self.params.pwm_frequency_hz,
            clamp_duty_percent(abs(signed_speed) * self.params.duty_scale),
        )

    def halt_motors(self):
        self.drive_side(
            self.params.left_dir_pin,
            self.params.left_pwm_pin,
            self.params.left_forward_level,
            0.0,
        )
        self.drive_side(
            self.params.right_dir_pin,
            self.params.right_pwm_pin,
            self.params.right_forward_level,
            0.0,
        )

    def on_cmd_vel(self, msg):
        if self.param_listener.is_old(self.params):
            self.param_listener.refresh_dynamic_parameters()
            self.params = self.param_listener.get_params()

        linear = msg.linear.x
        angular = msg.angular.z
        self.linear = linear
        self.angular = angular
        left = linear - angular
        right = linear + angular
        self.drive_side(
            self.params.left_dir_pin,
            self.params.left_pwm_pin,
            self.params.left_forward_level,
            left,
        )
        self.drive_side(
            self.params.right_dir_pin,
            self.params.right_pwm_pin,
            self.params.right_forward_level,
            right,
        )
        self.get_logger().info(
            f"cmd_vel linear={linear:+.2f} angular={angular:+.2f} "
            f"→ left={clamp_duty_percent(abs(left) * self.params.duty_scale):.0f}% "
            f"right={clamp_duty_percent(abs(right) * self.params.duty_scale):.0f}%"
        )

    def publish_joint_states(self):
        now = self.get_clock().now()
        dt = (now - self.last_update).nanoseconds / 1e9
        self.last_update = now
        if dt <= 0.0:
            return
        left_speed, right_speed = wheel_angular_velocities(self.linear, self.angular)
        self.left_wheel_angle += left_speed * dt
        self.right_wheel_angle += right_speed * dt
        joint_state = JointState()
        joint_state.header.stamp = now.to_msg()
        joint_state.name = WHEEL_JOINT_NAMES
        joint_state.position = [
            self.left_wheel_angle,
            self.right_wheel_angle,
            self.left_wheel_angle,
            self.right_wheel_angle,
        ]
        self.joint_pub.publish(joint_state)

    def shutdown(self):
        self.halt_motors()
        self.sbc.gpiochip_close(self.gpio_chip_handle)
        self.sbc.stop()


def main():
    rclpy.init()
    node = HatMDD10SM()
    try:
        rclpy.spin(node)
    finally:
        node.shutdown()
        node.destroy_node()
        rclpy.shutdown()
