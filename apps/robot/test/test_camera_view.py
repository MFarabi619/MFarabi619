import numpy as np

from robot.camera_view import render_field

WIDTH = 320
HEIGHT = 200


def render(x=0.0, y=0.0, theta=0.0):
    return render_field(x, y, theta, WIDTH, HEIGHT)


def test_shape_and_dtype():
    frame = render()
    assert frame.shape == (HEIGHT, WIDTH, 3)
    assert frame.dtype == np.uint8
    assert frame.flags["C_CONTIGUOUS"]


def test_sky_is_blue_dominant_field_is_green_dominant():
    frame = render().astype(np.int32)
    sky = frame[: HEIGHT // 4]
    ground = frame[-HEIGHT // 4 :]
    assert sky[..., 2].mean() > sky[..., 1].mean()
    assert ground[..., 1].mean() > ground[..., 2].mean()


def test_turning_changes_the_view():
    assert not np.array_equal(render(theta=0.0), render(theta=0.6))


def test_driving_forward_changes_the_view():
    assert not np.array_equal(render(x=0.0), render(x=0.5))
