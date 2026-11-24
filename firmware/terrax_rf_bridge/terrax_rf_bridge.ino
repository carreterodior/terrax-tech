/*
  TERRAX Wireless Switch (RF bridge) — ESP32 firmware
  ---------------------------------
  Turns Bluetooth LE commands from the TERRAX TECH app into 433 MHz
  EV1527-style codes, so cheap 433 MHz relay modules (the "learning code"
  kind) can switch auxiliary lights from the phone.

  Hardware (see the wiring page):
    ESP32 (ESP-32S / WROOM-32 dev board)
    FS1000A 433 MHz transmitter: VCC -> 5 V, GND -> GND, DATA -> GPIO4 (D4)
    17.3 cm straight wire on the FS1000A ANT pad
    On-board LED (GPIO2) blinks while transmitting.

  Needs only the "esp32 by Espressif Systems" board package, version 4.x,
  in the Arduino IDE (Tools > Board > Boards Manager). No extra libraries.
  Uses the 4.x unified BLE API (#include <BLE.h>).

  How codes work
  --------------
  Every channel (0–15) has its own 20-bit address, derived from this
  board's MAC so two bridges never clash. A frame is 24 bits:
  20 address bits + 4 key bits. ON and OFF use different key bits
  (default ON = 0x1, OFF = 0x2, changeable per channel). Each command is
  sent as 12 repeated frames. A switch module "learns" a channel when it is
  in learn mode and receives that channel's code (the app's Pair button).

  Bluetooth protocol (all values are raw bytes)
  ---------------------------------------------
  Service        54580001-7e2a-4f3c-9b1a-5445525241ff   ("TX" = TERRAX)
  Command (write) 54580002-...   write one of:
     01 ch st          set channel ch (0–15) ON (st=1) or OFF (st=0)
     02 ch             pair: send ch's ON code for ~3 s (receiver in learn mode)
     03 ch             pair OFF code for ~3 s (receivers that learn OFF separately)
     04 ch n gap10ms   pulse: n quick OFF→ON cycles, gap in 10 ms steps
                       (for lamps that change colour on a quick power cycle)
     05 a2 a1 a0 k     send a raw 24-bit code: 20-bit address a2a1a0 (top 4 bits of
                       a2 ignored) + key k, e.g. to replay an existing fob's code
     06 hi lo          set the base pulse length in µs (default 350, range 150–1000)
     07 ch on off      set the ON and OFF key nibbles for channel ch
     08 ch            forget channel ch's state (marks it unknown)
  State (read/notify) 54580003-...   16 bytes, one per channel:
     0 = OFF, 1 = ON, 0xFF = unknown (radio is one-way: last command sent)
  Info (read)         54580004-...   text: firmware version, pulse length, MAC

  Safety: commands arrive from any phone that connects. Bluetooth pairing /
  bonding is a planned next step before this ships to customers.
*/

#include <Arduino.h>
#include <BLE.h>
#include <Preferences.h>

// ---------------- configuration ----------------
static const char *FW_VERSION = "1.0.0";
static const char *BLE_NAME = "TERRAX WIRELESS SWITCH";
static const int TX_PIN = 4;        // D4 -> FS1000A DATA
static const int LED_PIN = 2;       // on-board blue LED on most ESP32 dev boards
static const int CHANNELS = 16;
static const int REPEATS = 12;      // frames per command
static const uint32_t PAIR_MS = 3000;

static const BLEUUID SERVICE_UUID("54580001-7e2a-4f3c-9b1a-5445525241ff");
static const BLEUUID CMD_UUID("54580002-7e2a-4f3c-9b1a-5445525241ff");
static const BLEUUID STATE_UUID("54580003-7e2a-4f3c-9b1a-5445525241ff");
static const BLEUUID INFO_UUID("54580004-7e2a-4f3c-9b1a-5445525241ff");

// ---------------- persistent settings ----------------
Preferences prefs;
uint16_t pulseUs = 350;             // EV1527 base period T
uint8_t keyOn[CHANNELS];
uint8_t keyOff[CHANNELS];
uint8_t chanState[CHANNELS];        // 0 off, 1 on, 0xFF unknown
uint32_t baseAddress = 0;           // 20-bit, from MAC

