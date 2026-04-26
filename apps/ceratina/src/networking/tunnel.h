#pragma once
#include <config.h>

namespace networking::tunnel {

enum Provider : uint8_t {
    ProviderDisabled = 0,
    ProviderBore,
    ProviderSelfHosted,
    ProviderLocaltunnel,
};

enum Phase : uint8_t {
    PhaseIdle = 0,
    PhaseInit,
    PhaseServe,
    PhaseWait,
};

struct Config {
    bool enabled;
    Provider provider;
    char host[96];
    uint16_t local_port;
    char path[64];
    bool reconnect;
};

struct Snapshot {
    bool enabled;
    bool started;
    bool stopped;
    bool ready;
    Provider provider;
    Phase phase;
    uint16_t remote_port;
    char url[128];
    char last_client_ip[16];
    unsigned long connect_attempts;
    unsigned long backoff_ms;
    unsigned long last_error_at;
    char last_error[96];
};

void initialize();
void service();
void stop();

bool isReady();
bool isStarted();

const char *accessURL();
const char *accessProviderName();
const char *accessLastClientIP();

void configure(const Config &config);
void accessConfig(Config &config);
bool storeConfig(Config *config);
bool clearConfig();
void accessSnapshot(Snapshot &snapshot);

void enable();
void disable();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
