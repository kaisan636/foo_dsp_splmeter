//
//  SPLMeterView.mm
//  foo_dsp_splmeter
//
//  UI in the style of JendaT/fb2k-components-mac-suite: themed presets
//  (ARGB light/dark), appearance-aware colors, falling peak cap, and a
//  clear over-limit alert.
//

#import "stdafx.h"
#import "dsp_splmeter.h"

#import <Cocoa/Cocoa.h>
#import <algorithm>
#import <cmath>

@class SPLGraphView;

@interface SPLGraphView : NSView
@end

@interface SPLMeterViewController : NSViewController
@property (nonatomic) SPLGraphView *graph;
@property (nonatomic) NSTextField *bigReadout;
@property (nonatomic) NSTextField *subReadout;
@property (nonatomic) NSTextField *doseReadout;
@property (nonatomic) NSButton *resetButton;
@property (nonatomic) NSTimer *timer;
@end

// ---- Theme presets (JendaT-suite style, ARGB 0xAARRGGBB) ----
// Index order must match splmeter::theme_count (6).
namespace splmeter_themes {

struct Theme {
    const char * name;
    uint32_t accentLight, bgLight, gridLight, textLight;
    uint32_t accentDark,  bgDark,  gridDark,  textDark;
};

static const Theme kThemes[] = {
    { "Default (Green)",
      0xFF1B8A3A, 0xFFF4F4F4, 0xFF9AA0A0, 0xFF202020,
      0xFF33FF66, 0xFF141414, 0xFF3C3C3C, 0xFFE8E8E8 },
    { "Nord",
      0xFF5E81AC, 0xFFECEFF4, 0xFFB0B6C0, 0xFF2E3440,
      0xFF88C0D0, 0xFF2E3440, 0xFF4C566A, 0xFFECEFF4 },
    { "Dracula",
      0xFF50FA7B, 0xFFF8F8F2, 0xFFCFCFD6, 0xFF282A36,
      0xFF50FA7B, 0xFF282A36, 0xFF44475A, 0xFFF8F8F2 },
    { "Gruvbox",
      0xFF98971A, 0xFFFBF1C7, 0xFFBDB4A0, 0xFF3C3836,
      0xFFB8BB26, 0xFF282828, 0xFF504945, 0xFFFBF1C7 },
    { "Solarized",
      0xFF268BD2, 0xFFFDF6E3, 0xFF93A1A0, 0xFF073642,
      0xFF268BD2, 0xFF002B36, 0xFF586E75, 0xFFFDF6E3 },
    { "Tokyo Night",
      0xFF7AA2F7, 0xFFD5D6DB, 0xFFA8AECB, 0xFF1A1B26,
      0xFF7AA2F7, 0xFF1A1B26, 0xFF414868, 0xFFA9B1D6 },
};

static const int kThemeCount = (int)(sizeof(kThemes) / sizeof(kThemes[0]));
static_assert(kThemeCount == 6, "keep in sync with splmeter::theme_count");

inline NSColor * fromARGB(uint32_t argb) {
    return [NSColor colorWithSRGBRed:((argb >> 16) & 0xFF) / 255.0
                               green:((argb >> 8) & 0xFF) / 255.0
                                blue:(argb & 0xFF) / 255.0
                               alpha:((argb >> 24) & 0xFF) / 255.0];
}

} // namespace splmeter_themes

