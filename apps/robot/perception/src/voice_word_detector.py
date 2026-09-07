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


import os

from audio_common_msgs.msg import AudioStamped
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
import sherpa_onnx
from std_msgs.msg import String
from std_srvs.srv import SetBool

INT16_FULL_SCALE = 32768.0
SILENT_CHUNKS_BEFORE_RESET = 16


class AutomaticGainControl:
    def __init__(self, target_level, max_gain, noise_gate=0.015,
                 rise=0.4, fall=0.15):
        self.target_level = target_level
        self.max_gain = max_gain
        self.noise_gate = noise_gate
        self.rise = rise
        self.fall = fall
        self.speech_level = noise_gate
        self.chunk_is_voiced = False

    def leveled(self, samples):
        if not len(samples):
            return samples
        level = float(np.sqrt(np.mean(np.square(samples))))
        self.chunk_is_voiced = level >= self.noise_gate
        if self.chunk_is_voiced:
            rate = self.rise if level > self.speech_level else self.fall
            self.speech_level += rate * (level - self.speech_level)
        gain = max(1.0, min(self.max_gain,
                            self.target_level / self.speech_level))
        return samples * gain


def default_model_directory(bundle_name):
    directory = os.path.dirname(__file__)
    installed_directory = os.path.join(directory, 'models', bundle_name)
    if os.path.isdir(installed_directory):
        return installed_directory
    return os.path.normpath(
        os.path.join(directory, '..', 'models', bundle_name))


def normalized_samples(message):
    return (np.array(message.audio.audio_data.int16_data, dtype=np.float32)
            / INT16_FULL_SCALE)


class StreamingKeywordSpotter:
    def __init__(self, model_directory, keyword_boost, keyword_threshold):
        def model_file(name):
            return os.path.join(model_directory, name)
        self.spotter = sherpa_onnx.KeywordSpotter(
            tokens=model_file('tokens.txt'),
            encoder=model_file('encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx'),
            decoder=model_file('decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx'),
            joiner=model_file('joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx'),
            keywords_file=model_file('keywords.txt'),
            keywords_score=keyword_boost,
            keywords_threshold=keyword_threshold,
            num_threads=1)
        self.stream = self.spotter.create_stream()

    def accept_waveform(self, rate, samples):
        self.stream.accept_waveform(rate, samples)

    def is_ready(self):
        return self.spotter.is_ready(self.stream)

    def decode(self):
        self.spotter.decode_stream(self.stream)

    def result(self):
        return self.spotter.get_result(self.stream)

    def reset(self):
        self.spotter.reset_stream(self.stream)


class VoiceWordDetector(Node):
    def __init__(self, **node_arguments):
        super().__init__('voice_word_detector', **node_arguments)
        audio_topic = self.declare_parameter(
            'audio_topic', 'microphone/audio').value
        word_topic = self.declare_parameter(
            'word_topic', 'perception/voice/word').value
        model_directory = self.declare_parameter(
            'model_directory',
            default_model_directory('voice_word_detector')).value
        keyword_boost = self.declare_parameter('keyword_boost', 1.5).value
        keyword_threshold = self.declare_parameter(
            'keyword_threshold', 0.2).value
        gain_target_level = self.declare_parameter(
            'gain_target_level', 0.1).value
        max_gain = self.declare_parameter('max_gain', 20.0).value
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        self.gain_control = AutomaticGainControl(gain_target_level, max_gain)
        self.silent_chunk_count = 0
        self.spotter = StreamingKeywordSpotter(
            model_directory, keyword_boost, keyword_threshold)
        self.word_publisher = self.create_publisher(String, word_topic, 10)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.create_subscription(
            AudioStamped, audio_topic, self.on_audio, qos_profile_sensor_data)
        self.get_logger().info(
            f'voice word detector: {audio_topic} -> {word_topic}')

    def on_enable(self, request, response):
        self.is_enabled = request.data
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_audio(self, message):
        if not self.is_enabled:
            return
        self.spotter.accept_waveform(
            message.audio.info.rate,
            self.gain_control.leveled(normalized_samples(message)))
        if self.gain_control.chunk_is_voiced:
            self.silent_chunk_count = 0
        else:
            self.silent_chunk_count += 1
            if self.silent_chunk_count == SILENT_CHUNKS_BEFORE_RESET:
                self.spotter.reset()
        while self.spotter.is_ready():
            self.spotter.decode()
            keyword = self.spotter.result()
            if not keyword:
                continue
            self.spotter.reset()
            word = keyword.lower()
            self.word_publisher.publish(String(data=word))
            self.get_logger().info(f'heard {word!r}')


def main():
    rclpy.init()
    node = VoiceWordDetector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
