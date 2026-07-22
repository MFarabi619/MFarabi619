#!/usr/bin/env python3

import rclpy
from adafruit_bno08x import (
    BNO_REPORT_ACCELEROMETER,
    BNO_REPORT_ACTIVITY_CLASSIFIER,
    BNO_REPORT_GYROSCOPE,
    BNO_REPORT_LINEAR_ACCELERATION,
    BNO_REPORT_MAGNETOMETER,
    BNO_REPORT_ROTATION_VECTOR,
    BNO_REPORT_SHAKE_DETECTOR,
    BNO_REPORT_STABILITY_CLASSIFIER,
    BNO_REPORT_STEP_COUNTER,
)
from adafruit_bno08x.i2c import BNO08X_I2C
from adafruit_extended_bus import ExtendedI2C
from geometry_msgs.msg import Vector3Stamped
from rclpy.node import Node
from sensor_msgs.msg import Imu, MagneticField
from std_msgs.msg import Bool, Header, String, UInt8, UInt32


MEDIUM_REPORT_INTERVAL_US = 100_000
SLOW_REPORT_INTERVAL_US = 1_000_000
MICROTESLA_TO_TESLA = 1e-6


class ImuDriver(Node):
    def __init__(self):
        super().__init__('imu_driver')
        self.declare_parameter('i2c_bus', 1)
        self.declare_parameter('i2c_address', 0x4A)
        self.declare_parameter('frame_id', 'imu_0_link')
        self.declare_parameter('rate_hz', 25.0)
        bus = ExtendedI2C(self.get_parameter('i2c_bus').value)
        self.bno085 = BNO08X_I2C(bus, address=self.get_parameter('i2c_address').value)
        rate_hz = self.get_parameter('rate_hz').value
        self.fast_interval_us = int(1_000_000 / rate_hz)
        self.configure_features()
        self.consecutive_failures = 0
        self.frame_id = self.get_parameter('frame_id').value
        self.imu_publisher = self.create_publisher(Imu, 'data', 10)
        self.mag_publisher = self.create_publisher(MagneticField, 'mag', 10)
        self.linear_acceleration_publisher = self.create_publisher(
            Vector3Stamped, 'linear_acceleration', 10)
        self.stability_publisher = self.create_publisher(String, 'stability', 10)
        self.activity_publisher = self.create_publisher(String, 'activity', 10)
        self.steps_publisher = self.create_publisher(UInt32, 'steps', 10)
        self.shake_publisher = self.create_publisher(Bool, 'shake', 10)
        self.calibration_status_publisher = self.create_publisher(
            UInt8, 'calibration_status', 10)
        self.create_timer(30.0, self.publish_calibration_status)
        self.create_timer(1.0 / rate_hz, self.publish_fast)
        self.create_timer(0.1, self.publish_medium)
        self.create_timer(1.0, self.publish_slow)

    def configure_features(self):
        for feature in (BNO_REPORT_ACCELEROMETER, BNO_REPORT_GYROSCOPE,
                        BNO_REPORT_ROTATION_VECTOR):
            self.bno085.enable_feature(feature, self.fast_interval_us)
        for feature in (BNO_REPORT_MAGNETOMETER, BNO_REPORT_LINEAR_ACCELERATION):
            self.bno085.enable_feature(feature, MEDIUM_REPORT_INTERVAL_US)
        for feature in (BNO_REPORT_STABILITY_CLASSIFIER, BNO_REPORT_ACTIVITY_CLASSIFIER,
                        BNO_REPORT_STEP_COUNTER, BNO_REPORT_SHAKE_DETECTOR):
            self.bno085.enable_feature(feature, SLOW_REPORT_INTERVAL_US)

    def recover(self):
        self.get_logger().warning('too many failed samples, soft-resetting the BNO085')
        try:
            self.bno085.soft_reset()
            self.configure_features()
        except (OSError, RuntimeError, KeyError) as error:
            self.get_logger().error(f'soft reset failed: {error}')
        self.consecutive_failures = 0

    def publish_calibration_status(self):
        try:
            status = self.bno085.calibration_status
        except (OSError, RuntimeError, KeyError):
            return
        self.calibration_status_publisher.publish(UInt8(data=status))

    def stamped_header(self):
        header = Header()
        header.stamp = self.get_clock().now().to_msg()
        header.frame_id = self.frame_id
        return header

    def publish_fast(self):
        try:
            quaternion = self.bno085.quaternion
            gyro = self.bno085.gyro
            acceleration = self.bno085.acceleration
        except (OSError, RuntimeError, KeyError) as error:
            self.get_logger().warning(
                f'fast sample failed: {error}', throttle_duration_sec=5.0)
            self.consecutive_failures += 1
            if self.consecutive_failures >= 50:
                self.recover()
            return
        self.consecutive_failures = 0
        if None in (quaternion, gyro, acceleration):
            return
        imu = Imu()
        imu.header = self.stamped_header()
        (imu.orientation.x, imu.orientation.y,
         imu.orientation.z, imu.orientation.w) = quaternion
        (imu.angular_velocity.x, imu.angular_velocity.y,
         imu.angular_velocity.z) = gyro
        (imu.linear_acceleration.x, imu.linear_acceleration.y,
         imu.linear_acceleration.z) = acceleration
        self.imu_publisher.publish(imu)

    def publish_medium(self):
        try:
            magnetic = self.bno085.magnetic
            linear = self.bno085.linear_acceleration
        except (OSError, RuntimeError, KeyError):
            return
        header = self.stamped_header()
        if magnetic is not None:
            mag = MagneticField()
            mag.header = header
            (mag.magnetic_field.x, mag.magnetic_field.y, mag.magnetic_field.z) = (
                component * MICROTESLA_TO_TESLA for component in magnetic)
            self.mag_publisher.publish(mag)
        if linear is not None:
            message = Vector3Stamped()
            message.header = header
            (message.vector.x, message.vector.y, message.vector.z) = linear
            self.linear_acceleration_publisher.publish(message)

    def publish_slow(self):
        try:
            stability = self.bno085.stability_classification
            activity = self.bno085.activity_classification
            steps = self.bno085.steps
            shake = self.bno085.shake
        except (OSError, RuntimeError, KeyError):
            return
        if stability is not None:
            self.stability_publisher.publish(String(data=stability))
        if activity is not None:
            most_likely = activity.get('most_likely', '')
            self.activity_publisher.publish(String(data=str(most_likely)))
        if steps is not None:
            self.steps_publisher.publish(UInt32(data=steps))
        if shake is not None:
            self.shake_publisher.publish(Bool(data=bool(shake)))


def main():
    rclpy.init()
    rclpy.spin(ImuDriver())


if __name__ == '__main__':
    main()