// ---- Shared theme resolution for view + controller ----
namespace splmeter_ui {

static inline BOOL isDark(id appearanceOwner) {
    NSAppearanceName best = [[appearanceOwner effectiveAppearance]
        bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
    return [best isEqualToString:NSAppearanceNameDarkAqua];
}

struct Palette {
    NSColor * accent, * bg, * grid, * text;
};

static inline Palette paletteFor(const splmeter::MeterSettings & cfg, BOOL dark) {
    using namespace splmeter_themes;
    int idx = cfg.themeIndex;
    if (idx < 0 || idx >= kThemeCount) idx = 0;
    const Theme & t = kThemes[idx];
    Palette p;
    p.accent = fromARGB(dark ? t.accentDark : t.accentLight);
    p.bg     = fromARGB(dark ? t.bgDark     : t.bgLight);
    p.grid   = fromARGB(dark ? t.gridDark   : t.gridLight);
    p.text   = fromARGB(dark ? t.textDark   : t.textLight);
    return p;
}

// Level -> color: green below (threshold-5), amber within 5 dB, red over.
static inline NSColor * levelColor(double spl, double threshold) {
    if (spl >= threshold) return [NSColor colorWithCalibratedRed:1.0 green:0.28 blue:0.25 alpha:1.0];
    if (spl >= threshold - 5.0) return [NSColor colorWithCalibratedRed:1.0 green:0.76 blue:0.15 alpha:1.0];
    return [NSColor colorWithCalibratedRed:0.20 green:0.85 blue:0.45 alpha:1.0];
}

} // namespace splmeter_ui

// ---- Graph view: history chart + vertical level bar with peak cap ----
@implementation SPLGraphView {
    NSTimer * _timer;
    double _pulsePhase;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _pulsePhase = 0.0;
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)tick {
    _pulsePhase += 0.15;
    [self setNeedsDisplay:YES];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    const splmeter::MeterState st = splmeter::get_meter_state();
    const splmeter::MeterSettings cfg = splmeter::get_settings();
    const BOOL dark = splmeter_ui::isDark(self);
    const splmeter_ui::Palette pal = splmeter_ui::paletteFor(cfg, dark);

    [pal.bg setFill];
    NSRectFill(self.bounds);

    const CGFloat minSPL = 40.0;
    const CGFloat maxSPL = 100.0;

    // Layout: left vertical level bar, main history chart on the right.
    const CGFloat barW = 26.0;
    const NSRect barRect = NSMakeRect(12.0, 12.0, barW, NSHeight(self.bounds) - 24.0);
    const NSRect plot = NSMakeRect(barRect.origin.x + barW + 14.0, 12.0,
                                   NSWidth(self.bounds) - barW - 40.0, NSHeight(self.bounds) - 24.0);

    auto yFor = ^(double spl) {
        const double clamped = std::clamp(spl, minSPL, maxSPL);
        return plot.origin.y + ((CGFloat)((clamped - minSPL) / (maxSPL - minSPL))) * plot.size.height;
    };

    // ---- History chart ----
    // Grid every 10 dB
    NSDictionary *axisAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: pal.grid
    };
    [pal.grid setStroke];
    for (int spl = (int)minSPL; spl <= (int)maxSPL; spl += 10) {
        const CGFloat y = yFor(spl);
        NSBezierPath *line = [NSBezierPath bezierPath];
        line.lineWidth = 1.0;
        [line moveToPoint:NSMakePoint(plot.origin.x, y)];
        [line lineToPoint:NSMakePoint(NSMaxX(plot), y)];
        [line stroke];
        NSString *label = [NSString stringWithFormat:@"%d", spl];
        [label drawAtPoint:NSMakePoint(plot.origin.x, y + 2.0) withAttributes:axisAttrs];
    }

    // Threshold line (dashed red)
    const CGFloat ty = yFor(cfg.thresholdDbSPL);
    NSBezierPath *thresh = [NSBezierPath bezierPath];
    thresh.lineWidth = 1.5;
    const CGFloat dash[] = { 6.0, 4.0 };
    [thresh setLineDash:dash count:2 phase:0];
    [[NSColor colorWithCalibratedRed:1.0 green:0.25 blue:0.25 alpha:0.85] setStroke];
    [thresh moveToPoint:NSMakePoint(plot.origin.x, ty)];
    [thresh lineToPoint:NSMakePoint(NSMaxX(plot), ty)];
    [thresh stroke];

