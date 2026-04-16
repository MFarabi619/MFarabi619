#include <Arduino.h>
#include <WalterModem.h>

//------------------------------------------
//  Configuration
//------------------------------------------
#define CELLULAR_APN "m2minternet.apn"

//------------------------------------------
//  Global state
//------------------------------------------
WalterModem modem;
WalterModemRsp rsp = {};
volatile bool is_gnss_fix_received = false;
WMGNSSFixEvent last_fix = {};

//------------------------------------------
//  GNSS event handler
//------------------------------------------
void on_gnss_event(WMGNSSEventType type, const WMGNSSEventData *data, void *args) {
  (void)args;
  if (type == WALTER_MODEM_GNSS_EVENT_FIX) {
    last_fix = data->gnssfix;
    is_gnss_fix_received = true;
  }
}

//------------------------------------------
//  LTE connection
//------------------------------------------
bool lte_connect() {
  Serial.println("[lte] setting opstate NO_RF...");
  if (!modem.setOpState(WALTER_MODEM_OPSTATE_NO_RF)) {
    Serial.println("[lte] failed to set NO_RF");
    return false;
  }

  Serial.printf("[lte] defining PDP context with APN: %s\n", CELLULAR_APN);
  if (!modem.definePDPContext(1, CELLULAR_APN)) {
    Serial.println("[lte] failed to define PDP context");
    return false;
  }

  Serial.println("[lte] setting opstate FULL...");
  if (!modem.setOpState(WALTER_MODEM_OPSTATE_FULL)) {
    Serial.println("[lte] failed to set FULL");
    return false;
  }

  Serial.println("[lte] setting automatic network selection...");
  if (!modem.setNetworkSelectionMode(WALTER_MODEM_NETWORK_SEL_MODE_AUTOMATIC)) {
    Serial.println("[lte] failed to set network selection");
    return false;
  }

  Serial.print("[lte] waiting for registration");
  for (int i = 0; i < 60; i++) {
    WalterModemNetworkRegState state = modem.getNetworkRegState();
    if (state == WALTER_MODEM_NETWORK_REG_REGISTERED_HOME ||
        state == WALTER_MODEM_NETWORK_REG_REGISTERED_ROAMING) {
      Serial.println(" registered!");
      return true;
    }
    Serial.print(".");
    delay(1000);
  }

  Serial.println(" timeout");
  return false;
}

//------------------------------------------
//  Print modem + SIM info
//------------------------------------------
void print_modem_info() {
  if (modem.getIdentity(&rsp)) {
    Serial.printf("[modem] IMEI: %s\n", rsp.data.identity.imei);
  }

  if (modem.getSIMState(&rsp)) {
    Serial.printf("[sim] state: %d\n", rsp.data.simState);
  }

  if (modem.getSIMCardID(&rsp)) {
    Serial.printf("[sim] ICCID: %s\n", rsp.data.simCardID.iccid);
  }

  if (modem.getRAT(&rsp)) {
    const char *rat_name = "unknown";
    switch (rsp.data.rat) {
    case WALTER_MODEM_RAT_LTEM:  rat_name = "LTE-M"; break;
    case WALTER_MODEM_RAT_NBIOT: rat_name = "NB-IoT"; break;
    case WALTER_MODEM_RAT_AUTO:  rat_name = "auto"; break;
    default: break;
    }
    Serial.printf("[modem] RAT: %s\n", rat_name);
  }
}

//------------------------------------------
//  Print cell info
//------------------------------------------
void print_cell_info() {
  if (modem.getCellInformation(WALTER_MODEM_SQNMONI_REPORTS_SERVING_CELL, &rsp)) {
    Serial.printf("[cell] operator: %s\n", rsp.data.cellInformation.netName);
    Serial.printf("[cell] RSRP: %.1f dBm\n", rsp.data.cellInformation.rsrp);
    Serial.printf("[cell] RSRQ: %.1f dB\n", rsp.data.cellInformation.rsrq);
    Serial.printf("[cell] RSSI: %.1f dBm\n", rsp.data.cellInformation.rssi);
    Serial.printf("[cell] CID: %lu\n", (unsigned long)rsp.data.cellInformation.cid);
    Serial.printf("[cell] TAC: %u\n", rsp.data.cellInformation.tac);
    Serial.printf("[cell] PCI: %u\n", rsp.data.cellInformation.pci);
    Serial.printf("[cell] EARFCN: %u\n", rsp.data.cellInformation.earfcn);
  }
}

