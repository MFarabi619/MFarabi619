# Pinout command

# Power rails.

# True enables them, False disables them.

# CC01
uint8 CC01_USER_PWR_CTRL=0

bool[] rails

# User controlled outputs.

# Bit 1 sets the output to on/off
# Bit 2-32 represent the toggle period in milliseconds
# Toggle period of 0 implies no toggling
# Minimum toggle period is 100ms
# Toggle period precision is 10ms

# Dingo 1.0 (D100)
uint8 D100_AUX_OUT1=0
uint8 D100_AUX_OUT2=1
uint8 D100_AUX_OUT3=2

# Dingo 1.5 (D150)
uint8 D150_AUX_OUT1=0
uint8 D150_AUX_OUT2=1
uint8 D150_AUX_OUT3=2

# CC01
uint8 CC01_AUX_OUT1=0
uint8 CC01_AUX_OUT2=1
uint8 CC01_AUX_OUT3=2
uint8 CC01_GPO0=3
uint8 CC01_GPO1=4
uint8 CC01_GPO2=5
uint8 CC01_GPO3=6

uint32[] outputs
