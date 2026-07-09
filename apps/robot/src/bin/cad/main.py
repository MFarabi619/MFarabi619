import logging

from yacv_server import show

from assembly import material_groups

logging.basicConfig(level=logging.INFO)

for group_index, (group_name, color, parts) in enumerate(material_groups):
    show(
        *parts,
        names=[f"{group_name}-{part_index}" for part_index in range(len(parts))],
        color_faces=color,
        auto_clear=(group_index == 0),
        tolerance=1.0,
        angular_tolerance=1.0,
    )
