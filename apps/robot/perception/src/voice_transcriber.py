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
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
import sherpa_onnx
from std_msgs.msg import String
from std_srvs.srv import SetBool

from voice_teleop import (
    DIGIT_WORDS, LONGITUDINAL_WORDS, PIVOT_WORDS, SPEED_PARAMETER_WORDS,
    STEER_WORDS)
from voice_word_detector import (
    AutomaticGainControl, default_model_directory, normalized_samples)

TELEOP_WORDS = frozenset(
    ['stop', *LONGITUDINAL_WORDS, *STEER_WORDS, *PIVOT_WORDS, *DIGIT_WORDS,
     *SPEED_PARAMETER_WORDS])
DECODE_ALIASES = {
    'to': 'two', 'too': 'two', 'for': 'four',
    'backwards': 'backward', 'forwards': 'forward',
}
FILLER_WORDS = frozenset(['a', 'and', 'oh', 'the', 'uh', 'um'])


class StreamingTranscriber:
    def __init__(self, model_directory, num_threads, trailing_silence_seconds):
        def model_file(name):
            return os.path.join(model_directory, name)
        self.recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=model_file('tokens.txt'),
            encoder=model_file('encoder-epoch-99-avg-1.int8.onnx'),
            decoder=model_file('decoder-epoch-99-avg-1.onnx'),
            joiner=model_file('joiner-epoch-99-avg-1.int8.onnx'),
            num_threads=num_threads,
            decoding_method='modified_beam_search',
            enable_endpoint_detection=True,
            rule1_min_trailing_silence=2.0,
            rule2_min_trailing_silence=trailing_silence_seconds)
        self.stream = self.recognizer.create_stream()

    def accept_waveform(self, rate, samples):
        self.stream.accept_waveform(rate, samples)

    def is_ready(self):
        return self.recognizer.is_ready(self.stream)

    def decode(self):
        self.recognizer.decode_stream(self.stream)

    def is_endpoint(self):
        return self.recognizer.is_endpoint(self.stream)

    def result(self):
        return self.recognizer.get_result(self.stream).lower().split()

    def reset(self):
        self.recognizer.reset(self.stream)


class VoiceTranscriber(Node):
    def __init__(self, **node_arguments):
        super().__init__('voice_transcriber', **node_arguments)
        audio_topic = self.declare_parameter(
            'audio_topic', 'microphone/audio').value
        word_topic = self.declare_parameter(
            'word_topic', 'perception/voice/word').value
        model_directory = self.declare_parameter(
            'model_directory',
            default_model_directory('voice_transcriber')).value
        num_threads = self.declare_parameter('num_threads', 2).value
        trailing_silence_seconds = self.declare_parameter(
            'trailing_silence_seconds', 0.8).value
        gain_target_level = self.declare_parameter(
            'gain_target_level', 0.1).value
        max_gain = self.declare_parameter('max_gain', 20.0).value
        self.is_enabled = self.declare_parameter('start_enabled', False).value

        self.gain_control = AutomaticGainControl(gain_target_level, max_gain)
        self.transcriber = StreamingTranscriber(
            model_directory, num_threads, trailing_silence_seconds)
        self.word_publisher = self.create_publisher(String, word_topic, 10)
        self.create_service(SetBool, '~/enable', self.on_enable)
        self.create_subscription(
            AudioStamped, audio_topic, self.on_audio, qos_profile_sensor_data)
        self.get_logger().info(
            f'voice transcriber: {audio_topic} -> {word_topic}')

    def on_enable(self, request, response):
        self.is_enabled = request.data
        response.success = True
        response.message = 'enabled' if request.data else 'disabled'
        return response

    def on_audio(self, message):
        if not self.is_enabled:
            return
        self.transcriber.accept_waveform(
            message.audio.info.rate,
            self.gain_control.leveled(normalized_samples(message)))
        while self.transcriber.is_ready():
            self.transcriber.decode()
        if not self.transcriber.is_endpoint():
            return
        words = [DECODE_ALIASES.get(word, word)
                 for word in self.transcriber.result()]
        self.transcriber.reset()
        teleop_words = [word for word in words if word in TELEOP_WORDS]
        utterance_is_recognized = (
            frozenset(words) <= TELEOP_WORDS | FILLER_WORDS)
        if not teleop_words or not utterance_is_recognized:
            if words:
                self.get_logger().info(f'ignored {" ".join(words)!r}')
            return
        for word in teleop_words:
            self.word_publisher.publish(String(data=word))
            self.get_logger().info(f'heard {word!r}')


def main():
    rclpy.init()
    node = VoiceTranscriber()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
