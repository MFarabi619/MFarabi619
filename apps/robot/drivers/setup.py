import os

from setuptools import setup


package_name = 'robot_drivers'

setup(
    name=package_name,
    version='0.1.0',
    py_modules=['adafruit_bno085', 'cytron_motor_driver', 'orbbec_gemini_335l', 'rpicam_mjpeg'],
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        (os.path.join('share', package_name), ['package.xml']),
    ],
    entry_points={
        'console_scripts': [
            'cytron_motor_driver = cytron_motor_driver:main',
        ],
    },
    zip_safe=True,
)
