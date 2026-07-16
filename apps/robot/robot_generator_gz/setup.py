import os

from setuptools import setup


package_name = 'robot_generator_gz'

setup(
    name=package_name,
    version='0.1.0',
    packages=[
        package_name,
        package_name + '.launch',
    ],
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
    description='Generates the Gazebo bridge launch file from robot.yaml',
    license='GPL-3.0-only',
    entry_points={
        'console_scripts': [
            'generate_gz_launch = robot_generator_gz.launch.generator:main',
        ],
    },
)
