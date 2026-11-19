# Copyright 2026 Mumtahin Farabi
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


from robot_boot.launch_policy import write_tempfile
import xacro

ARM_CONTROLLERS = {'kinova_link6': ['joint_trajectory_controller']}
GRIPPER_CONTROLLERS = {'robotiq_2f_85': ['robotiq_gripper_controller']}


def kinova_link6_xacro_fragment(arm):
    xyz = ' '.join(str(value) for value in arm.xyz)
    rpy = ' '.join(str(value) for value in arm.rpy)
    return f'''
  <xacro:include filename="$(find link6_description)/urdf/link6_macro.xacro"/>
  <xacro:link6 parent="{arm.parent}" prefix="{arm.name}_" robot_ip="" gripper="{arm.gripper_model}"
               sim_gazebo="true">
    <origin xyz="{xyz}" rpy="{rpy}"/>
  </xacro:link6>
  <xacro:include filename="$(find link6_description)/urdf/link6_end_effector.xacro"/>
  <xacro:link6_end_effector prefix="{arm.name}_" gripper="{arm.gripper_model}"
                            sim_gazebo="true"/>'''


ARM_XACRO_FRAGMENTS = {'kinova_link6': kinova_link6_xacro_fragment}


def write_urdf_file_with_arms(urdf_path, arms):
    if not arms:
        return urdf_path
    arm_xacro_fragments = ''.join(ARM_XACRO_FRAGMENTS[arm.model](arm) for arm in arms)
    wrapper_xacro = (
        '<robot name="robot" xmlns:xacro="http://www.ros.org/wiki/xacro">\n'
        f'  <xacro:include filename="{urdf_path}"/>{arm_xacro_fragments}\n'
        '</robot>\n')
    document = xacro.parse(wrapper_xacro)
    xacro.init_stacks(None)
    xacro.process_doc(document)
    return write_tempfile(document.toprettyxml(indent='  '), '.urdf')


def arm_controllers(arm):
    gripper_controllers = GRIPPER_CONTROLLERS[arm.gripper.model] if arm.gripper else []
    return ARM_CONTROLLERS[arm.model] + gripper_controllers


def arm_controller_parameters_files(bl, arm):
    models = [arm.model] + ([arm.gripper.model] if arm.gripper else [])
    return [bl.find('robot_control', f'{model}.yaml') for model in models]
