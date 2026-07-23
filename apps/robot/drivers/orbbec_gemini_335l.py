#!/usr/bin/env python3

from pyorbbecsdk import (
    Config,
    Context,
    OBFormat,
    OBLogLevel,
    OBSensorType,
    Pipeline,
)

FRAME_TIMEOUT_MS = 1000


class OrbbecGemini335L:
    def __init__(self, width, height, fps):
        Context().set_logger_level(OBLogLevel.WARNING)
        self.pipeline = Pipeline()
        config = Config()
        color_profiles = self.pipeline.get_stream_profile_list(
            OBSensorType.COLOR_SENSOR)
        config.enable_stream(
            color_profiles.get_video_stream_profile(
                width, height, OBFormat.MJPG, fps))
        self.pipeline.start(config)

    def color_calibration(self):
        camera_param = self.pipeline.get_camera_param()
        return camera_param.rgb_intrinsic, camera_param.rgb_distortion

    def frames(self):
        while True:
            frame_set = self.pipeline.wait_for_frames(FRAME_TIMEOUT_MS)
            if frame_set is None:
                continue
            color_frame = frame_set.get_color_frame()
            if color_frame is None:
                continue
            yield bytes(color_frame.get_data())

    def close(self):
        self.pipeline.stop()
