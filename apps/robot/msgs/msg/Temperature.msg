# Location of temperature sensors.

std_msgs/Header header

# Jackal (J100)
uint8 J100_MCU=0
uint8 J100_PCB=1

# Dingo 1.0 (D100)
uint8 D100_MCU=0
uint8 D100_PCB=1

# Dingo 1.5 (D150)
uint8 D150_MCU=0
uint8 D150_PCB=1

# Warthog (W200)
uint8 W200_MCU=0

# Ridgeback (R100)
uint8 R100_MCU=0
uint8 R100_PCB=1

# Common Core (CC01)
uint8 CC01_MCU=0
uint8 CC01_FAN1=1
uint8 CC01_FAN2=2
uint8 CC01_FAN3=3
uint8 CC01_FAN4=4
uint8 CC01_FAN5=5
uint8 CC01_FAN6=6
uint8 CC01_FAN7=7
uint8 CC01_FAN8=8
uint8 CC01_5V_INDUCTOR=9
uint8 CC01_MAIN_GND_LUG=10
uint8 CC01_24V_DCDC=11
uint8 CC01_12V_DCDC=12
uint8 CC01_EXT_1=13
uint8 CC01_EXT_2=14
uint8 CC01_EXT_3=15
uint8 CC01_EXT_4=16
uint8 CC01_BREAKOUT_1=17
uint8 CC01_BREAKOUT_2=18

# Array of temperature readings in Celsius
float32[] temperatures
