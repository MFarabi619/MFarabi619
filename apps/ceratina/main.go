package main

// https://github.com/tinygo-org/tinygo/blob/release/src/machine/machine_esp32s3.go
// https://tinygo.org/docs/reference/microcontrollers/machine/esp32-mini32/

// tinygo env
// tinygo ports
// tinygo flash -target=esp32s3 -port=/dev/ttyUSB0
// tinygo monitor -port=/dev/ttyUSB0

import (
	"machine"
	"time"
)

func main() {
	println("Hello World from TinyGo! 👋")

	count := 0
	led := machine.GPIO38
	led.Configure(machine.PinConfig{Mode: machine.PinOutput})

	println("CPU Frequency is: ")
	print(machine.GetCPUFrequency())

	for {
		println("count:", count)
		count++

		led.Low()
		println("LED IS:", led.Get())
		time.Sleep(time.Second / 2)

		led.High()
		println("LED IS:", led.Get())
		time.Sleep(time.Second / 2)
	}
}