    // History area + trace (most recent at right)
    if (st.historyCount > 1) {
        const size_t count = MIN((size_t)splmeter::history_length, (size_t)st.historyCount);
        const CGFloat stepX = plot.size.width / (CGFloat)(splmeter::history_length - 1);
        const size_t startIdx = st.historyCount - count;

        NSBezierPath *area = [NSBezierPath bezierPath];
        NSBezierPath *trace = [NSBezierPath bezierPath];
        BOOL first = YES;
        for (size_t i = 0; i < count; ++i) {
            const size_t ringIdx = (startIdx + i) % splmeter::history_length;
            const CGFloat x = plot.origin.x + (CGFloat)i * stepX;
            const CGFloat y = yFor(st.historySPL[ringIdx]);
            if (first) {
                [area moveToPoint:NSMakePoint(x, plot.origin.y)];
                [area lineToPoint:NSMakePoint(x, y)];
                [trace moveToPoint:NSMakePoint(x, y)];
                first = NO;
            } else {
                [area lineToPoint:NSMakePoint(x, y)];
                [trace lineToPoint:NSMakePoint(x, y)];
            }
        }
        [area lineToPoint:NSMakePoint(plot.origin.x + (CGFloat)(count - 1) * stepX, plot.origin.y)];
        [area closePath];
        [[pal.accent colorWithAlphaComponent:0.25] setFill];
        [area fill];

        trace.lineWidth = 1.5;
        [pal.accent setStroke];
        [trace stroke];
    }

    // Current smoothed level marker
    const CGFloat cy = yFor(st.displaySPL);
    NSBezierPath *current = [NSBezierPath bezierPath];
    current.lineWidth = 2.0;
    [splmeter_ui::levelColor(st.displaySPL, cfg.thresholdDbSPL) setStroke];
    [current moveToPoint:NSMakePoint(plot.origin.x, cy)];
    [current lineToPoint:NSMakePoint(NSMaxX(plot), cy)];
    [current stroke];

    // ---- Vertical level bar with falling peak cap ----
    [[pal.grid colorWithAlphaComponent:0.6] setStroke];
    NSBezierPath *frame = [NSBezierPath bezierPathWithRect:barRect];
    frame.lineWidth = 1.0;
    [frame stroke];

    auto barYFor = ^(double spl) {
        const double clamped = std::clamp(spl, minSPL, maxSPL);
        return barRect.origin.y + ((CGFloat)((clamped - minSPL) / (maxSPL - minSPL))) * barRect.size.height;
    };

    const CGFloat levelY = barYFor(st.displaySPL);
    const NSRect levelRect = NSMakeRect(barRect.origin.x + 2.0, barRect.origin.y,
                                        barW - 4.0, levelY - barRect.origin.y);
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0.20 green:0.85 blue:0.45 alpha:0.9]
                                                         endingColor:[NSColor colorWithCalibratedRed:1.0 green:0.28 blue:0.25 alpha:0.9]];
    [gradient drawInRect:levelRect angle:90.0];

    // Peak cap tick
    const CGFloat peakY = barYFor(st.peakHoldSPL);
    NSBezierPath *cap = [NSBezierPath bezierPath];
    cap.lineWidth = 2.0;
    [splmeter_ui::levelColor(st.peakHoldSPL, cfg.thresholdDbSPL) setStroke];
    [cap moveToPoint:NSMakePoint(barRect.origin.x + 1.0, peakY)];
    [cap lineToPoint:NSMakePoint(NSMaxX(barRect) - 1.0, peakY)];
    [cap stroke];

    // ---- Over-limit alert banner (pulsing) ----
    if (st.overThreshold) {
        const CGFloat pulse = 0.65 + 0.35 * sin(_pulsePhase);
        const NSRect banner = NSMakeRect(plot.origin.x, NSMaxY(plot) - 30.0, NSWidth(plot), 26.0);
        [[NSColor colorWithCalibratedRed:1.0 green:0.2 blue:0.2 alpha:0.18 * pulse + 0.10] setFill];
        NSBezierPath *bannerBg = [NSBezierPath bezierPathWithRoundedRect:banner xRadius:6.0 yRadius:6.0];
        [bannerBg fill];

        NSDictionary *warnAttrs = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:14],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0 green:0.3 blue:0.3 alpha:pulse]
        };
        NSString *warn = [NSString stringWithFormat:@"⚠ OVER LIMIT — %.0f dB SPL (limit %.0f) · turn it down",
                          st.displaySPL, cfg.thresholdDbSPL];
        const NSSize sz = [warn sizeWithAttributes:warnAttrs];
        [warn drawAtPoint:NSMakePoint(NSMidX(banner) - sz.width / 2.0, NSMidY(banner) - sz.height / 2.0)
           withAttributes:warnAttrs];
    }
}

@end

