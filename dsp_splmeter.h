#pragma once

#include <array>
#include <deque>

namespace splmeter {

// ---- GUIDs (regenerate if you fork this) ----
static constexpr GUID dsp_guid = { 0x7e4c21a3, 0x5b8f, 0x4d92, { 0xa1, 0x63, 0x2f, 0x88, 0xc4, 0x51, 0xe7, 0x0d } };
static constexpr GUID cfg_guid = { 0x3a9f5e82, 0x1c4d, 0x4b67, { 0x9e, 0x20, 0x7a, 0xd3, 0xf6, 0x18, 0xb5, 0x4c } };
static constexpr GUID cfg_guid_v2 = { 0x5d8b70f4, 0x9e2a, 0x4c13, { 0x8b, 0x76, 0x41, 0xc5, 0xe9, 0x0a, 0xd2, 0x6f } };
static constexpr GUID ui_guid = { 0x8f2a63d1, 0x47b9, 0x4e05, { 0xc3, 0x91, 0x58, 0xd6, 0xa2, 0xb7, 0xf4, 0x1e } };

// ---- Calibration settings (user editable) ----
struct MeterSettings {
    // Sensitivity of the headphones: dB SPL at 1 kHz for 1 mW input
    double sensitivityDbSPL = 96.0;    // user's headphones (~96 dB, verify vs 80 vs 250 ohm unit)
    // Impedance in ohms (used for voltage -> power conversion)
    double impedanceOhms = 80.0;       // user's unit is 80 ohm (250 ohm variant also exists)
    // Max output voltage of the DAC/headphone amp, V RMS at 100% volume (0 dBFS tone)
    // Unknown for the user's DAC: calibrate with a 1 kHz 0 dBFS tone + multimeter.
    double dacMaxVoltageRMS = 1.0;
    // Volume attenuation, as a percent (0-100). A_vol = -20*log10(percent/100).
    // foobar2000 can't read the Mac's system volume reliably, so the user sets it here.
    double systemVolumePercent = 100.0;
    // Safety threshold
    double thresholdDbSPL = 80.0;
    // Meter smoothing / history
    bool enabled = true;               // meter active (DSP itself is pass-through)
};

static constexpr size_t history_length = 600; // seconds of 1Hz history

struct MeterState {
    // Written by DSP thread, read by UI thread. Guarded by mutex.
    double rmsDbFS = -120.0;          // current RMS of the signal (dBFS)
    double peakDbFS = -120.0;
    double estimatedSPL = 0.0;        // current estimated dB SPL
    double estimatedPeakSPL = 0.0;    // peak SPL since playback start
    double laeqSeconds = 0.0;         // time-integrated Leq exposure seconds at current level
    bool overThreshold = false;
    double historySPL[history_length] = {};
    size_t historyCount = 0;          // how many entries are valid (most recent at end)
};



MeterSettings default_settings();
MeterSettings get_settings();
void set_settings(const MeterSettings & settings);
t_uint64 get_settings_generation();
void make_preset(dsp_preset & out);

// Shared meter state, thread-safe
MeterState get_meter_state();
void push_meter_frame(double rmsDbFS, double peakDbFS, double spl);

}
