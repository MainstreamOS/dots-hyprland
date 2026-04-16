#!/bin/bash

# Generic Bluetooth auto-connect script
# Connects to all trusted Bluetooth devices when run

sleep 4

for dev in $(bluetoothctl devices Trusted | awk '{print $2}'); do
    bluetoothctl -- connect "$dev" &
done
