#ifndef DECODE_XYE_H
#define DECODE_XYE_H

#include <Arduino.h>
#include <HardwareSerial.h>
#include <WiFiUdp.h>

void decodeXYE(HardwareSerial &serial, WiFiUDP &udp, int udpPort);
void printBuffer(uint8_t *buffer, uint8_t length);
void sendBufferUDP(WiFiUDP &udp, uint8_t *buffer, uint8_t length, int udpPort);

#endif
