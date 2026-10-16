// Copyright 2026 Mumtahin Farabi
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#include <algorithm>
#include <chrono>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

#include <control_msgs/action/gripper_command.hpp>
#include <Eigen/Geometry>
#include <geometric_shapes/shape_extents.h>
#include <moveit/planning_scene_interface/planning_scene_interface.hpp>
#include <geometry_msgs/msg/vector3_stamped.hpp>
#include <moveit/task_constructor/solvers/cartesian_path.h>
#include <moveit/task_constructor/solvers/joint_interpolation.h>
#include <moveit/task_constructor/solvers/pipeline_planner.h>
#include <moveit/task_constructor/stages/connect.h>
#include <moveit/task_constructor/stages/current_state.h>
#include <moveit/task_constructor/stages/generate_grasp_pose.h>
#include <moveit/task_constructor/stages/move_relative.h>
#include <moveit/task_constructor/stages/move_to.h>
#include <moveit/task_constructor/stages/simple_grasp.h>
#include <moveit/task_constructor/task.h>
#include <moveit_msgs/msg/robot_state.hpp>
#include <rclcpp/rclcpp.hpp>
#include <rclcpp/wait_for_message.hpp>
#include <rclcpp_action/rclcpp_action.hpp>
#include <sensor_msgs/msg/joint_state.hpp>
#include <shape_msgs/msg/mesh.hpp>

namespace {

constexpr char ARM_GROUP[] = "arm";
constexpr char GRIPPER_GROUP[] = "gripper";
constexpr char GRIPPER_JOINT[] = "robotiq_85_left_knuckle_joint";
constexpr char GRIPPER_CONTROLLER[] = "robotiq_gripper_controller";
constexpr char GRIPPER_OPEN_POSE[] = "open";
constexpr char END_EFFECTOR[] = "end_effector";
constexpr char IK_FRAME_LINK[] = "end_effector_link";
constexpr char PLANNING_FRAME[] = "world";
constexpr double IK_FRAME_OFFSET_Z_METERS = 0.147;
const Eigen::Quaterniond IK_FRAME_ROTATION(0, 1, 0, 0);
constexpr double GRASP_ANGLE_DELTA_RADIANS = 0.2;
constexpr double GRIPPER_MAX_GAP_METERS = 0.085;
constexpr double GRIPPER_CLOSED_RADIANS = 0.8;
constexpr double GRASP_SQUEEZE_FACTOR = 0.9;
constexpr double HOLD_PRELOAD_RADIANS = 0.005;
constexpr double HOLD_MAX_EFFORT = 5.0;
constexpr std::chrono::seconds GRIPPER_ACTION_SERVER_TIMEOUT_SECONDS{ 5 };
constexpr double APPROACH_MIN_METERS = 0.03;
constexpr double APPROACH_MAX_METERS = 0.12;
constexpr double LIFT_MIN_METERS = 0.05;
constexpr double LIFT_MAX_METERS = 0.15;
constexpr double DOWNWARD = -1.0;
constexpr double UPWARD = 1.0;
constexpr size_t MAX_SOLUTIONS = 2;
constexpr bool INTROSPECTION_ENABLED = false;
constexpr double MAX_VELOCITY_SCALING_FACTOR = 0.5;
constexpr double MAX_ACCELERATION_SCALING_FACTOR = 0.5;

shape_msgs::msg::Mesh object_mesh(const std::string& object) {
	moveit::planning_interface::PlanningSceneInterface scene;
	const auto objects = scene.getObjects({ object });
	const auto found = objects.find(object);
	if (found == objects.end() || found->second.meshes.empty()) {
		throw std::runtime_error(
		    "object '" + object + "' has no mesh in the planning scene");
	}
	return found->second.meshes.front();
}

double widest_horizontal_extent_meters(const shape_msgs::msg::Mesh& mesh) {
	double x_extent_meters = 0.0;
	double y_extent_meters = 0.0;
	double z_extent_meters = 0.0;
	geometric_shapes::getShapeExtents(
	    mesh, x_extent_meters, y_extent_meters, z_extent_meters);
	return std::max(x_extent_meters, y_extent_meters);
}

double grasp_close_radians(double width_meters) {
	const double squeezed_gap_meters = GRASP_SQUEEZE_FACTOR * width_meters;
	const double close_radians = GRIPPER_CLOSED_RADIANS *
	    (1.0 - squeezed_gap_meters / GRIPPER_MAX_GAP_METERS);
	return std::clamp(close_radians, 0.0, GRIPPER_CLOSED_RADIANS);
}

double measured_joint_radians(const rclcpp::Node::SharedPtr& node,
                              const std::string& joint_name) {
	auto callback_group = node->create_callback_group(
	    rclcpp::CallbackGroupType::MutuallyExclusive, false);
	rclcpp::SubscriptionOptions options;
	options.callback_group = callback_group;
	auto subscription = node->create_subscription<sensor_msgs::msg::JointState>(
	    "joint_states", rclcpp::SensorDataQoS(),
	    [](sensor_msgs::msg::JointState::ConstSharedPtr) {}, options);
	sensor_msgs::msg::JointState state;
	while (rclcpp::wait_for_message(
	    state, subscription, node->get_node_options().context())) {
		const auto found =
		    std::find(state.name.begin(), state.name.end(), joint_name);
		if (found != state.name.end()) {
			return state.position[found - state.name.begin()];
		}
	}
	throw std::runtime_error("joint_states unavailable");
}

void hold_gripper(const rclcpp::Node::SharedPtr& node, double position_radians) {
	auto gripper_commander =
	    rclcpp_action::create_client<control_msgs::action::GripperCommand>(
	        node, std::string(GRIPPER_CONTROLLER) + "/gripper_cmd");
	if (!gripper_commander->wait_for_action_server(
	        GRIPPER_ACTION_SERVER_TIMEOUT_SECONDS)) {
		throw std::runtime_error("gripper action server unavailable");
	}
	control_msgs::action::GripperCommand::Goal goal;
	goal.command.position = position_radians;
	goal.command.max_effort = HOLD_MAX_EFFORT;
	gripper_commander->async_send_goal(goal).get();
}

}  // namespace

