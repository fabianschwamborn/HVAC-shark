#include <WiFi.h>
#include <WiFiAP.h>
#include <WiFiUdp.h>
#include "decode_xye.h"

#define MASTER_START_BYTE 0xAA
#define MASTER_END_BYTE 0x55
#define RCV_BUFFER_LENGTH 128
#define SEND_RECEIVE_ENABLE_485 34 //receiving when low

const char *ssid = "HVAC-Shark";
const char *password = "12345678";
const int udpPort = 22222;

HardwareSerial serialRS485(2); // Use UART2
WiFiUDP udp;

void setup() {
  Serial.begin(115200); // USB console output
  serialRS485.begin(4800, SERIAL_8N1, 16, 17); // RS232 interface (RX, TX)
  Serial.println("Hello, this is the HVAC shark for Midea"); // Hello world for serial port check

  pinMode(SEND_RECEIVE_ENABLE_485, OUTPUT); //sending currently not implemented, so fix for receiving
  digitalWrite(SEND_RECEIVE_ENABLE_485, LOW);

  // Start the Wi-Fi access point
  WiFi.softAP(ssid, password);
  Serial.println("Wi-Fi access point started");

  // Start the UDP
  udp.begin(udpPort);
  Serial.println("UDP started");
}

void loop() {
  if (serialRS485.available()) {
    decodeXYE(serialRS485, udp, udpPort);
  }
}
