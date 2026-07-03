import os
import struct
import threading
import time

import numpy as np
import sounddevice as sd
import websocket
from pynput import keyboard

import mlx_whisper

CMD_VEL_TOPIC = "/cmd_vel"
SAMPLE_RATE = 16000
MAX_LINEAR = 0.4
MAX_ANGULAR = 1.0
PUBLISH_HZ = 5.0
DEADMAN_SECONDS = 3.0
PUSH_TO_TALK_KEY = keyboard.Key.alt_r

COMMANDS = {
    "forward": (1.0, 0.0),
    "ahead": (1.0, 0.0),
    "go": (1.0, 0.0),
    "back": (-1.0, 0.0),
    "backward": (-1.0, 0.0),
    "reverse": (-1.0, 0.0),
    "left": (0.0, 1.0),
    "right": (0.0, -1.0),
    "stop": (0.0, 0.0),
    "halt": (0.0, 0.0),
}


def encode_twist(linear_x, angular_z):
    return b"\x00\x01\x00\x00" + struct.pack(
        "<6d", linear_x, 0.0, 0.0, 0.0, 0.0, angular_z
    )


class BridgePublisher:
    def __init__(self, url):
        self.channel_id = 1
        self.send_lock = threading.Lock()
        self.connection = websocket.create_connection(
            url, subprotocols=["foxglove.sdk.v1"]
        )
        advertise = (
            '{"op":"advertise","channels":[{"id":%d,"topic":"%s",'
            '"encoding":"cdr","schemaName":"geometry_msgs/msg/Twist"}]}'
            % (self.channel_id, CMD_VEL_TOPIC)
        )
        with self.send_lock:
            self.connection.send(advertise)
        threading.Thread(target=self._drain, daemon=True).start()

    def _drain(self):
        while True:
            try:
                self.connection.recv()
            except Exception:
                return

    def publish_twist(self, linear_x, angular_z):
        frame = (
            b"\x01"
            + struct.pack("<I", self.channel_id)
            + encode_twist(linear_x, angular_z)
        )
        with self.send_lock:
            self.connection.send_binary(frame)


class VoiceControl:
    def __init__(self, bridge_url, model):
        self.bridge_url = bridge_url
        self.model = model
        self.publisher = BridgePublisher(bridge_url)
        self.state_lock = threading.Lock()
        self.active = (0.0, 0.0)
        self.last_command = 0.0
        self.recording = False
        self.frames = []
        self.stream = None

    def set_command(self, linear_weight, angular_weight):
        with self.state_lock:
            self.active = (linear_weight * MAX_LINEAR, angular_weight * MAX_ANGULAR)
            self.last_command = time.monotonic()

    def publisher_loop(self):
        period = 1.0 / PUBLISH_HZ
        while True:
            with self.state_lock:
                linear_x, angular_z = self.active
                if time.monotonic() - self.last_command > DEADMAN_SECONDS:
                    linear_x, angular_z, self.active = 0.0, 0.0, (0.0, 0.0)
            try:
                self.publisher.publish_twist(linear_x, angular_z)
            except Exception as error:
                print("publish error:", error)
            time.sleep(period)

    def start_recording(self):
        self.frames = []
        self.recording = True

        def callback(indata, _frames, _time, _status):
            if self.recording:
                self.frames.append(indata.copy())

        self.stream = sd.InputStream(
            samplerate=SAMPLE_RATE, channels=1, dtype="float32", callback=callback
        )
        self.stream.start()
        print("listening…")

    def stop_recording(self):
        if not self.recording:
            return
        self.recording = False
        self.stream.stop()
        self.stream.close()
        self.stream = None
        if not self.frames:
            return
        audio = np.concatenate(self.frames, axis=0).flatten()
        result = mlx_whisper.transcribe(audio, path_or_hf_repo=self.model)
        text = result.get("text", "").strip().lower()
        print("heard:", repr(text))
        for word, (linear_weight, angular_weight) in COMMANDS.items():
            if word in text:
                print("->", word)
                self.set_command(linear_weight, angular_weight)
                return
        print("-> no command matched")

    def on_press(self, key):
        if key == PUSH_TO_TALK_KEY and not self.recording:
            self.start_recording()

    def on_release(self, key):
        if key == PUSH_TO_TALK_KEY:
            self.stop_recording()

    def run(self):
        threading.Thread(target=self.publisher_loop, daemon=True).start()
        print("voice control ready -> %s via %s" % (CMD_VEL_TOPIC, self.bridge_url))
        print("hold RIGHT-OPTION and speak:", ", ".join(sorted(COMMANDS)))
        with keyboard.Listener(
            on_press=self.on_press, on_release=self.on_release
        ) as listener:
            listener.join()


def main():
    VoiceControl(os.environ["ROS2_BRIDGE_URL"], os.environ["WHISPER_MODEL"]).run()


if __name__ == "__main__":
    main()
