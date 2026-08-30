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


from typing import NamedTuple

from geometry_msgs.msg import TwistStamped
import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.parameter import Parameter
from rclpy.qos import qos_profile_sensor_data
from std_msgs.msg import String
from std_srvs.srv import SetBool

PUBLISH_PERIOD_SECONDS = 0.1
COMPOSITION_WINDOW_SECONDS = 1.5
LONGITUDINAL_WORDS = {
    'forward': 1.0, 'straight': 1.0, 'backward': -1.0, 'back': -1.0,
}
ACKNOWLEDGEMENTS = ('acknowledged', 'yes', 'sure', 'of course')
STEER_WORDS = {'left': 1.0, 'right': -1.0}
PIVOT_WORDS = {'clockwise': -1.0, 'counterclockwise': 1.0}
DIGIT_WORDS = {
    'zero': 0.0, 'one': 1.0, 'two': 2.0,
    'three': 3.0, 'four': 4.0, 'five': 5.0,
}
SPEED_PARAMETER_WORDS = {
    'linear': 'forward_speed_mps',
    'angular': 'angular_speed_radps',
}
LIVE_PARAMETERS = frozenset(SPEED_PARAMETER_WORDS.values())


class Motion(NamedTuple):
    longitudinal: float
    steer: float
    pivot: float

STOP = Motion(0.0, 0.0, 0.0)


class VoiceTeleop(Node):
    def __init__(self):
        super().__init__('voice_teleop')
        word_topic = self.declare_parameter(
            'word_topic', 'perception/voice/word').value
        self.frame_id = self.declare_parameter('frame_id', 'base_link').value
        self.forward_speed_mps = self.declare_parameter(
            'forward_speed_mps', 0.3).value
        self.angular_speed_radps = self.declare_parameter(
            'angular_speed_radps', 0.5).value
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        self.motion = STOP
        self.pending_speed_parameter = None
        self.acknowledgement_count = 0
        self.latest_word_time = self.get_clock().now() - Duration(
            seconds=COMPOSITION_WINDOW_SECONDS * 2.0)

        speech_topic = self.declare_parameter(
            'speech_topic', 'perception/voice/speech').value
        self.cmd_vel_publisher = self.create_publisher(
            TwistStamped, '/joy_teleop/cmd_vel', qos_profile_sensor_data)
        self.speech_publisher = self.create_publisher(
            String, speech_topic, 10)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_subscription(String, word_topic, self.on_word, 10)
        self.create_timer(PUBLISH_PERIOD_SECONDS, self.publish_held_twist)

    def on_enable(self, request, response):
        self.is_enabled = request.data
        if not request.data and self.motion != STOP:
            self.motion = STOP
            self.publish_twist()
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)

    def on_word(self, message):
        if not self.is_enabled:
            return
        word = message.data
        now = self.get_clock().now()
        is_composing = (
            now - self.latest_word_time
            <= Duration(seconds=COMPOSITION_WINDOW_SECONDS))
        self.latest_word_time = now

        if word in DIGIT_WORDS:
            if is_composing and self.pending_speed_parameter:
                self.set_parameters([Parameter(
                    self.pending_speed_parameter, value=DIGIT_WORDS[word])])
                self.get_logger().info(
                    f'{self.pending_speed_parameter} = {DIGIT_WORDS[word]}')
                self.pending_speed_parameter = None
                if self.motion != STOP:
                    self.publish_twist()
                self.acknowledge()
            return
        self.pending_speed_parameter = None

        if word in SPEED_PARAMETER_WORDS:
            self.pending_speed_parameter = SPEED_PARAMETER_WORDS[word]
            self.acknowledge()
            return
        if word == 'stop':
            self.motion = STOP
            self.publish_twist()
            self.acknowledge()
            return
        if word in PIVOT_WORDS:
            self.motion = Motion(0.0, 0.0, PIVOT_WORDS[word])
        elif word in LONGITUDINAL_WORDS:
            steer = self.motion.steer if is_composing else 0.0
            self.motion = Motion(LONGITUDINAL_WORDS[word], steer, 0.0)
        elif word in STEER_WORDS:
            was_moving = is_composing and self.motion.longitudinal != 0.0
            longitudinal = self.motion.longitudinal if was_moving else 1.0
            self.motion = Motion(longitudinal, STEER_WORDS[word], 0.0)
        else:
            return
        self.publish_twist()
        self.acknowledge()

    def acknowledge(self):
        acknowledgement = ACKNOWLEDGEMENTS[
            self.acknowledgement_count % len(ACKNOWLEDGEMENTS)]
        self.acknowledgement_count += 1
        self.speech_publisher.publish(String(data=acknowledgement))

    def publish_held_twist(self):
        if self.is_enabled and self.motion != STOP:
            self.publish_twist()

    def publish_twist(self):
        message = TwistStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        message.twist.linear.x = self.motion.longitudinal * self.forward_speed_mps
        message.twist.angular.z = (
            self.motion.pivot * self.angular_speed_radps
            + self.motion.longitudinal * self.motion.steer
            * self.angular_speed_radps)
        self.cmd_vel_publisher.publish(message)


def main():
    rclpy.init()
    node = VoiceTeleop()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
