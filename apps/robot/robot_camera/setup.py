from setuptools import setup

package_name = 'robot_camera'

setup(
    name=package_name,
    version='0.1.0',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Mumtahin Farabi',
    maintainer_email='mfarabi619@gmail.com',
    description='MJPEG-over-TCP camera ingester: splits JPEG frames into CompressedImage + CameraInfo.',
    license='GPL-3.0-only',
    entry_points={
        'console_scripts': [
            'mjpeg_camera = robot_camera.mjpeg_camera:main',
        ],
    },
)
