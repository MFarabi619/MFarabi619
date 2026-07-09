#!/usr/bin/env bash

# XIAO     HAT (PIN, not GPIO)
#  D4  --> 3   I2C SDA
#  D5  --> 5   I2C SCL
#  3V3 --> 1   powers the HAT (else i2c scan is empty)
#  GND --> 9

UDP_ADDRESS="10.0.0.21"
I2C_BUS="i2c@60013000"
PWM_DEVICE="pca9685@40"
PERIOD_USEC=20000

PULSE_USEC_MINIMUM=500
PULSE_USEC_CENTER=1450
PULSE_USEC_MAXIMUM=2400
PULSE_SWEEP_USEC=("$PULSE_USEC_MINIMUM" "$PULSE_USEC_CENTER" "$PULSE_USEC_MAXIMUM" "$PULSE_USEC_CENTER")

FIRST_CHANNEL=0
LAST_CHANNEL=15
SERVO_SETTLE_SECONDS=0.5

mcumgrctl --udp "$UDP_ADDRESS"
mcumgrctl --udp "$UDP_ADDRESS" shell "device list"
mcumgrctl --udp "$UDP_ADDRESS" shell "i2c scan $I2C_BUS"

for channel in $(seq "$FIRST_CHANNEL" "$LAST_CHANNEL"); do
	for pulse_usec in "${PULSE_SWEEP_USEC[@]}"; do
		mcumgrctl --udp "$UDP_ADDRESS" shell "pwm usec $PWM_DEVICE $channel $PERIOD_USEC $pulse_usec"
		sleep "$SERVO_SETTLE_SECONDS"
	done
done