int main(int argc, char** argv) {
	rclcpp::init(argc, argv);
	auto node = rclcpp::Node::make_shared("pick_task");
	const std::string object =
	    node->declare_parameter<std::string>("object", "apple");
	std::thread node_spinner([node] { rclcpp::spin(node); });

	using namespace moveit::task_constructor;

	moveit_msgs::msg::RobotState grasp_posture;
	grasp_posture.is_diff = true;
	grasp_posture.joint_state.name = { GRIPPER_JOINT };
	grasp_posture.joint_state.position = {
		grasp_close_radians(widest_horizontal_extent_meters(object_mesh(object)))
	};

	Task task("", INTROSPECTION_ENABLED);
	task.setName("pick " + object);
	task.loadRobotModel(node);

	auto sampling_planner = std::make_shared<solvers::PipelinePlanner>(node);
	sampling_planner->setMaxVelocityScalingFactor(MAX_VELOCITY_SCALING_FACTOR);
	sampling_planner->setMaxAccelerationScalingFactor(
	    MAX_ACCELERATION_SCALING_FACTOR);
	auto interpolation_planner =
	    std::make_shared<solvers::JointInterpolationPlanner>();
	interpolation_planner->setMaxVelocityScalingFactor(
	    MAX_VELOCITY_SCALING_FACTOR);
	interpolation_planner->setMaxAccelerationScalingFactor(
	    MAX_ACCELERATION_SCALING_FACTOR);

	TrajectoryExecutionInfo arm_execution;
	arm_execution.controller_names = { "joint_trajectory_controller" };
	TrajectoryExecutionInfo gripper_execution;
	gripper_execution.controller_names = { GRIPPER_CONTROLLER };

	auto current_state = std::make_unique<stages::CurrentState>("current state");
	Stage* current_state_stage = current_state.get();
	task.add(std::move(current_state));

	auto open_gripper =
	    std::make_unique<stages::MoveTo>("open gripper", interpolation_planner);
	open_gripper->setGroup(GRIPPER_GROUP);
	open_gripper->setGoal(GRIPPER_OPEN_POSE);
	open_gripper->setTrajectoryExecutionInfo(gripper_execution);
	task.add(std::move(open_gripper));

	auto move_to_pick = std::make_unique<stages::Connect>(
	    "move to pick",
	    stages::Connect::GroupPlannerVector{
	        {ARM_GROUP, sampling_planner},
	        {GRIPPER_GROUP, interpolation_planner}});
	move_to_pick->setProperty("merge_mode", stages::Connect::SEQUENTIAL);
	task.add(std::move(move_to_pick));

	auto grasp_generator =
	    std::make_unique<stages::GenerateGraspPose>("generate grasp pose");
	grasp_generator->setAngleDelta(GRASP_ANGLE_DELTA_RADIANS);
	grasp_generator->setObject(object);
	grasp_generator->setPreGraspPose(GRIPPER_OPEN_POSE);
	grasp_generator->setGraspPose(grasp_posture);
	grasp_generator->setMonitoredStage(current_state_stage);

	auto grasp =
	    std::make_unique<stages::SimpleGrasp>(std::move(grasp_generator), "grasp");
	grasp->setIKFrame(
	    Eigen::Translation3d(0, 0, IK_FRAME_OFFSET_Z_METERS) * IK_FRAME_ROTATION,
	    IK_FRAME_LINK);
	grasp->findChild("close gripper")->setTrajectoryExecutionInfo(
	    gripper_execution);

	grasp->setObject(object);
	grasp->setEndEffector(END_EFFECTOR);

	auto cartesian_solver = std::make_shared<solvers::CartesianPath>();
	cartesian_solver->setMaxVelocityScalingFactor(MAX_VELOCITY_SCALING_FACTOR);
	cartesian_solver->setMaxAccelerationScalingFactor(
	    MAX_ACCELERATION_SCALING_FACTOR);

	auto approach =
	    std::make_unique<stages::MoveRelative>("approach object", cartesian_solver);
	approach->setGroup(ARM_GROUP);
	approach->setIKFrame(IK_FRAME_LINK);
	geometry_msgs::msg::Vector3Stamped approach_motion;
	approach_motion.header.frame_id = PLANNING_FRAME;
	approach_motion.vector.z = DOWNWARD;
	approach->setDirection(approach_motion);
	approach->setMinMaxDistance(APPROACH_MIN_METERS, APPROACH_MAX_METERS);
	approach->setTrajectoryExecutionInfo(arm_execution);
	task.add(std::move(approach));

	task.add(std::move(grasp));

	auto lift =
	    std::make_unique<stages::MoveRelative>("lift object", cartesian_solver);
	lift->setGroup(ARM_GROUP);
	lift->setIKFrame(IK_FRAME_LINK);
	geometry_msgs::msg::Vector3Stamped lift_motion;
	lift_motion.header.frame_id = PLANNING_FRAME;
	lift_motion.vector.z = UPWARD;
	lift->setDirection(lift_motion);
	lift->setMinMaxDistance(LIFT_MIN_METERS, LIFT_MAX_METERS);
	lift->setTrajectoryExecutionInfo(arm_execution);
	task.add(std::move(lift));

	int exit_code = 0;
	try {
		if (task.plan(MAX_SOLUTIONS)) {
			std::cout << "planned " << task.numSolutions()
			          << " solutions, executing best" << std::endl;
			task.execute(*task.solutions().front());
			hold_gripper(node,
			             measured_joint_radians(node, GRIPPER_JOINT) +
			                 HOLD_PRELOAD_RADIANS);
			std::cout << "picked '" << object << "'" << std::endl;
		} else {
			std::cerr << "no pick solution found for '" << object << "'"
			          << std::endl;
			task.explainFailure(std::cerr);
			exit_code = 1;
		}
	} catch (const InitStageException& exception) {
		std::cerr << exception << std::endl;
		exit_code = 1;
	}

	rclcpp::shutdown();
	node_spinner.join();
	return exit_code;
}
