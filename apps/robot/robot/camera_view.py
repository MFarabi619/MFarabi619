import numpy as np

SKY_TOP_COLOR = np.array([90, 140, 210], dtype=np.float32)
SKY_HORIZON_COLOR = np.array([200, 220, 245], dtype=np.float32)
FIELD_COLOR = np.array([78, 132, 58], dtype=np.float32)
FURROW_COLOR = np.array([120, 92, 60], dtype=np.float32)
HAZE_COLOR = np.array([200, 215, 225], dtype=np.float32)


def intrinsics(width, height, fov_deg):
    focal = (width / 2.0) / np.tan(np.radians(fov_deg) / 2.0)
    return focal, focal, width / 2.0, height / 2.0


def render_field(x, y, theta, width=640, height=400, fov_deg=70.0,
                 camera_height=0.2, row_spacing=0.6, fog_distance=18.0):
    focal, _, center_x, center_y = intrinsics(width, height, fov_deg)
    columns = np.arange(width, dtype=np.float32)
    rows = np.arange(height, dtype=np.float32)
    grid_u, grid_v = np.meshgrid(columns, rows)

    sky_blend = np.clip(grid_v / center_y, 0.0, 1.0)[..., None]
    image = SKY_TOP_COLOR * (1.0 - sky_blend) + SKY_HORIZON_COLOR * sky_blend

    is_ground = grid_v > center_y
    depth = np.where(is_ground, grid_v - center_y, 1.0)
    forward = np.where(is_ground, camera_height * focal / depth, 0.0)
    left = forward * (center_x - grid_u) / focal

    world_x = x + forward * np.cos(theta) - left * np.sin(theta)
    world_y = y + forward * np.sin(theta) + left * np.cos(theta)

    is_crop_row = np.abs(np.mod(world_y / row_spacing, 1.0) - 0.5) < 0.18
    is_cross_mark = np.abs(np.mod(world_x / 1.0, 1.0) - 0.5) < 0.06
    ground = np.where(is_crop_row[..., None], FURROW_COLOR, FIELD_COLOR)
    ground = np.where(is_cross_mark[..., None], ground * 0.82, ground)

    fog = np.clip(forward / fog_distance, 0.0, 1.0)[..., None]
    ground = ground * (1.0 - fog) + HAZE_COLOR * fog

    image = np.where(is_ground[..., None], ground, image)
    return np.ascontiguousarray(np.clip(image, 0, 255).astype(np.uint8))
