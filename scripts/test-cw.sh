#!/bin/sh
# Decodes synthetic Morse (10-30 WPM, with noise) through CWDemodulator and checks the text.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
swiftc -O -o "$OUT/cwtest" Tests/CWDecoderCheck/main.swift Sources/G90SDR/CWDemodulator.swift
"$OUT/cwtest"
