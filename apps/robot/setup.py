import os
import sys
from glob import glob

from setuptools import find_packages, setup

package_name = "robot"

if len(sys.argv) >= 2 and sys.argv[1] != "clean":
    from generate_parameter_library_py.setup_helper import generate_parameter_module

    generate_parameter_module(
        "hat_mdd10sm_parameters",
        "robot/hat_mdd10sm_parameters.yaml",
    )

setup(
    name=package_name,
    version="0.1.0",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages", [f"resource/{package_name}"]),
        (f"share/{package_name}", ["package.xml"]),
        (os.path.join("share", package_name, "launch"), glob("launch/*.launch.py")),
        (os.path.join("share", package_name, "urdf"), glob("urdf/*.urdf")),
        (os.path.join("share", package_name, "meshes"), glob("meshes/*.stl") + glob("meshes/*.glb")),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="Mumtahin Farabi",
    maintainer_email="mfarabi619@gmail.com",
    description="Differential-drive farm rover: Cytron MDD10 hardware driver and a kinematic/camera simulator as ROS 2 nodes.",
    license="AGPL-3.0-or-later",
    entry_points={
        "console_scripts": [
            "hat_mdd10sm = robot.hat_mdd10sm:main",
            "simulator = robot.simulator:main",
        ],
    },
)
