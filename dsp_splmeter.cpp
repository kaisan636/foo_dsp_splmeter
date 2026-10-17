#include "stdafx.h"
#include "dsp_splmeter.h"

#include <SDK/cfg_var.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <cmath>
#include <mutex>

#ifdef __APPLE__
service_ptr ConfigureSPLMeterDSP(fb2k::hwnd_t parent, dsp_preset_edit_callback_v2::ptr callback);
#endif

namespace splmeter {
namespace {

cfg_struct_t<MeterSettings> cfg_settings(cfg_guid_v2, default_settings());
std::mutex g_settings_mutex;
std::once_flag g_settings_loaded;
MeterSettings g_cached_settings = default_settings();
std::atomic<t_uint64> g_settings_generation { 1 };

void ensure_settings_loaded() {
    std::call_once(g_settings_loaded, [] {
        std::lock_guard<std::mutex> lock(g_settings_mutex);
        g_cached_settings = cfg_settings.get();
    });
}

// ---- shared meter state ----
std::mutex g_meter_mutex;
MeterState g_meter_state;
std::deque<float> g_second_accum;   // RMS per second for history (ring)
std::atomic<unsigned> g_second_rate { 0 };
double g_second_sum = 0.0;
t_uint64 g_second_samples = 0;
double g_second_power = 0.0;

// Wall clock for ballistics / dose integration
std::chrono::steady_clock::time_point g_last_frame = std::chrono::steady_clock::now();
bool g_have_last_frame = false;

}

MeterSettings default_settings() {
    MeterSettings s;
    s.sensitivityDbSPL = 96.0;
    s.impedanceOhms = 80.0;
    s.dacMaxVoltageRMS = 1.0;   // unknown until measured; calibrate with a 1 kHz 0 dBFS tone
    s.systemVolumePercent = 100.0;
    s.thresholdDbSPL = 80.0;
    s.enabled = true;
    return s;
}

MeterSettings get_settings() {
    ensure_settings_loaded();
    std::lock_guard<std::mutex> lock(g_settings_mutex);
    return g_cached_settings;
}

void set_settings(const MeterSettings & settings) {
    ensure_settings_loaded();
    MeterSettings clipped = settings;
    clipped.sensitivityDbSPL = std::clamp(clipped.sensitivityDbSPL, 60.0, 140.0);
    clipped.impedanceOhms = std::clamp(clipped.impedanceOhms, 4.0, 600.0);
    clipped.dacMaxVoltageRMS = std::clamp(clipped.dacMaxVoltageRMS, 0.05, 10.0);
    clipped.systemVolumePercent = std::clamp(clipped.systemVolumePercent, 0.0, 100.0);
    clipped.thresholdDbSPL = std::clamp(clipped.thresholdDbSPL, 40.0, 120.0);
    clipped.themeIndex = std::clamp(clipped.themeIndex, 0, splmeter::theme_count - 1);
    {
        std::lock_guard<std::mutex> lock(g_settings_mutex);
        g_cached_settings = clipped;
    }
    g_settings_generation.fetch_add(1, std::memory_order_release);
    cfg_settings = clipped;
}

t_uint64 get_settings_generation() {
    ensure_settings_loaded();
    return g_settings_generation.load(std::memory_order_acquire);
}

void make_preset(dsp_preset & out) {
    dsp_preset_builder builder;
    builder << (t_uint32) 1;
    builder.finish(dsp_guid, out);
}

// Estimate SPL, identical to the user's reference formula:
//   SPL_ref = S + 30 + 20*log10(V_FS) - 10*log10(Z)
//   SPL     = SPL_ref + L + G_dig - A_vol
// where L + G_dig is the post-DSP-chain RMS (this DSP sits after EQ/preamp/
// ReplayGain, so digital gain is already in the measurement) and
// A_vol = -20*log10(volume). Expanding:
//   S + 10*log10(1000 * (V_FS*vol)^2 / Z) + L  ==  SPL_ref + L - A_vol
double estimate_spl(const MeterSettings & s, double rmsDbFS) {
    const double vol = std::clamp(s.systemVolumePercent, 0.0, 100.0) / 100.0;
    const double voltage = s.dacMaxVoltageRMS * vol;
    if (voltage <= 0.0 || s.impedanceOhms <= 0.0) return 0.0;
    const double powermW = (voltage * voltage / s.impedanceOhms) * 1000.0;
    const double splFull = s.sensitivityDbSPL + 10.0 * std::log10(powermW);
    return splFull + rmsDbFS;   // rmsDbFS is negative, lowers the level
}

MeterState get_meter_state() {
    std::lock_guard<std::mutex> lock(g_meter_mutex);
    return g_meter_state;
}

void push_meter_frame(double rmsDbFS, double peakDbFS, double spl) {
    std::lock_guard<std::mutex> lock(g_meter_mutex);

    // Frame delta for ballistics and dose integration
    const auto now = std::chrono::steady_clock::now();
    double dt = 0.0;
    if (g_have_last_frame) {
        dt = std::chrono::duration<double>(now - g_last_frame).count();
    }
    g_last_frame = now;
    g_have_last_frame = true;
    if (dt <= 0.0) dt = 0.0;
    if (dt > 1.0) dt = 1.0;   // ignore huge gaps (playback paused, etc.)

    g_meter_state.rmsDbFS = rmsDbFS;
    g_meter_state.peakDbFS = peakDbFS;
    g_meter_state.estimatedSPL = spl;
    g_meter_state.estimatedPeakSPL = std::max(g_meter_state.estimatedPeakSPL, spl);
    g_meter_state.overThreshold = spl >= g_cached_settings.thresholdDbSPL;

    // Meter ballistics: fast attack (0.5/frame), slow release (0.08/frame).
    // Frame-rate normalized so it behaves the same at any chunk size.
    const double cur = g_meter_state.displaySPL;
    const double alpha = (spl > cur) ? 0.5 : 0.08;
    const double blend = 1.0 - std::pow(1.0 - alpha, dt * 60.0);
    g_meter_state.displaySPL = cur + (spl - cur) * blend;

    // Peak hold: latch new peaks, hold 1.5 s, then fall at 15 dB/s down to the
    // current level. Same falling-peak-cap feel as the JendaT spectrum bars.
    if (spl >= g_meter_state.peakHoldSPL) {
        g_meter_state.peakHoldSPL = spl;
        g_meter_state.peakHoldAge = 0.0;
    } else {
        g_meter_state.peakHoldAge += dt;
        if (g_meter_state.peakHoldAge > 1.5) {
            const double fallen = g_meter_state.peakHoldSPL - dt * 15.0;
            g_meter_state.peakHoldSPL = std::max(fallen, g_meter_state.displaySPL);
        }
    }

    // NIOSH hearing dose: 100 % = 8 h at 85 dB SPL, 3 dB exchange rate.
    //   T(spl) hours = 8 / 2^((spl - 85) / 3);  dose% += dt/T * 100
    // Below 70 dB the allowed time exceeds a day, so integration is negligible.
    if (spl >= 70.0 && dt > 0.0) {
        const double allowedHours = 8.0 / std::pow(2.0, (spl - 85.0) / 3.0);
        if (allowedHours > 0.0) {
            g_meter_state.dosePercent += (dt / 3600.0) / allowedHours * 100.0;
        }
    }

    // Rough Leq-style accumulation (kept for compatibility)
    if (spl > 0.0) {
        const double excess = spl - 80.0;
        g_meter_state.laeqSeconds += std::pow(10.0, excess / 10.0) * dt;
    }

    // 1 Hz history
    const unsigned sampleRate = g_second_rate.load(std::memory_order_relaxed);
    if (sampleRate > 0) {
        g_second_power += std::pow(10.0, rmsDbFS / 10.0);
        g_second_samples += sampleRate;
        if (g_second_samples >= sampleRate) {
            const double secRms = 10.0 * std::log10(std::max(g_second_power / (double)g_second_samples, 1e-12));
            const MeterSettings s = g_cached_settings;
            const double secSPL = (float) estimate_spl(s, secRms);
            g_meter_state.historySPL[g_meter_state.historyCount % history_length] = (float) secSPL;
            g_meter_state.historyCount++;
            g_second_power = 0.0;
            g_second_samples = 0;
        }
    }
}

void reset_exposure() {
    std::lock_guard<std::mutex> lock(g_meter_mutex);
    g_meter_state.estimatedPeakSPL = 0.0;
    g_meter_state.laeqSeconds = 0.0;
    g_meter_state.dosePercent = 0.0;
    g_meter_state.peakHoldSPL = 0.0;
    g_meter_state.peakHoldAge = 0.0;
    g_meter_state.historyCount = 0;
}

}

