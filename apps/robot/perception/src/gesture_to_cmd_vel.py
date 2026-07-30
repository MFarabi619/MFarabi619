#!/usr/bin/env python3

# Copyright 2026 Mumtahin Farabi
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


from geometry_msgs.msg import TwistStamped
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from vision_msgs.msg import Detection2DArray

GESTURE_VELOCITIES = {
    'Open_Palm': (0.0, 0.0),
    'Closed_Fist': (0.0, 0.0),
    'Thumb_Up': (1.0, 0.0),
    'Thumb_Down': (-1.0, 0.0),
    'Victory': (0.0, 1.0),
    'Pointing_Up': (0.0, -1.0),
}

STOP = (0.0, 0.0)


class GestureToCmdVel(Node):
    def __init__(self):
        super().__init__('gesture_to_cmd_vel')
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.linear_speed = self.declare_parameter('linear_speed', 1.0).value
        self.angular_speed = self.declare_parameter('angular_speed', 1.0).value
        self.confidence_threshold = self.declare_parameter(
            'confidence_threshold', 0.6).value
        self.commit_frames = self.declare_parameter('commit_frames', 3).value
        watchdog_timeout = self.declare_parameter('watchdog_timeout', 0.5).value

        self.candidate = None
        self.candidate_count = 0
        self.committed = STOP

        self.publisher = self.create_publisher(
            TwistStamped, '/joy_teleop/cmd_vel', qos_profile_sensor_data)
        self.create_subscription(
            Detection2DArray, 'perception/gestures', self.on_gestures,
            qos_profile_sensor_data)
        self.watchdog = self.create_timer(watchdog_timeout, self.on_watchdog)

    def on_gestures(self, message):
        self.watchdog.reset()
        gesture = self.confident_gesture(message)
        if gesture is None:
            self.candidate = None
            self.candidate_count = 0
            self.committed = STOP
            self.publish(self.committed)
            return
        if gesture == self.candidate:
            self.candidate_count += 1
        else:
            self.candidate = gesture
            self.candidate_count = 1
        if self.candidate_count >= self.commit_frames and gesture in GESTURE_VELOCITIES:
            linear, angular = GESTURE_VELOCITIES[gesture]
            self.committed = (linear * self.linear_speed, angular * self.angular_speed)
        self.publish(self.committed)

    def confident_gesture(self, message):
        if not message.detections:
            return None
        hypothesis = message.detections[0].results[0].hypothesis
        if hypothesis.score < self.confidence_threshold:
            return None
        return hypothesis.class_id

    def on_watchdog(self):
        self.committed = STOP
        self.publish(self.committed)

    def publish(self, velocity):
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x, message.twist.angular.z = velocity
        self.publisher.publish(message)


def main():
    rclpy.init()
    rclpy.spin(GestureToCmdVel())


if __name__ == '__main__':
    main()