// ---------------- BLE objects ----------------
BLECharacteristic stateChar;
BLECharacteristic infoChar;
volatile bool clientConnected = false;

// Commands are queued from the BLE callback (BLE task) and transmitted in
// loop(), so radio timing never runs inside the Bluetooth stack.
struct Command {
  uint8_t len;
  uint8_t data[8];
};
QueueHandle_t commandQueue;

// ---------------- 433 MHz EV1527 transmitter ----------------
// Bit 0: high 1T, low 3T. Bit 1: high 3T, low 1T. Sync: high 1T, low 31T.
static inline void txPulse(uint16_t highT, uint16_t lowT) {
  digitalWrite(TX_PIN, HIGH);
  delayMicroseconds(pulseUs * highT);
  digitalWrite(TX_PIN, LOW);
  delayMicroseconds(pulseUs * lowT);
}

void sendFrame(uint32_t code24) {
  txPulse(1, 31);                         // sync / preamble
  for (int i = 23; i >= 0; i--) {
    if (code24 & (1UL << i)) txPulse(3, 1);
    else txPulse(1, 3);
  }
}

void sendCode(uint32_t code24, int repeats) {
  digitalWrite(LED_PIN, HIGH);
  for (int r = 0; r < repeats; r++) sendFrame(code24);
  txPulse(1, 31);                         // trailing sync closes the last frame
  digitalWrite(TX_PIN, LOW);
  digitalWrite(LED_PIN, LOW);
}

uint32_t channelCode(uint8_t ch, bool on) {
  uint32_t addr = (baseAddress ^ ((uint32_t)ch * 0x9E37UL)) & 0xFFFFFUL;
  uint8_t key = (on ? keyOn[ch] : keyOff[ch]) & 0x0F;
  return (addr << 4) | key;
}

// ---------------- state reporting ----------------
void publishState() {
  if (!stateChar) return;
  stateChar.setValue(chanState, CHANNELS);
  if (clientConnected) stateChar.notify();
}

void publishInfo() {
  if (!infoChar) return;
  char buf[96];
  uint64_t mac = ESP.getEfuseMac();
  snprintf(buf, sizeof(buf), "TERRAX Wireless Switch %s; pulse %u us; mac %04X%08lX",
           FW_VERSION, pulseUs, (uint16_t)(mac >> 32), (unsigned long)mac);
  infoChar.setValue((const uint8_t *)buf, strlen(buf));
}

void saveChannel(uint8_t ch) {
  char k[8];
  snprintf(k, sizeof(k), "on%u", ch);  prefs.putUChar(k, keyOn[ch]);
  snprintf(k, sizeof(k), "off%u", ch); prefs.putUChar(k, keyOff[ch]);
  snprintf(k, sizeof(k), "st%u", ch);  prefs.putUChar(k, chanState[ch]);
}

