.PHONY: install connect

-include config.env

ESP32_PORT ?= /dev/ttyACM0

install:
	./install-esp32s3-linux.sh config.env

connect:
	picocom -b 115200 $(ESP32_PORT)
