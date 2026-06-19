from setuptools import find_packages, setup

package_name = "robot"

setup(
    name=package_name,
    version="0.1.0",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages", [f"resource/{package_name}"]),
        (f"share/{package_name}", ["package.xml"]),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="Mumtahin Farabi",
    maintainer_email="mfarabi619@gmail.com",
    description="ROS 2 Scaffolding",
    license="AGPL",
    entry_points={
        "console_scripts": [
            "hat_mdd10sm = robot.hat_mdd10sm:main",
        ],
    },
)
