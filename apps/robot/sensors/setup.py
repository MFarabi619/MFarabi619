import os

from setuptools import setup


package_name = 'robot_sensors'

setup(
    name=package_name,
    version='0.1.0',
    py_modules=['imu', 'camera', 'orbbec_camera'],
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        (os.path.join('share', package_name), ['package.xml']),
    ],
    entry_points={
        'console_scripts': [
            'imu = imu:main',
            'camera = camera:main',
        ],
    },
    zip_safe=True,
)
