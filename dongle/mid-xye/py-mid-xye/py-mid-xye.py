#!/usr/bin/env python3

import socket
import argparse

# Import pyserial with error handling
try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("PySerial not installed correctly. Please install with: pip install pyserial")
    import sys

    sys.exit(1)

# Constants
MASTER_START_BYTE = 0xAA
MASTER_END_BYTE = 0x55
RCV_BUFFER_LENGTH = 128
UDP_PORT = 22222


class RS485Decoder:
    def __init__(self, serial_port, udp_host, udp_port=UDP_PORT):
        self.serial = serial_port
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp_host = udp_host
        self.udp_port = udp_port
        self.receiving_sequence = False
        self.buffer = bytearray()

    def process_byte(self, byte):
        if self.receiving_sequence:
            self.buffer.append(byte)

            if byte == MASTER_END_BYTE:
                self.print_buffer()
                self.send_buffer_udp()
                self.receiving_sequence = False
                self.buffer = bytearray()

            elif byte == MASTER_START_BYTE:
                self.print_buffer()
                self.send_buffer_udp()
                self.receiving_sequence = True
                self.buffer = bytearray([byte])

            elif len(self.buffer) >= RCV_BUFFER_LENGTH - 1:
                print("Frame error: Data length exceeded. Data received: ", end="")
                self.print_buffer()
                self.send_buffer_udp()
                self.receiving_sequence = False
                self.buffer = bytearray()

        elif byte == MASTER_START_BYTE:
            self.receiving_sequence = True
            self.buffer = bytearray([byte])

    def print_buffer(self):
        for b in self.buffer:
            print(f"{b:02X} ", end="")
        print()

    def send_buffer_udp(self):
        # Format the packet exactly as in the Arduino code
        packet = bytearray(b"HVAC_shark")  # Start sequence
        packet.append(1)  # Manufacturer: 1 for Midea
        packet.append(0)  # Bus type: 0 for XYE bus
        packet.append(0)  # Reserved
        packet.extend(self.buffer)

        self.udp_socket.sendto(packet, (self.udp_host, self.udp_port))

    def run(self):
        try:
            while True:
                if self.serial.in_waiting > 0:
                    byte = ord(self.serial.read(1))
                    self.process_byte(byte)
        except KeyboardInterrupt:
            print("\nExiting...")


def list_available_ports():
    try:
        ports = list_ports.comports()
        if not ports:
            return "No serial ports found"
        return "\n".join(f"{port.device}: {port.description}" for port in ports)
    except Exception as e:
        return f"Error listing ports: {str(e)}"


def main():
    parser = argparse.ArgumentParser(description="Midea XYE RS485 to UDP Bridge")
    parser.add_argument(
        "--port", type=str, help="Serial port (e.g., COM3 or /dev/ttyUSB0)"
    )
    parser.add_argument(
        "--baud", type=int, default=4800, help="Baud rate (default: 4800)"
    )
    parser.add_argument(
        "--udp-host",
        type=str,
        default="127.0.0.1",
        help="UDP target host (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--udp-port", type=int, default=UDP_PORT, help=f"UDP port (default: {UDP_PORT})"
    )
    parser.add_argument(
        "--list-ports", action="store_true", help="List available serial ports"
    )
    args = parser.parse_args()

    if args.list_ports:
        print("Available serial ports:")
        print(list_available_ports())
        return

    if not args.port:
        print(
            "Error: Serial port is required. Use --list-ports to see available ports."
        )
        return

    try:
        ser = serial.Serial(args.port, args.baud, timeout=1)
        print(f"Connected to {args.port} at {args.baud} baud")
        print(f"Sending UDP packets to {args.udp_host}:{args.udp_port}")
        print("Press Ctrl+C to exit")

        decoder = RS485Decoder(ser, args.udp_host, args.udp_port)
        decoder.run()

    except Exception as e:
        print(f"Error: {e}")
    finally:
        if "ser" in locals() and hasattr(ser, "is_open") and ser.is_open:
            ser.close()


if __name__ == "__main__":
    main()
