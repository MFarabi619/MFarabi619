from robot.camera_stream import stream_url


def test_stream_url_builds_from_host_and_port():
    assert stream_url("rpi5-16", "8888") == "http://rpi5-16:8888/stream"
