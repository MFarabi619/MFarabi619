import os

from setuptools import setup


package_name = 'robot_config'

setup(
    name=package_name,
    version='0.1.0',
    packages=[
        package_name,
        package_name + '.common',
        package_name + '.common.definitions',
        package_name + '.common.utils',
        package_name + '.mounts',
        package_name + '.mounts.definitions',
        package_name + '.platform_config',
        package_name + '.sensors',
        package_name + '.sensors.definitions',
        package_name + '.system',
    ],
    data_files=[
        # Install marker file in the package index
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        # Include the package.xml file
        (os.path.join('share', package_name), ['package.xml']),
    ],
    install_requires=[
        'setuptools',
    ],
    zip_safe=True,
    maintainer='Mumtahin Farabi',
    maintainer_email='mfarabi619@gmail.com',
    description='robot.yaml parser and typed config model',
    license='GPL-3.0-only',
)
