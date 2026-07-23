# Pinout state

std_msgs/Header header

# Current power rail state

# CC01
uint8 CC01_USER_PWR_CTRL=0

bool[] rails

# Current input state

# Dingo 1.0 (D100)
uint8 D100_AUX_IN1=0
uint8 D100_AUX_IN2=1
uint8 D100_AUX_IN3=2

# Dingo 1.5 (D150)
uint8 D150_AUX_IN1=0
uint8 D150_AUX_IN2=1
uint8 D150_AUX_IN3=2

# CC01
uint8 CC01_AUX_IN1=0
uint8 CC01_AUX_IN2=1
uint8 CC01_AUX_IN3=2
uint8 CC01_GPI0=3
uint8 CC01_GPI1=4
uint8 CC01_GPI2=5
uint8 CC01_GPI3=6

bool[] inputs

# Current output state

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

bool[] outputs

# Current output toggle period

uint32[] output_periods