// ---------------- command handling (runs in loop) ----------------
void handle(const Command &c) {
  if (c.len == 0) return;
  const uint8_t op = c.data[0];
  const uint8_t ch = c.len > 1 ? c.data[1] : 0;
  const bool chOk = ch < CHANNELS;

  switch (op) {
    case 0x01:  // set ON/OFF
      if (c.len >= 3 && chOk) {
        bool on = c.data[2] != 0;
        sendCode(channelCode(ch, on), REPEATS);
        chanState[ch] = on ? 1 : 0;
        saveChannel(ch);
        publishState();
      }
      break;

    case 0x02:  // pair ON code
    case 0x03:  // pair OFF code
      if (c.len >= 2 && chOk) {
        uint32_t code = channelCode(ch, op == 0x02);
        uint32_t until = millis() + PAIR_MS;
        while ((int32_t)(until - millis()) > 0) {
          sendCode(code, 4);
          delay(20);
        }
      }
      break;

    case 0x04:  // pulse OFF->ON n times (colour stepping)
      if (c.len >= 4 && chOk) {
        uint8_t n = c.data[2] ? c.data[2] : 1;
        uint16_t gap = (uint16_t)c.data[3] * 10;
        for (uint8_t i = 0; i < n; i++) {
          sendCode(channelCode(ch, false), 6);
          delay(gap);
          sendCode(channelCode(ch, true), 6);
          delay(gap);
        }
        chanState[ch] = 1;
        saveChannel(ch);
        publishState();
      }
      break;

    case 0x05:  // raw 24-bit code
      if (c.len >= 5) {
        uint32_t addr = (((uint32_t)c.data[1] << 16) | ((uint32_t)c.data[2] << 8) | c.data[3]) & 0xFFFFFUL;
        sendCode((addr << 4) | (c.data[4] & 0x0F), REPEATS);
      }
      break;

    case 0x06:  // pulse length
      if (c.len >= 3) {
        uint16_t t = ((uint16_t)c.data[1] << 8) | c.data[2];
        if (t >= 150 && t <= 1000) {
          pulseUs = t;
          prefs.putUShort("pulse", pulseUs);
          publishInfo();
        }
      }
      break;

    case 0x07:  // key nibbles for a channel
      if (c.len >= 4 && chOk) {
        keyOn[ch] = c.data[2] & 0x0F;
        keyOff[ch] = c.data[3] & 0x0F;
        saveChannel(ch);
      }
      break;

    case 0x08:  // forget state
      if (c.len >= 2 && chOk) {
        chanState[ch] = 0xFF;
        saveChannel(ch);
        publishState();
      }
      break;
  }
}

// ---------------- BLE callbacks ----------------
// Runs on the BLE task: copy the bytes and queue them for loop().
void onCommandWrite(BLECharacteristic chr, const BLEConnInfo &) {
  size_t len = 0;
  const uint8_t *data = chr.getValue(&len);
  Command c;
  c.len = (uint8_t)min(len, sizeof(c.data));
  for (uint8_t i = 0; i < c.len; i++) c.data[i] = data[i];
  xQueueSend(commandQueue, &c, 0);    // drop if the queue is full
}

// ---------------- setup / loop ----------------
void setup() {
  pinMode(TX_PIN, OUTPUT);
  digitalWrite(TX_PIN, LOW);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  Serial.begin(115200);

  commandQueue = xQueueCreate(16, sizeof(Command));

  prefs.begin("txrf", false);
  pulseUs = prefs.getUShort("pulse", 350);
  for (int ch = 0; ch < CHANNELS; ch++) {
    char k[8];
    snprintf(k, sizeof(k), "on%d", ch);  keyOn[ch] = prefs.getUChar(k, 0x1);
    snprintf(k, sizeof(k), "off%d", ch); keyOff[ch] = prefs.getUChar(k, 0x2);
    snprintf(k, sizeof(k), "st%d", ch);  chanState[ch] = prefs.getUChar(k, 0xFF);
  }

  uint64_t mac = ESP.getEfuseMac();
  baseAddress = (uint32_t)((mac ^ (mac >> 20) ^ (mac >> 40)) & 0xFFFFFUL);

  // Shown when scanning for Bluetooth devices. Several bridges share this
  // name; the app tells them apart by their Bluetooth address.
  const char *name = BLE_NAME;
  if (!BLE.begin(name)) {
    Serial.println("BLE init failed");
    while (true) delay(1000);
  }
  BLEServer server = BLE.createServer();
  server.onConnect([](BLEServer, const BLEConnInfo &) { clientConnected = true; });
  server.onDisconnect([](BLEServer s, const BLEConnInfo &, uint8_t) {
    clientConnected = false;
    s.startAdvertising();               // stay discoverable
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
  adv.setName(name);
  adv.setScanResponse(true);            // name goes in the scan response
  adv.start();

  Serial.printf("%s ready, firmware %s\n", name, FW_VERSION);
}

void loop() {
  Command c;
  if (xQueueReceive(commandQueue, &c, pdMS_TO_TICKS(50)) == pdTRUE) {
    handle(c);
  }
}
