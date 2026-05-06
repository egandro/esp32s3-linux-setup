.PHONY: connect

-include config.env

ESP32_PORT ?= /dev/ttyACM0

connect:
	picocom -b 115200 $(ESP32_PORT)
