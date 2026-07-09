#!/usr/bin/env bash

UDP_ADDRESS="10.0.0.21"
PWM_DEVICE="ledc@60019000"

LEFT_FORWARD_CHANNEL=0
LEFT_BACKWARD_CHANNEL=1
RIGHT_FORWARD_CHANNEL=2
RIGHT_BACKWARD_CHANNEL=3

PWM_PERIOD=1000
PWM_DUTY=700

LED_DEVICE="ws2812@0"
RED="ff0000"
GREEN="00ff00"
BLUE="0000ff"
WHITE="ffffff"
OFF="000000"
LED_COUNT=4
WIPE_WAIT=0.2

echo "forward"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_FORWARD_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_FORWARD_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep 1
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_FORWARD_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_FORWARD_CHANNEL $PWM_PERIOD 0"

echo "backward"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_BACKWARD_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_BACKWARD_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep 1
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_BACKWARD_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_BACKWARD_CHANNEL $PWM_PERIOD 0"

echo "turn left"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_BACKWARD_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_FORWARD_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep 1
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_BACKWARD_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_FORWARD_CHANNEL $PWM_PERIOD 0"

echo "turn right"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_FORWARD_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_BACKWARD_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep 1
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_FORWARD_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_BACKWARD_CHANNEL $PWM_PERIOD 0"

# echo "per-pixel: red green blue white"
# mcumgrctl --udp $UDP_ADDRESS shell "led_strip update_rgb $LED_DEVICE $RED $GREEN $BLUE $WHITE"
# sleep 3

# for COLOR in $RED $GREEN $BLUE; do
# 	echo "wipe $COLOR"
# 	for n in $(seq 1 $LED_COUNT); do
# 		mcumgrctl --udp $UDP_ADDRESS shell "led_strip fill $LED_DEVICE $COLOR $n"
# 		sleep $WIPE_WAIT
# 	done
# done
# sleep 1

# echo "off"
# mcumgrctl --udp $UDP_ADDRESS shell "led_strip fill $LED_DEVICE $OFF $LED_COUNT"