//------------------------------------------
//  Sync GNSS clock from network
//------------------------------------------
void sync_gnss_clock() {
  Serial.println("[gnss] checking clock...");

  if (modem.gnssGetUTCTime(&rsp)) {
    if (rsp.data.clock.epochTime > 0) {
      Serial.printf("[gnss] clock set: %llu\n", rsp.data.clock.epochTime);
      return;
    }
  }

  Serial.println("[gnss] clock not set — will use cold start");
}

//------------------------------------------
//  Update GNSS assistance data
//------------------------------------------
void update_gnss_assistance() {
  Serial.println("[gnss] checking assistance data...");

  if (modem.gnssGetAssistanceStatus(&rsp)) {
    const char *names[] = {"almanac", "realtime_ephemeris", "predicted_ephemeris"};
    for (int i = 0; i < WALTER_MODEM_GNSS_ASSISTANCE_TYPE_COUNT; i++) {
      WMGNSSAssistance &a = rsp.data.gnssAssistance[i];
      Serial.printf("[gnss] %s: available=%d, expires_in=%ds\n",
                    names[i], a.available, a.timeToExpire);
    }
  }

  Serial.println("[gnss] updating realtime ephemeris...");
  if (modem.gnssUpdateAssistance(WALTER_MODEM_GNSS_ASSISTANCE_TYPE_REALTIME_EPHEMERIS)) {
    Serial.println("[gnss] assistance updated");
  } else {
    Serial.println("[gnss] assistance update failed (non-fatal)");
  }
}

//------------------------------------------
//  Get GNSS fix
//------------------------------------------
bool get_gnss_fix() {
  Serial.println("[gnss] disconnecting LTE for GNSS...");
  modem.setOpState(WALTER_MODEM_OPSTATE_MINIMUM);
  delay(500);

  Serial.println("[gnss] configuring...");
  modem.gnssConfig(
    WALTER_MODEM_GNSS_SENS_MODE_HIGH,
    WALTER_MODEM_GNSS_ACQ_MODE_COLD_WARM_START,
    WALTER_MODEM_GNSS_LOC_MODE_ON_DEVICE_LOCATION
  );

  Serial.println("[gnss] requesting fix...");
  is_gnss_fix_received = false;
  modem.gnssPerformAction(WALTER_MODEM_GNSS_ACTION_GET_SINGLE_FIX);

  Serial.print("[gnss] waiting for fix");
  for (int i = 0; i < 120; i++) {
    if (is_gnss_fix_received) {
      Serial.println(" got it!");
      return true;
    }
    Serial.print(".");
    delay(1000);
  }

  Serial.println(" timeout (no fix in 120s)");
  return false;
}

//------------------------------------------
//  Print GNSS fix
//------------------------------------------
void print_fix() {
  Serial.println("\n========== GNSS FIX ==========");
  bool is_valid = (last_fix.satCount > 0 && last_fix.estimatedConfidence > 0);
  Serial.printf("  Status:     %s\n", is_valid ? "VALID FIX" : "NO FIX");
  Serial.printf("  Latitude:   %.6f\n", last_fix.latitude);
  Serial.printf("  Longitude:  %.6f\n", last_fix.longitude);
  Serial.printf("  Height:     %.1f m\n", last_fix.height);
  Serial.printf("  Confidence: %.1f m\n", last_fix.estimatedConfidence);
  Serial.printf("  Satellites: %d\n", last_fix.satCount);
  Serial.printf("  Time to fix: %lu ms\n", (unsigned long)last_fix.timeToFix);
  Serial.printf("  Timestamp:  %lld\n", last_fix.timestamp);

  if (last_fix.satCount > 0) {
    Serial.println("  Satellites:");
    for (uint8_t i = 0; i < last_fix.satCount && i < 10; i++) {
      Serial.printf("    #%d: signal=%d dB/Hz\n",
                    last_fix.sats[i].satNo, last_fix.sats[i].signalStrength);
    }
  }
  Serial.println("==============================\n");
}

//------------------------------------------
//  Main
//------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("\n[walter] starting...");

  if (!modem.begin(&Serial2)) {
    Serial.println("[walter] modem init failed — rebooting");
    delay(3000);
    ESP.restart();
  }
  Serial.println("[walter] modem initialized");

  modem.setGNSSEventHandler(on_gnss_event, NULL);

  print_modem_info();

  if (!lte_connect()) {
    Serial.println("[walter] LTE failed — trying GNSS without assistance");
  } else {
    print_cell_info();
    sync_gnss_clock();
    update_gnss_assistance();
  }

  if (get_gnss_fix()) {
    print_fix();
  } else {
    Serial.println("[gnss] no fix obtained");
  }

  Serial.println("[walter] done.");
}

void loop() {
  delay(10000);
}
