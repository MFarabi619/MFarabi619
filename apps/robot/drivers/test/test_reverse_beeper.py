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
from rclpy.duration import Duration


def command(linear_x):
    message = TwistStamped()
    message.twist.linear.x = linear_x
    return message


def capture(node):
    beeps = []
    node.audio_publisher.publish = beeps.append
    return beeps


def rewind(node, seconds):
    node.beep_start_time -= Duration(seconds=seconds)


def test_the_first_beep_plays_the_moment_reversing_starts(reverse_beeper_node):
    beeps = capture(reverse_beeper_node)
    reverse_beeper_node.on_cmd_vel(command(-0.3))
    assert len(beeps) == 1


def test_forward_and_stopped_commands_stay_silent(reverse_beeper_node):
    beeps = capture(reverse_beeper_node)
    reverse_beeper_node.on_cmd_vel(command(0.3))
    reverse_beeper_node.publish_beep()
    reverse_beeper_node.on_cmd_vel(command(0.0))
    reverse_beeper_node.publish_beep()
    assert beeps == []


def test_each_period_publishes_exactly_one_chunk(
        reverse_beeper_node, reverse_beeper_module):
    beeps = capture(reverse_beeper_node)
    reverse_beeper_node.on_cmd_vel(command(-0.3))
    reverse_beeper_node.publish_beep()
    assert len(beeps) == 1
    rewind(reverse_beeper_node, reverse_beeper_module.BEEP_PERIOD_SECONDS)
    reverse_beeper_node.publish_beep()
    reverse_beeper_node.publish_beep()
    assert len(beeps) == 2


def test_stale_commands_stop_the_beeper(
        reverse_beeper_node, reverse_beeper_module):
    beeps = capture(reverse_beeper_node)
    reverse_beeper_node.on_cmd_vel(command(-0.3))
    beeps.clear()
    reverse_beeper_node.last_command_time -= Duration(
        seconds=reverse_beeper_module.COMMAND_TIMEOUT_SECONDS * 2.0)
    rewind(reverse_beeper_node, reverse_beeper_module.BEEP_PERIOD_SECONDS)
    reverse_beeper_node.publish_beep()
    assert beeps == []


def test_a_chunk_is_tone_followed_by_silence(
        reverse_beeper_node, reverse_beeper_module):
    beeps = capture(reverse_beeper_node)
    reverse_beeper_node.on_cmd_vel(command(-0.3))
    samples = beeps[0].audio.audio_data.float32_data
    tone_sample_count = int(
        reverse_beeper_module.SAMPLE_RATE_HZ
        * reverse_beeper_module.TONE_SECONDS)
    assert len(samples) == int(
        reverse_beeper_module.SAMPLE_RATE_HZ
        * reverse_beeper_module.BEEP_PERIOD_SECONDS)
    assert max(samples[:tone_sample_count]) > 0.1
    assert all(sample == 0.0 for sample in samples[tone_sample_count:])


def test_chunks_carry_the_declared_audio_format(
        reverse_beeper_node, reverse_beeper_module):
    beeps = capture(reverse_beeper_node)
    reverse_beeper_node.on_cmd_vel(command(-0.3))
    info = beeps[0].audio.info
    samples = beeps[0].audio.audio_data.float32_data
    assert info.format == reverse_beeper_module.PORTAUDIO_FLOAT32
    assert info.channels == 1
    assert info.rate == reverse_beeper_module.SAMPLE_RATE_HZ
    assert info.chunk == len(samples)
    assert max(samples) <= 1.0 and min(samples) >= -1.0
