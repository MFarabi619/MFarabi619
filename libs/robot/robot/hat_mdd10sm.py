import RPi.GPIO as GPIO
import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node

AN1, AN2 = 12, 13
DIG1, DIG2 = 26, 24
FREQ = 1000
TURN_THRESHOLD = 0.05


def set_dir(direction):
    if direction == "forward":
        GPIO.output(DIG1, GPIO.HIGH)
        GPIO.output(DIG2, GPIO.LOW)
    elif direction == "backward":
        GPIO.output(DIG1, GPIO.LOW)
        GPIO.output(DIG2, GPIO.HIGH)
    elif direction == "left":
        GPIO.output(DIG1, GPIO.LOW)
        GPIO.output(DIG2, GPIO.LOW)
    elif direction == "right":
        GPIO.output(DIG1, GPIO.HIGH)
        GPIO.output(DIG2, GPIO.HIGH)


def clamp(value, lo=0.0, hi=100.0):
    return max(lo, min(hi, value))


class HatMDD10SM(Node):
    def __init__(self):
        super().__init__("hat_mdd10sm")
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        for pin in (AN1, AN2, DIG1, DIG2):
            GPIO.setup(pin, GPIO.OUT)
        self.pwm1 = GPIO.PWM(AN1, FREQ)
        self.pwm2 = GPIO.PWM(AN2, FREQ)
        self.pwm1.start(0)
        self.pwm2.start(0)
        set_dir("forward")
        self.create_subscription(Twist, "cmd_vel", self.on_cmd_vel, 10)

    def on_cmd_vel(self, msg):
        linear = msg.linear.x
        angular = msg.angular.z

        if abs(angular) > TURN_THRESHOLD:
            set_dir("left" if angular > 0 else "right")
            duty = clamp(abs(angular) * 100.0)
        elif linear >= 0:
            set_dir("forward")
            duty = clamp(linear * 100.0)
        else:
            set_dir("backward")
            duty = clamp(abs(linear) * 100.0)

        self.pwm1.ChangeDutyCycle(duty)
        self.pwm2.ChangeDutyCycle(duty)

    def shutdown(self):
        self.pwm1.ChangeDutyCycle(0)
        self.pwm2.ChangeDutyCycle(0)
        self.pwm1.stop()
        self.pwm2.stop()
        GPIO.cleanup()


def main():
    rclpy.init()
    node = HatMDD10SM()
    try:
        rclpy.spin(node)
    finally:
        node.shutdown()
        node.destroy_node()
        rclpy.shutdown()
