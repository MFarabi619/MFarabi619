import lgpio
import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node

from robot.hat_mdd10sm_parameters import hat_mdd10sm


def clamp(value, low=0.0, high=100.0):
    return max(low, min(high, value))


class HatMDD10SM(Node):
    def __init__(self):
        super().__init__("hat_mdd10sm")
        self.param_listener = hat_mdd10sm.ParamListener(self)
        self.params = self.param_listener.get_params()

        self.chip = lgpio.gpiochip_open(self.params.gpio_chip)
        for pin in (
            self.params.left_pwm_pin,
            self.params.right_pwm_pin,
            self.params.left_dir_pin,
            self.params.right_dir_pin,
        ):
            lgpio.gpio_claim_output(self.chip, pin, 0)
        self.stop()

        self.create_subscription(Twist, "cmd_vel", self.on_cmd_vel, 10)
        self.get_logger().info(
            f"ready on chip {self.params.gpio_chip}, subscribed to /cmd_vel"
        )

    def drive_side(self, dir_pin, pwm_pin, forward_level, signed_speed):
        is_forward = signed_speed >= 0.0
        lgpio.gpio_write(
            self.chip, dir_pin, forward_level if is_forward else 1 - forward_level
        )
        lgpio.tx_pwm(
            self.chip,
            pwm_pin,
            self.params.pwm_frequency_hz,
            clamp(abs(signed_speed) * self.params.duty_scale),
        )

    def stop(self):
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
            f"→ left={clamp(abs(left) * self.params.duty_scale):.0f}% "
            f"right={clamp(abs(right) * self.params.duty_scale):.0f}%"
        )

    def shutdown(self):
        self.stop()
        lgpio.gpiochip_close(self.chip)


def main():
    rclpy.init()
    node = HatMDD10SM()
    try:
        rclpy.spin(node)
    finally:
        node.shutdown()
        node.destroy_node()
        rclpy.shutdown()
