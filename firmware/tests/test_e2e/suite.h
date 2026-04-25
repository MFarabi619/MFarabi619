// clang-format off
#pragma once

namespace boot::provisioning { void test(); }

namespace hardware::i2c { void test(); }
namespace hardware::system { void test(); }

namespace filesystems::api { void test(); }
namespace filesystems::eeprom { void test(); }
namespace filesystems::littlefs { void test(); }
namespace filesystems::sd { void test(); }

namespace networking::ble { void test(); }
namespace networking::ota { void test(); }
namespace networking::sntp { void test(); }
namespace networking::telnet { void test(); }
namespace networking::update { void test(); }
namespace networking::tunnel { void test(); }
namespace networking::wifi { void test(); }

namespace services::cloudevents { void test(); }
namespace services::data_logger { void test(); }
namespace services::email { void test(); }
namespace services::http::api::database { void test(); }
namespace services::http { void test(); }
namespace services::http_e2e { void test(); }
namespace services::identity { void test(); }
namespace services::rtc { void test(); }
namespace services::sshd { void test(); }
namespace services::ws_shell { void test(); }

namespace sensors::barometric_pressure { void test(); }
namespace sensors::carbon_dioxide { void test(); }
namespace sensors::current { void test(); }
namespace sensors::soil { void test(); }
namespace sensors::solar_radiation { void test(); }
namespace sensors::temperature_and_humidity { void test(); }
namespace sensors::rainfall { void test(); }
namespace sensors::voltage { void test(); }

namespace programs::buttons { void test(); }
namespace programs::coreutils { void test(); }
namespace programs::led { void test(); }
namespace programs::shell { void test(); }
namespace programs::sqlite { void test(); }
namespace programs::ssh_client { void test(); }
namespace power::sleep { void test(); }
