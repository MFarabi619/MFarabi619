from better_launch import BetterLaunch, convenience, launch_this


@launch_this
def record():
    BetterLaunch()

    convenience.record_topics(camera_topic="image_raw")
