# G90SDR

macOS (SwiftUI) app to control a Xiegu G90 over its CAT cable and show an audio waterfall.

## What it does
- **CAT control** (CI-V, 19200 baud, radio address `0x70`): read/set frequency, read/set mode, S-meter, band and tuning-step buttons.
- **Waterfall** (0–4 kHz): FFT of the radio's audio output captured through a sound card.

## Waterfall limitation
The G90's CAT port carries control commands only; it does not stream spectrum data. The waterfall is therefore computed from audio, using the radio's data/line-out into a sound-card input. It shows the receive passband around the tuned frequency, not a wideband scope like the radio's own display.

## Build
Needs only the Xcode Command Line Tools (no full Xcode).

    swift build            # debug build
    scripts/bundle.sh      # release build wrapped in build/G90SDR.app (needed for the microphone permission prompt)
    open build/G90SDR.app

`@State` is avoided on purpose: its macro plugin is not part of the Command Line Tools.
