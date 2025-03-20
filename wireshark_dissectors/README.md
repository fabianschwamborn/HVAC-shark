# Getting Started

To use the HVAC-shark dissector:

1. Copy the `hvac-shark.lua` script to your Wireshark plugins directory. This can be identified via Wireshark > About > Folders.
- Alternative: On Linux, you can use symbolic links to load the new dissector without restarting Wireshark:
    - `ln -sf /path/to/your/dissector /path/to/wireshark/plugins/`
- On Windows, you can create a symbolic link using the command prompt:
    - `cmd /c mklink /D "C:\path\to\wireshark\plugins\your_dissector" "C:\path\to\your\dissector"`
- On macOS (symlinks didn't work properly when tested)
    - `mkdir ~/.local/lib/wireshark/plugins`
    - `cp HVAC-shark_mid-xye.lua ~/.local/lib/wireshark/plugins/`

2. Restart Wireshark to load the new dissector.
3. Open a capture file from the `captures` folder to see the dissector in action.
- Or, run a real time capture with a filter for `port 22222`
