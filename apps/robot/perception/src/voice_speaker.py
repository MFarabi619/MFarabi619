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

from voice_word_detector import default_model_directory

PORTAUDIO_FLOAT32 = 1
LIVE_PARAMETERS = frozenset({'language', 'speaker_id'})


class KokoroSynthesizer:
    def __init__(self, model_directory):
        def model_file(name):
            return os.path.join(model_directory, name)
        self.tts = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(
                kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                    model=model_file('model.onnx'),
                    voices=model_file('voices.bin'),
                    tokens=model_file('tokens.txt'),
                    data_dir=model_file('espeak-ng-data'),
                    lexicon=model_file('lexicon-us-en.txt')),
                num_threads=4)))

    def generate(self, text, speaker_id):
        return self.tts.generate(text, sid=speaker_id)


class VitsSynthesizer:
    def __init__(self, model_directory):
        def model_file(name):
            return os.path.join(model_directory, name)
        self.tts = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(
                vits=sherpa_onnx.OfflineTtsVitsModelConfig(
                    model=model_file('fr_FR-siwis-medium.onnx'),
                    tokens=model_file('tokens.txt'),
                    data_dir=model_file('espeak-ng-data')),
                num_threads=1)))

    def generate(self, text, speaker_id):
        return self.tts.generate(text)


class VoiceSpeaker(Node):
    def __init__(self):
        super().__init__('voice_speaker')
        speech_topic = self.declare_parameter(
            'speech_topic', 'perception/voice/speech').value
        audio_topic = self.declare_parameter('audio_topic', 'audio').value
        model_directory = self.declare_parameter(
            'model_directory', default_model_directory('voice_speaker')).value
        self.language = self.declare_parameter('language', 'en').value
        self.speaker_id = self.declare_parameter('speaker_id', 21).value

        self.synthesizers = {
            'en': KokoroSynthesizer(os.path.join(model_directory, 'english')),
            'fr': VitsSynthesizer(os.path.join(model_directory, 'french')),
        }
        self.audio_publisher = self.create_publisher(
            AudioStamped, audio_topic, qos_profile_sensor_data)
        self.add_post_set_parameters_callback(self.on_parameters_set)
        self.create_subscription(String, speech_topic, self.on_speech, 10)
        self.get_logger().info(f'voice speaker: {speech_topic} -> {audio_topic}')

    def on_parameters_set(self, parameters):
        for parameter in parameters:
            if parameter.name in LIVE_PARAMETERS:
                setattr(self, parameter.name, parameter.value)

    def on_speech(self, message):
        if not message.data:
            return
        synthesizer = self.synthesizers.get(self.language)
        if synthesizer is None:
            self.get_logger().warning(f'no voice for language {self.language!r}')
            return
        synthesis = synthesizer.generate(message.data, self.speaker_id)
        self.audio_publisher.publish(self.speech_message(synthesis))

    def speech_message(self, synthesis):
        message = AudioStamped()
        message.header.stamp = self.get_clock().now().to_msg()
        message.audio.info.format = PORTAUDIO_FLOAT32
        message.audio.info.channels = 1
        message.audio.info.rate = synthesis.sample_rate
        message.audio.info.chunk = len(synthesis.samples)
        message.audio.audio_data.float32_data = synthesis.samples
        return message


def main():
    rclpy.init()
    node = VoiceSpeaker()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
