# Copyright 2026 Mumtahin Farabi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.


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

MEDIUM_REPORT_INTERVAL_US = 100_000
SLOW_REPORT_INTERVAL_US = 1_000_000


class AdafruitBno085:
    def __init__(self, i2c_bus, i2c_address, fast_interval_us):
        self.fast_interval_us = fast_interval_us
        self.device = BNO08X_I2C(ExtendedI2C(i2c_bus), address=i2c_address)
        self.configure_features()

    def configure_features(self):
        for feature in (BNO_REPORT_ACCELEROMETER, BNO_REPORT_GYROSCOPE,
                        BNO_REPORT_ROTATION_VECTOR):
            self.device.enable_feature(feature, self.fast_interval_us)
        for feature in (BNO_REPORT_MAGNETOMETER, BNO_REPORT_LINEAR_ACCELERATION):
            self.device.enable_feature(feature, MEDIUM_REPORT_INTERVAL_US)
        for feature in (BNO_REPORT_STABILITY_CLASSIFIER, BNO_REPORT_ACTIVITY_CLASSIFIER,
                        BNO_REPORT_STEP_COUNTER, BNO_REPORT_SHAKE_DETECTOR):
            self.device.enable_feature(feature, SLOW_REPORT_INTERVAL_US)

    def soft_reset(self):
        self.device.soft_reset()
        self.configure_features()

    @property
    def quaternion(self):
        return self.device.quaternion

    @property
    def gyro(self):
        return self.device.gyro

    @property
    def acceleration(self):
        return self.device.acceleration

    @property
    def magnetic(self):
        return self.device.magnetic

    @property
    def linear_acceleration(self):
        return self.device.linear_acceleration

    @property
    def stability_classification(self):
        return self.device.stability_classification

    @property
    def activity_classification(self):
        return self.device.activity_classification

    @property
    def steps(self):
        return self.device.steps

    @property
    def shake(self):
        return self.device.shake

    @property
    def calibration_status(self):
        return self.device.calibration_status
