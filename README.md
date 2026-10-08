# SPL Meter for foobar2000 (macOS)

A [foobar2000](https://www.foobar2000.org/mac) component for macOS that estimates
in real time the dB SPL reaching your ears, graphs it live, and warns you when you
go over 80 dB, the level associated with increased hearing-damage risk over
prolonged exposure.

![platform](https://img.shields.io/badge/platform-macOS%2011+-blue) ![CI](https://github.com/kaisan636/foo_dsp_splmeter/actions/workflows/build.yml/badge.svg)

## Why

Listening to music through headphones at high volume is one of the most common
causes of gradual hearing loss. Most players give you no idea of the actual
physical loudness. This component does the math for you:

```
voltage = DAC max output (V RMS) × system volume
power   = voltage² / headphone impedance        (mW)
SPL     = headphone sensitivity + 10·log₁₀(power) + signal RMS (dBFS)
```

It is an **estimate**, not a calibrated measurement: it depends on you entering
your headphone sensitivity, impedance, and DAC output voltage in the DSP
configuration. Good enough to know if you are in the danger zone, not good
enough for audiological work.

## Features

- Live graph of the last 10 minutes of estimated SPL (1 point per second)
- Big current-SPL readout, turns red over the threshold
- Red dashed threshold line (80 dB by default, configurable)
- Peak SPL for the session
- The DSP is 100% pass-through: it never alters the audio, only measures

## Installation

Grab `foo_dsp_splmeter.component.zip` from the
[latest release](https://github.com/kaisan636/foo_dsp_splmeter/releases), unzip it,
and drop the bundle into:

```text
~/Library/foobar2000-v2/user-components/foo_dsp_splmeter/
```

Restart foobar2000, then:

1. Enable the DSP: `Playback → DSP Manager → SPL Meter (hearing safety)`.
2. Add the panel to your layout. In `UI-Layout.txt`:

```text
splitter vertical style=thin
{
    playlist
    splmeter
}
```

## Configuration

Right-click the DSP in the chain → Configure:

| Setting | Meaning | Typical over-ear |
|---|---|---|
| Sensitivity | dB SPL at 1 kHz for 1 mW | 96-106 |
| Impedance | headphone impedance | 32 Ω |
| DAC max voltage | V RMS at 100% volume | 1.0-2.0 |
| System volume | match macOS output volume | 45% |
| Threshold | warning level | 80 dB |

Find your headphone's numbers on the spec sheet or
[rtings](https://www.rtings.com/headphones). If you don't know the DAC voltage,
leave 1.0 V and calibrate by ear: if the estimate is clearly wrong (e.g. 60 dB at
a painful volume), adjust the voltage until it roughly matches reality.

## Building from source

Requires Xcode and the
[foobar2000 SDK](https://www.foobar2000.org/SDK) (2023-09-06 or newer, the one
with macOS support) placed as `../sdk`:

```sh
xcodebuild -project foo_dsp_splmeter.xcodeproj -target foo_dsp_splmeter -configuration Release build
```

(See `.github/workflows/build.yml` for the full sequence including SDK libraries.)

CI builds the component on GitHub's macOS runners on every push and attaches the
bundle to releases automatically.

## License

MIT. foobar2000 SDK is property of Peter Pawlowski / foobar2000, used under its
redistribution terms; this repo does not vendor the SDK, it downloads the
official package at build time.

## State

The DSP itself is trivial (pass-through + RMS meter); the risky part is the macOS
UI. Report any crash with your foobar2000 version. Requires macOS 11+ and
foobar2000 v2.
