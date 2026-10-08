#include "stdafx.h"

DECLARE_COMPONENT_VERSION(
    "SPL Meter",
    "1.0.0",
    "Real-time dB SPL estimator with live graph for foobar2000 macOS. Helps keep listening below 80 dB to protect hearing. Pass-through DSP: does not alter audio."
);

VALIDATE_COMPONENT_FILENAME("foo_dsp_splmeter.component");

FOOBAR2000_IMPLEMENT_CFG_VAR_DOWNGRADE;
