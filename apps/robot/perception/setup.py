import os

from setuptools import setup


package_name = 'robot_perception'

setup(
    name=package_name,
    version='0.1.0',
    py_modules=['detect_crop_row', 'detect_hand_gestures', 'foxglove_panels'],
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        (os.path.join('share', package_name), ['package.xml']),
    ],
    install_requires=[
        'setuptools',
    ],
    zip_safe=True,
    maintainer='Mumtahin Farabi',
    maintainer_email='mfarabi619@gmail.com',
    description='Perception nodes (MediaPipe gesture recognition) for the robot',
    license='GPL-3.0-only',
    entry_points={
        'console_scripts': [
            'detect_crop_row = detect_crop_row:main',
            'detect_hand_gestures = detect_hand_gestures:main',
            'foxglove_panels = foxglove_panels:main',
        ],
    },
)
