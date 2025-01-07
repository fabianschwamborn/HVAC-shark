# Getting Started

To use the HVAC-shark dissector:

1. Copy the `hvac-shark.lua` script to your Wireshark plugins directory.
  
- Alternative: On Linux, you can use symbolic links to load the new dissector without restarting Wireshark:
    - `ln -sf /path/to/your/dissector /path/to/wireshark/plugins/`
- On Windows, you can create a symbolic link using the command prompt:
    - `cmd /c mklink /D "C:\path\to\wireshark\plugins\your_dissector" "C:\path\to\your\dissector"`
2. Restart Wireshark to load the new dissector.
3. Open a capture file from the `captures` folder to see the dissector in action.
