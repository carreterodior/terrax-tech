/*
  TERRAX Wireless Switch (wired relay version) — ESP32 firmware
  -------------------------------------------------------------
  The TERRAX TECH app talks to this board over Bluetooth LE; the board
  switches relay outputs directly (no 433 MHz radio, no remote receivers).
  Each relay output drives the coil of an automotive relay (or is the
  load relay itself on a small set-up) that powers the auxiliary lights.

  Same Bluetooth service and commands as the RF version (1.x), so the app
  works with either; the Info text says "relay" so the app can hide the
  radio-only settings.

  Hardware (see the wiring page / README.md):
    ESP32 (ESP-32S / WROOM-32 dev board), powered from a 12 V -> 5 V buck
    converter into the board's 5V/VIN pin.
    Relay board inputs IN1..IN8 on GPIO 16, 17, 18, 19, 21, 22, 23, 25.
    Relay board VCC -> 5 V, GND -> GND (common ground with the ESP32).
    On-board LED (GPIO2) flashes on every command.

  Outputs (channel -> relay):
    channel 0 = relay 1 = light set 1 power (low beam)
    channel 1 = relay 2 = light set 1 high beam
    channel 2 = relay 3 = light set 2 power, channel 3 = relay 4 = set 2 high beam
    ... up to channel 7 = relay 8 (4 light sets).

  Relay boards come in two kinds: single SRD-05VDC modules with a transistor
  (what TERRAX uses) switch ON with HIGH; many multi-channel optocoupler
  boards switch ON when the input is pulled LOW. Command 09 picks the kind
  (saved). Default since 2.0.1: HIGH trigger.
  LOW-trigger boards are driven "open drain" (since 2.0.2): ON pulls the
  input to GND, OFF lets go of the wire (pin floats). A 3.3 V "OFF" is not
  enough to switch off a 5 V low-trigger module (PNP transistor or
  optocoupler), which then stays on whatever the app says.

  USB serial console (115200 baud), for testing on the bench:
    1..8  toggle that relay      0  all off      ?  show every output
  At power-up every output starts OFF (safe: no lights come on by
  themselves when the car starts).

  Needs only the "esp32 by Espressif Systems" board package 4.x (BLE.h).

  Bluetooth protocol (raw bytes)
  ------------------------------
  Service         54580001-7e2a-4f3c-9b1a-5445525241ff
  Command (write) 54580002-...
     01 ch st          channel ch ON (st=1) or OFF (st=0)
     04 ch n gap10ms   n quick OFF->ON cycles, gap in 10 ms steps
                       (tri-colour lamps step White -> Yellow -> All-Weather)
     08 ch             switch channel ch OFF and forget it
     09 lvl            relay board kind: 0 = turns on with LOW, 1 = with HIGH
     0A                all outputs OFF
     02/03/05/06/07    radio-only commands of the RF version: ignored
  State (read/notify) 54580003-...   16 bytes, one per channel:
     0 = OFF, 1 = ON, 0xFF = no relay on this channel
  Info (read)         54580004-...
     "TERRAX Wireless Switch 2.0.2; relay; trigger HIGH; outputs 8; mac ..."

  Safety: any phone that connects can send commands. Bluetooth pairing /
  bonding is a planned next step before this ships to customers.
*/

#include <Arduino.h>
#include <BLE.h>
#include <Preferences.h>

// ---------------- configuration ----------------
static const char *FW_VERSION = "2.0.2";
static const char *BLE_NAME = "TERRAX WIRELESS SWITCH";
static const int LED_PIN = 2;
static const int CHANNELS = 16;                  // protocol size (state bytes)
// Boot-safe output pins (not strapping, flash or input-only pins).
static const int RELAY_PINS[] = {16, 17, 18, 19, 21, 22, 23, 25};
static const int OUTPUTS = sizeof(RELAY_PINS) / sizeof(RELAY_PINS[0]);

static const BLEUUID SERVICE_UUID("54580001-7e2a-4f3c-9b1a-5445525241ff");
static const BLEUUID CMD_UUID("54580002-7e2a-4f3c-9b1a-5445525241ff");
static const BLEUUID STATE_UUID("54580003-7e2a-4f3c-9b1a-5445525241ff");
static const BLEUUID INFO_UUID("54580004-7e2a-4f3c-9b1a-5445525241ff");

