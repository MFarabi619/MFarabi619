from better_launch import BetterLaunch, launch_this


@launch_this
def robot_gz_bridges():
    bl = BetterLaunch()

    bl.node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        name='clock_bridge',
        cmd_args=
            [
                '/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock'
                ,
            ]
        ,
    )

    bl.node(
        package='ros_gz_image',
        executable='image_bridge',
        name='image_bridge',
        cmd_args=
            [
                'camera/image_raw'
                ,
            ]
        ,
    )

    bl.node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        name='sensors_bridge',
        cmd_args=
            [
                '/camera/camera_info@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo'
                ,
                '/gps/fix@sensor_msgs/msg/NavSatFix[gz.msgs.NavSat'
                ,
            ]
        ,
    )

