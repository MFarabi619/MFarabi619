import lgpio
import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node

GPIO_CHIP = 0
AN1, AN2 = 12, 13
DIG1, DIG2 = 26, 24
FREQ = 1000
TURN_THRESHOLD = 0.05


def clamp(value, lo=0.0, hi=100.0):
    return max(lo, min(hi, value))


class HatMDD10SM(Node):
    def __init__(self):
        super().__init__("hat_mdd10sm")
        self.chip = lgpio.gpiochip_open(GPIO_CHIP)
        for pin in (AN1, AN2, DIG1, DIG2):
            lgpio.gpio_claim_output(self.chip, pin, 0)
        self.set_dir("forward")
        self.duty = 0.0
        self.apply_pwm()
        self.create_subscription(Twist, "cmd_vel", self.on_cmd_vel, 10)
        self.get_logger().info(f"ready on chip {GPIO_CHIP}, subscribed to /cmd_vel")

    def set_dir(self, direction):
        if direction == "forward":
            lgpio.gpio_write(self.chip, DIG1, 1)
            lgpio.gpio_write(self.chip, DIG2, 0)
        elif direction == "backward":
            lgpio.gpio_write(self.chip, DIG1, 0)
            lgpio.gpio_write(self.chip, DIG2, 1)
        elif direction == "left":
            lgpio.gpio_write(self.chip, DIG1, 0)
            lgpio.gpio_write(self.chip, DIG2, 0)
        elif direction == "right":
            lgpio.gpio_write(self.chip, DIG1, 1)
            lgpio.gpio_write(self.chip, DIG2, 1)

    def apply_pwm(self):
        lgpio.tx_pwm(self.chip, AN1, FREQ, self.duty)
        lgpio.tx_pwm(self.chip, AN2, FREQ, self.duty)

    def on_cmd_vel(self, msg):
        linear = msg.linear.x
        angular = msg.angular.z

        if abs(angular) > TURN_THRESHOLD:
            self.set_dir("left" if angular > 0 else "right")
            self.duty = clamp(abs(angular) * 100.0)
        elif linear >= 0:
            self.set_dir("forward")
            self.duty = clamp(linear * 100.0)
        else:
            self.set_dir("backward")
            self.duty = clamp(abs(linear) * 100.0)

        self.apply_pwm()
        self.get_logger().info(
            f"cmd_vel linear={linear:+.2f} angular={angular:+.2f} → duty={self.duty:.0f}%"
        )

    def shutdown(self):
        self.duty = 0.0
        self.apply_pwm()
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
