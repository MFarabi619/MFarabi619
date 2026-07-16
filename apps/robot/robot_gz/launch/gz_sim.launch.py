import os

from ament_index_python.packages import get_package_share_directory
from better_launch import BetterLaunch, launch_this


@launch_this
def gz_sim(world: str = 'maize'):
    bl = BetterLaunch()
    share = get_package_share_directory('robot_gz')
    worlds = os.path.join(share, 'worlds')
    models = os.path.join(share, 'models')
    shares = [os.path.join(prefix, 'share')
              for prefix in os.environ.get('AMENT_PREFIX_PATH', '').split(':') if prefix]
    resource_path = os.pathsep.join([worlds, models] + shares)
    world_file = os.path.join(worlds, f'{world}.sdf')
    plugin_path = os.path.join(os.environ.get('CONDA_PREFIX', ''), 'lib')
    bl.process(
        ['gz', 'sim', world_file, '-r', '-v', '4'],
        name='gazebo',
        env={
            'GZ_SIM_RESOURCE_PATH': resource_path,
            'GZ_SIM_SYSTEM_PLUGIN_PATH': plugin_path,
        })
