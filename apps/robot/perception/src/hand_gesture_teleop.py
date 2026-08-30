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
from std_srvs.srv import SetBool
from vision_msgs.msg import Detection2DArray

GESTURE_DIRECTIONS = {
    'Open_Palm': (0.0, 0.0),
    'Closed_Fist': (0.0, 0.0),
    'Thumb_Up': (1.0, 0.0),
    'Thumb_Down': (-1.0, 0.0),
    'Victory': (0.0, 1.0),
    'Pointing_Up': (0.0, -1.0),
}

STOP = (0.0, 0.0)


class HandGestureTeleop(Node):
    def __init__(self):
        super().__init__('hand_gesture_teleop')
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.linear_speed = self.declare_parameter('linear_speed', 1.0).value
        self.angular_speed = self.declare_parameter('angular_speed', 1.0).value
        self.confidence_threshold = self.declare_parameter(
            'confidence_threshold', 0.6).value
        self.commit_frames = self.declare_parameter('commit_frames', 3).value
        watchdog_timeout_seconds = self.declare_parameter(
            'watchdog_timeout_seconds', 0.5).value

        self.is_enabled = self.declare_parameter('start_enabled', False).value
        self.candidate = None
        self.candidate_count = 0
        self.committed = STOP

        self.create_service(SetBool, '~/enable', self.on_enable)
        self.cmd_vel_publisher = self.create_publisher(
            TwistStamped, '/joy_teleop/cmd_vel', qos_profile_sensor_data)
        self.create_subscription(
            Detection2DArray, 'perception/gestures', self.on_gestures,
            qos_profile_sensor_data)
        self.watchdog = self.create_timer(
            watchdog_timeout_seconds, self.on_watchdog)

    def on_enable(self, request, response):
        self.is_enabled = request.data
        if not request.data and self.committed != STOP:
            self.committed = STOP
            self.publish_twist(self.committed)
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_gestures(self, message):
        if not self.is_enabled:
            return
        self.watchdog.reset()
        gesture = self.confident_gesture(message)
        if gesture is None:
            self.candidate = None
            self.candidate_count = 0
            self.committed = STOP
            self.publish_twist(self.committed)
            return
        if gesture == self.candidate:
            self.candidate_count += 1
        else:
            self.candidate = gesture
            self.candidate_count = 1
        if self.candidate_count >= self.commit_frames:
            linear, angular = GESTURE_DIRECTIONS[gesture]
            self.committed = (linear * self.linear_speed, angular * self.angular_speed)
        self.publish_twist(self.committed)

    def confident_gesture(self, message):
        best_gesture = None
        best_score = self.confidence_threshold
        for detection in message.detections:
            hypothesis = detection.results[0].hypothesis
            if hypothesis.score < best_score:
                continue
            if hypothesis.class_id not in GESTURE_DIRECTIONS:
                continue
            best_score = hypothesis.score
            best_gesture = hypothesis.class_id
        return best_gesture

    def on_watchdog(self):
        if self.committed == STOP:
            return
        self.committed = STOP
        self.publish_twist(self.committed)

    def publish_twist(self, velocity):
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x, message.twist.angular.z = velocity
        self.cmd_vel_publisher.publish(message)


def main():
    rclpy.init()
    node = HandGestureTeleop()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
