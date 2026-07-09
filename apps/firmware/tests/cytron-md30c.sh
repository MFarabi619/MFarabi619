#!/usr/bin/env bash

UDP_ADDRESS="10.0.0.21"

GPIO_DEVICE="gpio0"
PWM_DEVICE="ledc@60019000"

LEFT_PWM_CHANNEL=0
RIGHT_PWM_CHANNEL=1

LEFT_DIR_PIN=2
RIGHT_DIR_PIN=7

PWM_PERIOD=50
PWM_DUTY=40

echo "forward"
mcumgrctl --udp $UDP_ADDRESS shell "gpio conf $GPIO_DEVICE $LEFT_DIR_PIN o1"
mcumgrctl --udp $UDP_ADDRESS shell "gpio conf $GPIO_DEVICE $RIGHT_DIR_PIN o0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep 5
echo "stop"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD 0"

echo "backward"
mcumgrctl --udp $UDP_ADDRESS shell "gpio conf $GPIO_DEVICE $LEFT_DIR_PIN o0"
mcumgrctl --udp $UDP_ADDRESS shell "gpio conf $GPIO_DEVICE $RIGHT_DIR_PIN o1"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep 5
echo "stop"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD 0"

echo "left"
mcumgrctl --udp $UDP_ADDRESS shell "gpio conf $GPIO_DEVICE $LEFT_DIR_PIN o0"
mcumgrctl --udp $UDP_ADDRESS shell "gpio conf $GPIO_DEVICE $RIGHT_DIR_PIN o0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep 5
echo "stop"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD 0"

echo "right"
mcumgrctl --udp $UDP_ADDRESS shell "gpio conf $GPIO_DEVICE $LEFT_DIR_PIN o1"
mcumgrctl --udp $UDP_ADDRESS shell "gpio conf $GPIO_DEVICE $RIGHT_DIR_PIN o1"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep 5
echo "stop"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp $UDP_ADDRESS shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD 0"
