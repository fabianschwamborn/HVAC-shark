# Usage
```
cd dongle/mid-xye/py-mid-xye
python3 -m venv venv
source venv/bin/activate
# or for fish users
#source venv/bin/activate.fish
pip3 install -r requirements.txt
./py-mid-xye.py --port /dev/tty.usbserial-A50285BI
# or something like /dev/ttyUSB0 on Linux
```

Run `./py-mid-xye.py --help` for more info.