@implementation SPLMeterViewController

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 220)];

    self.bigReadout = [NSTextField labelWithString:@"-- dB SPL"];
    self.bigReadout.font = [NSFont monospacedDigitSystemFontOfSize:26 weight:NSFontWeightBold];
    self.bigReadout.frame = NSMakeRect(12, 178, 200, 32);
    [root addSubview:self.bigReadout];

    self.subReadout = [NSTextField labelWithString:@"peak -- · RMS -- dBFS · limit 80 dB"];
    self.subReadout.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.subReadout.frame = NSMakeRect(12, 158, 300, 18);
    [root addSubview:self.subReadout];

    self.doseReadout = [NSTextField labelWithString:@"dose 0%"];
    self.doseReadout.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
    self.doseReadout.frame = NSMakeRect(330, 158, 90, 18);
    self.doseReadout.alignment = NSTextAlignmentRight;
    [root addSubview:self.doseReadout];

    self.resetButton = [NSButton buttonWithTitle:@"Reset" target:self action:@selector(resetTapped)];
    self.resetButton.bezelStyle = NSBezelStyleRounded;
    self.resetButton.controlSize = NSControlSizeSmall;
    self.resetButton.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    self.resetButton.frame = NSMakeRect(424, 155, 46, 22);
    [root addSubview:self.resetButton];

    self.graph = [[SPLGraphView alloc] initWithFrame:NSMakeRect(0, 0, 480, 150)];
    self.graph.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:self.graph];

    self.view = root;

    [self refreshTheme];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)resetTapped {
    splmeter::reset_exposure();
    [self refresh];
}

- (void)refreshTheme {
    const splmeter::MeterSettings cfg = splmeter::get_settings();
    const BOOL dark = splmeter_ui::isDark(self);
    const splmeter_ui::Palette pal = splmeter_ui::paletteFor(cfg, dark);
    self.bigReadout.textColor = pal.text;
    self.subReadout.textColor = [pal.text colorWithAlphaComponent:0.75];
}

- (void)refresh {
    const splmeter::MeterState st = splmeter::get_meter_state();
    const splmeter::MeterSettings cfg = splmeter::get_settings();
    self.bigReadout.stringValue = [NSString stringWithFormat:@"%.1f dB SPL", st.displaySPL];
    self.bigReadout.textColor = splmeter_ui::levelColor(st.displaySPL, cfg.thresholdDbSPL);
    self.subReadout.stringValue = [NSString stringWithFormat:@"peak %.1f · RMS %.1f dBFS · limit %.0f dB",
        st.peakHoldSPL, st.rmsDbFS, cfg.thresholdDbSPL];
    [self refreshTheme];
    self.doseReadout.stringValue = [NSString stringWithFormat:@"dose %.0f%%", st.dosePercent];
    self.doseReadout.textColor = st.dosePercent >= 100.0
        ? [NSColor colorWithCalibratedRed:1.0 green:0.3 blue:0.3 alpha:1.0]
        : [splmeter_ui::paletteFor(cfg, splmeter_ui::isDark(self)).text colorWithAlphaComponent:0.75];
}

- (void)dealloc {
    [self.timer invalidate];
}

@end

service_ptr ConfigureSPLMeterDSP(fb2k::hwnd_t parent, dsp_preset_edit_callback_v2::ptr callback) {
    (void)parent; (void)callback;
    SPLMeterViewController *controller = [[SPLMeterViewController alloc] init];
    return fb2k::wrapNSObject(controller);
}

namespace {

class splmeter_ui_element : public ui_element_mac {
public:
    service_ptr instantiate(service_ptr arg) override {
        (void)arg;
        return fb2k::wrapNSObject([[SPLMeterViewController alloc] init]);
    }

    bool match_name(const char * name) override {
        return pfc::stricmp_ascii(name, "splmeter") == 0
            || pfc::stricmp_ascii(name, "SPL Meter") == 0
            || pfc::stricmp_ascii(name, "spl-meter") == 0;
    }

    fb2k::stringRef get_name() override {
        return fb2k::makeString("SPL Meter");
    }

    GUID get_guid() override {
        return splmeter::ui_guid;
    }
};

static service_factory_single_t<splmeter_ui_element> g_splmeter_ui_element_factory;

}
