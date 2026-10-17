#include "stdafx.h"

DECLARE_COMPONENT_VERSION(
    "SPL Meter",
    "1.1.0",
    "Hearing safety meter for foobar2000 macOS: estimated dB SPL with smoothed ballistics, "
    "falling peak hold, 10-minute history graph, NIOSH-style daily dose, themed light/dark UI, "
    "and a pulsing alert when you go over your limit. "
    "The DSP is strictly pass-through: it reads samples to measure but never writes or modifies them, "
    "so the audio output is bit-identical with the component active."
);

VALIDATE_COMPONENT_FILENAME("foo_dsp_splmeter.component");

FOOBAR2000_IMPLEMENT_CFG_VAR_DOWNGRADE;
