#include "decode_xye.h"

#define MASTER_START_BYTE 0xAA
#define MASTER_END_BYTE 0x55
#define RCV_BUFFER_LENGTH 128

static bool receivingRS485Sequence = false;
static uint8_t buffer[RCV_BUFFER_LENGTH];
static uint8_t rcvByteCount = 0;

void decodeXYE(HardwareSerial &rs485, WiFiUDP &udp, int udpPort) {
  uint8_t byteReceived = rs485.read();

  if (receivingRS485Sequence) {
    buffer[rcvByteCount++] = byteReceived;
    
    switch (byteReceived) {
      case MASTER_END_BYTE:
        printBuffer(buffer, rcvByteCount);
        sendBufferUDP(udp, buffer, rcvByteCount, udpPort);
        receivingRS485Sequence = false;
        rcvByteCount = 0;
        break;

      case MASTER_START_BYTE:
        printBuffer(buffer, rcvByteCount);
        sendBufferUDP(udp, buffer, rcvByteCount, udpPort);
        receivingRS485Sequence = true; // Start a new frame
        rcvByteCount = 0;
        buffer[rcvByteCount++] = byteReceived;
        break;

      case RCV_BUFFER_LENGTH - 1:
        Serial.print("Frame error: Data length exceeded. Data received: ");
        printBuffer(buffer, rcvByteCount);
        sendBufferUDP(udp, buffer, rcvByteCount, udpPort);
        receivingRS485Sequence = false;
        rcvByteCount = 0;
        break;

      case MASTER_START_BYTE:
        receivingRS485Sequence = true;
        rcvByteCount = 0;
        buffer[rcvByteCount++] = byteReceived;    
        break;4

      default:
        break;
   }
  } 
}
void printBuffer(uint8_t *buffer, uint8_t length) {
  for (uint8_t i = 0; i < length; i++) {
    if (buffer[i] < 0x10) {
      Serial.print("0"); // Add leading zero for single digit hex values
    }
    Serial.print(buffer[i], HEX);
    Serial.print(" ");
  }
  Serial.println();
}

void sendBufferUDP(WiFiUDP &udp, uint8_t *buffer, uint8_t length, int udpPort) { 
  udp.beginPacket("255.255.255.255", udpPort);
  udp.write((const uint8_t *)"HVAC_shark", 10); //start sequence
  udp.write(1); // manufacturer: 1 for Midea
  udp.write(0); // bus type: 0 for XYE bus
  udp.write(0); // reserved
  udp.write(buffer, length);
  udp.endPacket(); 
}