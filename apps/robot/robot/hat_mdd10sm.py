import lgpio
import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node

GPIO_CHIP = 0
AN1, AN2 = 12, 13
DIG1, DIG2 = 26, 24
PWM_FREQUENCY_HZ = 1000
LEFT_FORWARD_LEVEL = 1
RIGHT_FORWARD_LEVEL = 0


def clamp(value, low=0.0, high=100.0):
    return max(low, min(high, value))


class HatMDD10SM(Node):
    def __init__(self):
        super().__init__("hat_mdd10sm")
        self.chip = lgpio.gpiochip_open(GPIO_CHIP)
        for pin in (AN1, AN2, DIG1, DIG2):
            lgpio.gpio_claim_output(self.chip, pin, 0)
        self.stop()

        self.create_subscription(Twist, "cmd_vel", self.on_cmd_vel, 10)
        self.get_logger().info(f"ready on chip {GPIO_CHIP}, subscribed to /cmd_vel")

    def drive_side(self, dig_pin, an_pin, forward_level, signed_speed):
        is_forward = signed_speed >= 0.0
        lgpio.gpio_write(
            self.chip, dig_pin, forward_level if is_forward else 1 - forward_level
        )
        lgpio.tx_pwm(
            self.chip, an_pin, PWM_FREQUENCY_HZ, clamp(abs(signed_speed) * 50.0)
        )

    def stop(self):
        self.drive_side(DIG1, AN1, LEFT_FORWARD_LEVEL, 0.0)
        self.drive_side(DIG2, AN2, RIGHT_FORWARD_LEVEL, 0.0)

    def on_cmd_vel(self, msg):
        linear = msg.linear.x
        angular = msg.angular.z
        left = linear - angular
        right = linear + angular
        self.drive_side(DIG1, AN1, LEFT_FORWARD_LEVEL, left)
        self.drive_side(DIG2, AN2, RIGHT_FORWARD_LEVEL, right)
        self.get_logger().info(
            f"cmd_vel linear={linear:+.2f} angular={angular:+.2f} "
            f"→ left={clamp(abs(left) * 100.0):.0f}% right={clamp(abs(right) * 100.0):.0f}%"
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
