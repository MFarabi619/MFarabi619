# flake8: noqa

# auto-generated DO NOT EDIT

from rcl_interfaces.msg import ParameterDescriptor
from rcl_interfaces.msg import SetParametersResult
from rcl_interfaces.msg import FloatingPointRange, IntegerRange
from rclpy.clock import Clock
from rclpy.exceptions import InvalidParameterValueException
from rclpy.time import Time
import copy
import rclpy
import rclpy.parameter
from generate_parameter_library_py.python_validators import ParameterValidators



class hat_mdd10sm:

    class Params:
        # for detecting if the parameter struct has been updated
        stamp_ = Time()

        gpio_chip = 0
        pwm_frequency_hz = 1000
        left_pwm_pin = 12
        right_pwm_pin = 13
        left_dir_pin = 26
        right_dir_pin = 24
        left_forward_level = 1
        right_forward_level = 0
        duty_scale = 50.0



    class ParamListener:
        def __init__(self, node, prefix=""):
            self.prefix_ = prefix
            self.params_ = hat_mdd10sm.Params()
            self.node_ = node
            self.logger_ = rclpy.logging.get_logger("hat_mdd10sm." + prefix)

            self.declare_params()

            self.node_.add_on_set_parameters_callback(self.update)
            self.user_callback = None
            self.clock_ = Clock()

        def get_params(self):
            tmp = self.params_.stamp_
            self.params_.stamp_ = None
            paramCopy = copy.deepcopy(self.params_)
            paramCopy.stamp_ = tmp
            self.params_.stamp_ = tmp
            return paramCopy

        def is_old(self, other_param):
            return self.params_.stamp_ != other_param.stamp_

        def unpack_parameter_dict(self, namespace: str, parameter_dict: dict):
            """
            Flatten a parameter dictionary recursively.

            :param namespace: The namespace to prepend to the parameter names.
            :param parameter_dict: A dictionary of parameters keyed by the parameter names
            :return: A list of rclpy Parameter objects
            """
            parameters = []
            for param_name, param_value in parameter_dict.items():
                full_param_name = namespace + param_name
                # Unroll nested parameters
                if isinstance(param_value, dict):
                    nested_params = self.unpack_parameter_dict(
                            namespace=full_param_name + rclpy.parameter.PARAMETER_SEPARATOR_STRING,
                            parameter_dict=param_value)
                    parameters.extend(nested_params)
                else:
                    parameters.append(rclpy.parameter.Parameter(full_param_name, value=param_value))
            return parameters

        def set_params_from_dict(self, param_dict):
            params_to_set = self.unpack_parameter_dict('', param_dict)
            self.update(params_to_set)

        def set_user_callback(self, callback):
            self.user_callback = callback

        def clear_user_callback(self):
            self.user_callback = None

        def refresh_dynamic_parameters(self):
            updated_params = self.get_params()
            # TODO remove any destroyed dynamic parameters

            # declare any new dynamic parameters


        def update(self, parameters):
            updated_params = self.get_params()

            for param in parameters:
                if param.name == self.prefix_ + "gpio_chip":
                    updated_params.gpio_chip = param.value
                    self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))

                if param.name == self.prefix_ + "pwm_frequency_hz":
                    validation_result = ParameterValidators.bounds(param, 100, 20000)
                    if validation_result:
                        return SetParametersResult(successful=False, reason=validation_result)
                    updated_params.pwm_frequency_hz = param.value
                    self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))

                if param.name == self.prefix_ + "left_pwm_pin":
                    updated_params.left_pwm_pin = param.value
                    self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))

                if param.name == self.prefix_ + "right_pwm_pin":
                    updated_params.right_pwm_pin = param.value
                    self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))

                if param.name == self.prefix_ + "left_dir_pin":
                    updated_params.left_dir_pin = param.value
                    self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))

                if param.name == self.prefix_ + "right_dir_pin":
                    updated_params.right_dir_pin = param.value
                    self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))

                if param.name == self.prefix_ + "left_forward_level":
                    validation_result = ParameterValidators.bounds(param, 0, 1)
                    if validation_result:
                        return SetParametersResult(successful=False, reason=validation_result)
                    updated_params.left_forward_level = param.value
                    self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))

                if param.name == self.prefix_ + "right_forward_level":
                    validation_result = ParameterValidators.bounds(param, 0, 1)
                    if validation_result:
                        return SetParametersResult(successful=False, reason=validation_result)
                    updated_params.right_forward_level = param.value
                    self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))

                if param.name == self.prefix_ + "duty_scale":
                    validation_result = ParameterValidators.bounds(param, 0.0, 100.0)
                    if validation_result:
                        return SetParametersResult(successful=False, reason=validation_result)
                    updated_params.duty_scale = param.value
                    self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))



            updated_params.stamp_ = self.clock_.now()
            self.update_internal_params(updated_params)
            if self.user_callback:
                self.user_callback(self.get_params())
            return SetParametersResult(successful=True)

        def update_internal_params(self, updated_params):
            self.params_ = updated_params

        def declare_params(self):
            updated_params = self.get_params()
            # declare all parameters and give default values to non-required ones
            if not self.node_.has_parameter(self.prefix_ + "gpio_chip"):
                descriptor = ParameterDescriptor(description=r"lgpio chip number to open.", read_only = False)
                parameter = updated_params.gpio_chip
                self.node_.declare_parameter(self.prefix_ + "gpio_chip", parameter, descriptor)

            if not self.node_.has_parameter(self.prefix_ + "pwm_frequency_hz"):
                descriptor = ParameterDescriptor(description=r"PWM frequency for the motor channels, in hertz.", read_only = False)
                descriptor.integer_range.append(IntegerRange())
                descriptor.integer_range[-1].from_value = 100
                descriptor.integer_range[-1].to_value = 20000
                parameter = updated_params.pwm_frequency_hz
                self.node_.declare_parameter(self.prefix_ + "pwm_frequency_hz", parameter, descriptor)

            if not self.node_.has_parameter(self.prefix_ + "left_pwm_pin"):
                descriptor = ParameterDescriptor(description=r"GPIO pin for the left motor's PWM (speed) signal.", read_only = False)
                parameter = updated_params.left_pwm_pin
                self.node_.declare_parameter(self.prefix_ + "left_pwm_pin", parameter, descriptor)

            if not self.node_.has_parameter(self.prefix_ + "right_pwm_pin"):
                descriptor = ParameterDescriptor(description=r"GPIO pin for the right motor's PWM (speed) signal.", read_only = False)
                parameter = updated_params.right_pwm_pin
                self.node_.declare_parameter(self.prefix_ + "right_pwm_pin", parameter, descriptor)

            if not self.node_.has_parameter(self.prefix_ + "left_dir_pin"):
                descriptor = ParameterDescriptor(description=r"GPIO pin for the left motor's direction signal.", read_only = False)
                parameter = updated_params.left_dir_pin
                self.node_.declare_parameter(self.prefix_ + "left_dir_pin", parameter, descriptor)

            if not self.node_.has_parameter(self.prefix_ + "right_dir_pin"):
                descriptor = ParameterDescriptor(description=r"GPIO pin for the right motor's direction signal.", read_only = False)
                parameter = updated_params.right_dir_pin
                self.node_.declare_parameter(self.prefix_ + "right_dir_pin", parameter, descriptor)

            if not self.node_.has_parameter(self.prefix_ + "left_forward_level"):
                descriptor = ParameterDescriptor(description=r"Direction-pin level that drives the left motor forward.", read_only = False)
                descriptor.integer_range.append(IntegerRange())
                descriptor.integer_range[-1].from_value = 0
                descriptor.integer_range[-1].to_value = 1
                parameter = updated_params.left_forward_level
                self.node_.declare_parameter(self.prefix_ + "left_forward_level", parameter, descriptor)

            if not self.node_.has_parameter(self.prefix_ + "right_forward_level"):
                descriptor = ParameterDescriptor(description=r"Direction-pin level that drives the right motor forward.", read_only = False)
                descriptor.integer_range.append(IntegerRange())
                descriptor.integer_range[-1].from_value = 0
                descriptor.integer_range[-1].to_value = 1
                parameter = updated_params.right_forward_level
                self.node_.declare_parameter(self.prefix_ + "right_forward_level", parameter, descriptor)

            if not self.node_.has_parameter(self.prefix_ + "duty_scale"):
                descriptor = ParameterDescriptor(description=r"Percent PWM duty per unit of wheel speed (clamped to 100).", read_only = False)
                descriptor.floating_point_range.append(FloatingPointRange())
                descriptor.floating_point_range[-1].from_value = 0.0
                descriptor.floating_point_range[-1].to_value = 100.0
                parameter = updated_params.duty_scale
                self.node_.declare_parameter(self.prefix_ + "duty_scale", parameter, descriptor)

            # TODO: need validation
            # get parameters and fill struct fields
            param = self.node_.get_parameter(self.prefix_ + "gpio_chip")
            self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))
            updated_params.gpio_chip = param.value
            param = self.node_.get_parameter(self.prefix_ + "pwm_frequency_hz")
            self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))
            validation_result = ParameterValidators.bounds(param, 100, 20000)
            if validation_result:
                raise InvalidParameterValueException('pwm_frequency_hz',param.value, 'Invalid value set during initialization for parameter pwm_frequency_hz: ' + validation_result)
            updated_params.pwm_frequency_hz = param.value
            param = self.node_.get_parameter(self.prefix_ + "left_pwm_pin")
            self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))
            updated_params.left_pwm_pin = param.value
            param = self.node_.get_parameter(self.prefix_ + "right_pwm_pin")
            self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))
            updated_params.right_pwm_pin = param.value
            param = self.node_.get_parameter(self.prefix_ + "left_dir_pin")
            self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))
            updated_params.left_dir_pin = param.value
            param = self.node_.get_parameter(self.prefix_ + "right_dir_pin")
            self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))
            updated_params.right_dir_pin = param.value
            param = self.node_.get_parameter(self.prefix_ + "left_forward_level")
            self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))
            validation_result = ParameterValidators.bounds(param, 0, 1)
            if validation_result:
                raise InvalidParameterValueException('left_forward_level',param.value, 'Invalid value set during initialization for parameter left_forward_level: ' + validation_result)
            updated_params.left_forward_level = param.value
            param = self.node_.get_parameter(self.prefix_ + "right_forward_level")
            self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))
            validation_result = ParameterValidators.bounds(param, 0, 1)
            if validation_result:
                raise InvalidParameterValueException('right_forward_level',param.value, 'Invalid value set during initialization for parameter right_forward_level: ' + validation_result)
            updated_params.right_forward_level = param.value
            param = self.node_.get_parameter(self.prefix_ + "duty_scale")
            self.logger_.debug(param.name + ": " + param.type_.name + " = " + str(param.value))
            validation_result = ParameterValidators.bounds(param, 0.0, 100.0)
            if validation_result:
                raise InvalidParameterValueException('duty_scale',param.value, 'Invalid value set during initialization for parameter duty_scale: ' + validation_result)
            updated_params.duty_scale = param.value


            self.update_internal_params(updated_params)
