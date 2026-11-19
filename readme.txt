# Armed TTL-Triggered Audio Playback Controller

## Overview
MATLAB-based stimulus playback controller using a National Instruments (NI) DAQ device. The application waits for an external TTL trigger, plays a selected WAV audio stimulus through an analog output, and simultaneously activates a digital LED signal.

After playback, the system resets its outputs and automatically re-arms for the next trigger.

## Hardware Configuration

| Connection | NI DAQ Channel | Function |
|---|---|---|
| Audio Output | PXI1Slot3/ao0 | Analog WAV stimulus |
| LED Output | PXI1Slot3/Port0/Line0 | Digital HIGH during playback |
| Trigger Input | PXI1Slot3/PFI0 | External TTL trigger |

**Default trigger:** Falling edge (HIGH → LOW).

Actual connector pin assignments should be verified against the specific NI hardware.

## Operation
1. Select a WAV file from the configured directory.
2. Normalize and scale audio to the configured peak voltage.
3. Identify and print sound segment onset/offset times.
4. Prepare audio and LED signals for synchronized DAQ output.
5. Arm the system and wait for an external TTL.
6. On triggering, play the audio while setting the LED HIGH.
7. Return the audio output to 0 V and LED to LOW after playback.
8. Automatically re-arm for the next trigger.
9. Press **STOP ARMED TRIGGER** to finish and release DAQ resources.

## Default Settings

| Parameter | Default |
|---|---|
| Playback duration | 1 second |
| Duration override | Enabled |
| Audio peak voltage | ±0.4 V |
| Trigger edge | Falling |
| Triggers per DAQ run | 1 |
| Trigger timeout | 1000 ms |
| WAV directory | Current MATLAB folder |

When the duration override is enabled, longer recordings are truncated and shorter recordings are padded with zeros. Disabling it plays the full recording.

Stereo WAV files use the left channel only.

## Requirements
- MATLAB
- Data Acquisition Toolbox with support for the legacy session-based API
- Compatible National Instruments DAQ hardware and drivers
- WAV stimulus file
- External TTL trigger source
- Appropriate analog output and LED interface circuitry

## Configuration
Edit the **USER SETTINGS** section at the beginning of `ArmedCuePlaybackController.m` to configure the NI device, channels, trigger polarity, playback duration, and voltage.

The output sample rate follows the selected WAV file and must be supported by the NI hardware.

## Notes
- Audio and LED outputs are queued together for synchronized playback.
- Sound segment detection is informational; it does not automatically change playback timing.
- The stop control is processed between blocking acquisition calls.
- No trial-by-trial data file is exported; playback counts and timing information are printed in MATLAB.
- Confirm audio voltage, digital output compatibility, and trigger behavior with the actual experimental equipment.

## Status
**Research prototype — hardware timing and output validation required.**
