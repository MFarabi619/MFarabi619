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
    )

    bl.node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        name='sensors_bridge',
        cmd_args=
            [
                '/sensors/gps_0/fix@sensor_msgs/msg/NavSatFix[gz.msgs.NavSat'
                ,
            ]
        ,
    )

