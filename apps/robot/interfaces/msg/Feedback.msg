# High-frequency feedback from the motor driver, as necessary to support
# closed-loop control. Default publish frequency is 50Hz.

std_msgs/Header header

DriveFeedback[2] drivers

# Commanded control mode, use the MODE_ constants from Drive.
int8 commanded_mode

# Actual control mode. This may differ from the commanded in cases where
# the motor enable is off, the motors are in over-current, etc.
int8 actual_mode