// ---- The DSP itself: completely pass-through, only measures ----
class dsp_splmeter_impl : public dsp_impl_base {
public:
    dsp_splmeter_impl(const dsp_preset &) {}

    static GUID g_get_guid() { return splmeter::dsp_guid; }
    static void g_get_name(pfc::string_base & out) { out = "SPL Meter (hearing safety)"; }

    bool on_chunk(audio_chunk * chunk, abort_callback &) {
        if (chunk->is_empty()) return true;
        const splmeter::MeterSettings settings = splmeter::get_settings();
        if (!settings.enabled) return true;

        const unsigned sampleRate = chunk->get_sample_rate();
        if (sampleRate != m_sampleRate) {
            m_sampleRate = sampleRate;
            splmeter::g_second_rate.store(sampleRate, std::memory_order_relaxed);
        }

        const audio_sample * data = chunk->get_data();
        const t_size frames = chunk->get_sample_count();
        const unsigned channels = chunk->get_channels();
        if (frames == 0 || channels == 0) return true;

        double sumSq = 0.0;
        audio_sample peak = 0;
        const t_size total = frames * channels;
        for (t_size i = 0; i < total; ++i) {
            const double v = data[i];
            sumSq += v * v;
            const audio_sample a = (audio_sample) std::fabs((double) v);
            if (a > peak) peak = a;
        }
        const double rms = std::sqrt(sumSq / (double) total);
        const double rmsDbFS = 20.0 * std::log10(std::max(rms, 1e-9));
        const double peakDbFS = 20.0 * std::log10(std::max((double) peak, 1e-9));
        const double spl = splmeter::estimate_spl(settings, rmsDbFS);
        splmeter::push_meter_frame(rmsDbFS, peakDbFS, spl);
        return true;   // pass through untouched
    }

    void on_endofplayback(abort_callback &) {}
    void on_endoftrack(abort_callback &) {}
    void flush() {}
    double get_latency() { return 0; }
    bool need_track_change_mark() { return false; }

    static bool g_get_default_preset(dsp_preset & out) {
        splmeter::make_preset(out);
        return true;
    }

#ifdef __APPLE__
    static service_ptr g_show_config_popup(fb2k::hwnd_t parent, dsp_preset_edit_callback_v2::ptr callback) {
        return ConfigureSPLMeterDSP(parent, callback);
    }
#endif
    static bool g_have_config_popup() { return true; }

private:
    unsigned m_sampleRate = 0;
};

static dsp_factory_t<dsp_splmeter_impl> g_dsp_splmeter_factory;
