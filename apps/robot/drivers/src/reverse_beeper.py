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


import array
import math

from audio_common_msgs.msg import AudioStamped
from geometry_msgs.msg import TwistStamped
import rclpy
from rclpy.duration import Duration
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data

SAMPLE_RATE_HZ = 16000
TONE_HZ = 1000.0
TONE_SECONDS = 0.6
BEEP_PERIOD_SECONDS = 1.0
TICK_SECONDS = 0.05
COMMAND_TIMEOUT_SECONDS = 0.5
REVERSING_THRESHOLD_MPS = -0.01
TONE_AMPLITUDE = 0.6
PORTAUDIO_FLOAT32 = 1


def period_samples():
    tone_sample_count = int(SAMPLE_RATE_HZ * TONE_SECONDS)
    period_sample_count = int(SAMPLE_RATE_HZ * BEEP_PERIOD_SECONDS)
    samples = array.array('f', (
        TONE_AMPLITUDE * math.sin(math.tau * TONE_HZ * index / SAMPLE_RATE_HZ)
        for index in range(tone_sample_count)))
    samples.extend([0.0] * (period_sample_count - tone_sample_count))
    return samples


class ReverseBeeper(Node):
    def __init__(self):
        super().__init__('reverse_beeper')
        cmd_vel_topic = self.declare_parameter(
            'cmd_vel_topic', 'platform/cmd_vel').value
        audio_topic = self.declare_parameter('audio_topic', 'audio').value

        self.samples = period_samples()
        self.is_reversing = False
        self.last_command_time = self.get_clock().now()
        self.beep_start_time = self.get_clock().now()
        self.published_period_count = 0

        self.audio_publisher = self.create_publisher(
            AudioStamped, audio_topic, qos_profile_sensor_data)
        self.create_subscription(
            TwistStamped, cmd_vel_topic, self.on_cmd_vel,
            qos_profile_sensor_data)
        self.create_timer(TICK_SECONDS, self.publish_beep)

    def on_cmd_vel(self, message):
        now = self.get_clock().now()
        self.last_command_time = now
        was_reversing = self.is_reversing
        self.is_reversing = message.twist.linear.x < REVERSING_THRESHOLD_MPS
        if self.is_reversing and not was_reversing:
            self.beep_start_time = now
            self.published_period_count = 0
            self.publish_beep()

    def publish_beep(self):
        now = self.get_clock().now()
        if not self.is_reversing:
            return
        if now - self.last_command_time > Duration(
                seconds=COMMAND_TIMEOUT_SECONDS):
            return
        elapsed_seconds = (now - self.beep_start_time).nanoseconds * 1e-9
        due_period_count = int(elapsed_seconds / BEEP_PERIOD_SECONDS) + 1
        if self.published_period_count >= due_period_count:
            return
        self.published_period_count += 1
        self.audio_publisher.publish(self.beep_message())

    def beep_message(self):
        message = AudioStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.audio.info.format = PORTAUDIO_FLOAT32
        message.audio.info.channels = 1
        message.audio.info.rate = SAMPLE_RATE_HZ
        message.audio.info.chunk = len(self.samples)
        message.audio.audio_data.float32_data = self.samples
        return message


def main():
    rclpy.init()
    node = ReverseBeeper()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