// ---------------- settings / state ----------------
Preferences prefs;
bool activeHigh = true;             // true: relay ON when input HIGH (SRD-05VDC modules)
uint8_t chanState[CHANNELS];

BLECharacteristic stateChar;
BLECharacteristic infoChar;
volatile bool clientConnected = false;

struct Command {
  uint8_t len;
  uint8_t data[8];
};
QueueHandle_t commandQueue;

// ---------------- outputs ----------------
// HIGH-trigger modules: push-pull, HIGH = on, LOW = off.
// LOW-trigger modules: open drain, LOW = on, pin floating (input) = off.
void drivePin(int pin, bool on) {
  if (activeHigh) {
    digitalWrite(pin, on ? HIGH : LOW);
    pinMode(pin, OUTPUT);
    digitalWrite(pin, on ? HIGH : LOW);
  } else if (on) {
    digitalWrite(pin, LOW);
    pinMode(pin, OUTPUT);
    digitalWrite(pin, LOW);
  } else {
    pinMode(pin, INPUT);
  }
}

void writeOutput(uint8_t ch, bool on) {
  if (ch >= OUTPUTS) return;
  drivePin(RELAY_PINS[ch], on);
  chanState[ch] = on ? 1 : 0;
}

void logOutput(uint8_t ch) {
  if (ch >= OUTPUTS) return;
  const bool on = chanState[ch] == 1;
  const char *sig = activeHigh ? (on ? "HIGH 3.3V" : "LOW 0V") : (on ? "LOW 0V" : "released");
  Serial.printf("  relay %d (GPIO %d): %s, signal %s
", ch + 1, RELAY_PINS[ch], on ? "ON" : "OFF", sig);
}

void allOff() {
  for (int ch = 0; ch < OUTPUTS; ch++) writeOutput(ch, false);
}

void blink() {
  digitalWrite(LED_PIN, HIGH);
  delay(30);
  digitalWrite(LED_PIN, LOW);
}

// ---------------- reporting ----------------
void publishState() {
  if (!stateChar) return;
  stateChar.setValue(chanState, CHANNELS);
  if (clientConnected) stateChar.notify();
}

void publishInfo() {
  if (!infoChar) return;
  char buf[112];
  uint64_t mac = ESP.getEfuseMac();
  snprintf(buf, sizeof(buf),
           "TERRAX Wireless Switch %s; relay; trigger %s; outputs %d; mac %04X%08lX",
           FW_VERSION, activeHigh ? "HIGH" : "LOW", OUTPUTS,
           (uint16_t)(mac >> 32), (unsigned long)mac);
  infoChar.setValue((const uint8_t *)buf, strlen(buf));
}

// ---------------- commands (run in loop) ----------------
void handle(const Command &c) {
  if (c.len == 0) return;
  const uint8_t op = c.data[0];
  const uint8_t ch = c.len > 1 ? c.data[1] : 0xFF;
  const bool chOk = ch < OUTPUTS;
  Serial.printf("cmd");
  for (uint8_t i = 0; i < c.len; i++) Serial.printf(" %02X", c.data[i]);
  Serial.println();

  switch (op) {
    case 0x01:  // ON / OFF
      if (c.len >= 3 && chOk) {
        writeOutput(ch, c.data[2] != 0);
        logOutput(ch);
        blink();
        publishState();
      }
      break;

    case 0x04:  // quick OFF->ON cycles (colour stepping)
      if (c.len >= 4 && chOk) {
        uint8_t n = c.data[2] ? c.data[2] : 1;
        if (n > 10) n = 10;
        uint16_t gap = (uint16_t)(c.data[3] ? c.data[3] : 30) * 10;
        for (uint8_t i = 0; i < n; i++) {
          writeOutput(ch, false);
          delay(gap);
          writeOutput(ch, true);
          delay(gap);
        }
        logOutput(ch);
        blink();
        publishState();
      }
      break;

    case 0x08:  // OFF and forget
      if (c.len >= 2 && chOk) {
        writeOutput(ch, false);
        publishState();
      }
      break;

    case 0x09:  // relay board kind
      if (c.len >= 2) {
        bool high = c.data[1] != 0;
        if (high != activeHigh) {
          activeHigh = high;
          prefs.putBool("high", activeHigh);
        }
        allOff();                    // re-drive every pin at the new level
        Serial.printf("  relay board now switches on with %s
", activeHigh ? "HIGH" : "LOW");
        publishInfo();
        publishState();
      }
      break;

    case 0x0A:  // everything off
      allOff();
      blink();
      publishState();
      break;

    default:    // 02, 03, 05, 06, 07: radio-only in the RF version
      break;
  }
}

void onCommandWrite(BLECharacteristic chr, const BLEConnInfo &) {
  size_t len = 0;
  const uint8_t *data = chr.getValue(&len);
  Command c;
  c.len = (uint8_t)min(len, sizeof(c.data));
  for (uint8_t i = 0; i < c.len; i++) c.data[i] = data[i];
  xQueueSend(commandQueue, &c, 0);
}

// ---------------- setup / loop ----------------
void setup() {
  prefs.begin("txrelay", false);
  activeHigh = prefs.getBool("high", true);

  // Drive every output OFF straight away (OFF level before OUTPUT mode, or
  // released for LOW-trigger boards), so no relay clicks on during boot.
  for (int i = 0; i < CHANNELS; i++) chanState[i] = 0xFF;
  for (int ch = 0; ch < OUTPUTS; ch++) writeOutput(ch, false);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  Serial.begin(115200);

  commandQueue = xQueueCreate(16, sizeof(Command));

  if (!BLE.begin(BLE_NAME)) {
    Serial.println("BLE init failed");
    while (true) delay(1000);
  }
  BLEServer server = BLE.createServer();
  server.onConnect([](BLEServer, const BLEConnInfo &) {
    clientConnected = true;
    Serial.println("phone connected");
  });
  server.onDisconnect([](BLEServer s, const BLEConnInfo &, uint8_t) {
    clientConnected = false;
    Serial.println("phone disconnected");
    s.startAdvertising();
  });

  BLEService service = server.createService(SERVICE_UUID);
  BLECharacteristic cmdChar = service.createCharacteristic(
      CMD_UUID, BLEProperty::Write | BLEProperty::WriteNR, BLEPermission::WriteOpen);
  cmdChar.onWrite(onCommandWrite);
  stateChar = service.createCharacteristic(
      STATE_UUID, BLEProperty::Read | BLEProperty::Notify, BLEPermission::ReadOpen);
  infoChar = service.createCharacteristic(INFO_UUID, BLEProperty::Read, BLEPermission::ReadOpen);

  publishState();
  publishInfo();
  server.start();

  BLEAdvertising adv = BLE.getAdvertising();
  adv.addServiceUUID(SERVICE_UUID);
  adv.setName(BLE_NAME);
  adv.setScanResponse(true);
  adv.start();

  Serial.printf("%s ready, firmware %s (relay, trigger %s)\n", BLE_NAME, FW_VERSION,
                activeHigh ? "HIGH" : "LOW");
}

void serialConsole() {
  while (Serial.available()) {
    const int k = Serial.read();
    if (k >= '1' && k <= '0' + OUTPUTS) {
      const uint8_t ch = k - '1';
      Serial.printf("console: toggle relay %d
", ch + 1);
      writeOutput(ch, chanState[ch] != 1);
      logOutput(ch);
      blink();
      publishState();
    } else if (k == '0') {
      Serial.println("console: all off");
      allOff();
      publishState();
    } else if (k == '?') {
      Serial.printf("firmware %s, relay board switches on with %s, phone %s
", FW_VERSION,
                    activeHigh ? "HIGH" : "LOW", clientConnected ? "connected" : "not connected");
      for (int ch = 0; ch < OUTPUTS; ch++) logOutput(ch);
    }
  }
}

void loop() {
  Command c;
  if (xQueueReceive(commandQueue, &c, pdMS_TO_TICKS(50)) == pdTRUE) {
    handle(c);
  }
  serialConsole();
}
