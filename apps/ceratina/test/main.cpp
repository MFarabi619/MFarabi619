#include <Arduino.h>
#include <unity.h>

void Driver_RS485_Modbus_run_live_tests(void);
void Driver_I2CBus_run_tests(void);
void Driver_RTC_run_tests(void);
void Driver_Solar_Radiation_run_tests(void);
void Driver_Wind_Speed_run_tests(void);
void Driver_Wind_Direction_run_tests(void);
void Driver_Soil_run_live_tests(void);
void Module_Voltage_Monitor_run_tests(void);
void Module_Temperature_And_Humidity_run_tests(void);
void Module_Time_run_tests(void);

void Module_Console_run_tests(void);
void Module_Database_run_tests(void);
void Module_Filesystem_run_tests(void);
// void Service_SMTP_Client_run_tests(void);
void Service_CloudEvents_run_tests(void);
void Module_Sensors_run_tests(void);

void setUp(void) {}

void tearDown(void) {}

void setup(void) {
  delay(2000);
  UNITY_BEGIN();

  Driver_I2CBus_run_tests();
  Driver_RS485_Modbus_run_live_tests();
  #if CONFIG_MODULE_SOLAR_RADIATION_ENABLED == 1
  Driver_Solar_Radiation_run_tests();
  #endif
  #if CONFIG_MODULE_VOLTAGE_MONITOR_ENABLED == 1
  Module_Voltage_Monitor_run_tests();
  #endif
  Driver_Wind_Speed_run_tests();
  Driver_Wind_Direction_run_tests();
  #if CONFIG_MODULE_SOIL_ENABLED == 1
  Driver_Soil_run_live_tests();
  #endif
  Module_Temperature_And_Humidity_run_tests();

  Driver_RTC_run_tests();

  Module_Console_run_tests();
  Module_Database_run_tests();
  Module_Filesystem_run_tests();
  // Service_SMTP_Client_run_tests();
  Service_CloudEvents_run_tests();
  Module_Sensors_run_tests();

  Module_Time_run_tests();

  UNITY_END();
}

void loop(void) { delay(1000); }
