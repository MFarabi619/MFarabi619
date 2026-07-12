#!/usr/bin/env bash

HOSTNAME="xiao.local"
UDP_ADDRESS=10.0.0.21
UDP_ADDRESS=$(ping $HOSTNAME -c1 | head -1 | awk -F'[()]' 'NR==1{print $2}')
[ -z "$HOST" ] && {
  echo "couldn't resolve $HOSTNAME" >&2
  exit 1
}

GPIO_DEVICE="gpio0"
PWM_DEVICE="mcpwm@6001e000"

LEFT_PWM_CHANNEL=0
RIGHT_PWM_CHANNEL=2

LEFT_DIR_PIN=2
RIGHT_DIR_PIN=7

PWM_PERIOD=100
PWM_DUTY=$PWM_PERIOD
DELAY_SECONDS=1

echo "forward"
mcumgrctl --udp "$UDP_ADDRESS" shell "gpio conf $GPIO_DEVICE $LEFT_DIR_PIN o1"
mcumgrctl --udp "$UDP_ADDRESS" shell "gpio conf $GPIO_DEVICE $RIGHT_DIR_PIN o0"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep $DELAY_SECONDS
echo "stop"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD 0"

echo "backward"
mcumgrctl --udp "$UDP_ADDRESS" shell "gpio conf $GPIO_DEVICE $LEFT_DIR_PIN o0"
mcumgrctl --udp "$UDP_ADDRESS" shell "gpio conf $GPIO_DEVICE $RIGHT_DIR_PIN o1"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep $DELAY_SECONDS
echo "stop"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD 0"

echo "left"
mcumgrctl --udp "$UDP_ADDRESS" shell "gpio conf $GPIO_DEVICE $LEFT_DIR_PIN o0"
mcumgrctl --udp "$UDP_ADDRESS" shell "gpio conf $GPIO_DEVICE $RIGHT_DIR_PIN o0"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep $DELAY_SECONDS
echo "stop"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD 0"

echo "right"
mcumgrctl --udp "$UDP_ADDRESS" shell "gpio conf $GPIO_DEVICE $LEFT_DIR_PIN o1"
mcumgrctl --udp "$UDP_ADDRESS" shell "gpio conf $GPIO_DEVICE $RIGHT_DIR_PIN o1"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD $PWM_DUTY"
sleep $DELAY_SECONDS
echo "stop"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $LEFT_PWM_CHANNEL $PWM_PERIOD 0"
mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $RIGHT_PWM_CHANNEL $PWM_PERIOD 0"
