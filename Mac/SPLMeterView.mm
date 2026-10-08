#import "stdafx.h"
#import "dsp_splmeter.h"

#import <Cocoa/Cocoa.h>

@class SPLGraphView;

@interface SPLGraphView : NSView
@end

@interface SPLMeterViewController : NSViewController
@property (nonatomic) SPLGraphView *graph;
@property (nonatomic) NSTextField *bigReadout;
@property (nonatomic) NSTextField *subReadout;
@property (nonatomic) NSTimer *timer;
@end

@implementation SPLGraphView {
    NSTimer * _timer;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)tick {
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedWhite:0.10 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    const splmeter::MeterState st = splmeter::get_meter_state();
    const splmeter::MeterSettings cfg = splmeter::get_settings();

    const NSRect plot = NSInsetRect(self.bounds, 30.0, 16.0);
    const CGFloat minSPL = 40.0;
    const CGFloat maxSPL = 100.0;

    auto yFor = ^(double spl) {
        const double clamped = std::clamp(spl, minSPL, maxSPL);
        return plot.origin.y + ((CGFloat)((clamped - minSPL) / (maxSPL - minSPL))) * plot.size.height;
    };

    // Grid lines every 10 dB
    [[NSColor colorWithCalibratedWhite:0.22 alpha:1.0] setStroke];
    NSDictionary *axisAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.55 alpha:1.0]
    };
    for (int spl = (int)minSPL; spl <= (int)maxSPL; spl += 10) {
        const CGFloat y = yFor(spl);
        NSBezierPath *line = [NSBezierPath bezierPath];
        line.lineWidth = 1.0;
        [line moveToPoint:NSMakePoint(plot.origin.x, y)];
        [line lineToPoint:NSMakePoint(NSMaxX(plot), y)];
        [line stroke];
        NSString *label = [NSString stringWithFormat:@"%d", spl];
        [label drawAtPoint:NSMakePoint(4.0, y - 5.0) withAttributes:axisAttrs];
    }

    // 80 dB threshold line (red, dashed)
    const CGFloat ty = yFor(cfg.thresholdDbSPL);
    NSBezierPath *thresh = [NSBezierPath bezierPath];
    thresh.lineWidth = 1.5;
    const CGFloat dash[] = { 6.0, 4.0 };
    [thresh setLineDash:dash count:2 phase:0];
    [[NSColor colorWithCalibratedRed:1.0 green:0.25 blue:0.25 alpha:0.85] setStroke];
    [thresh moveToPoint:NSMakePoint(plot.origin.x, ty)];
    [thresh lineToPoint:NSMakePoint(NSMaxX(plot), ty)];
    [thresh stroke];

    // History graph (most recent at right)
    if (st.historyCount > 1) {
        NSBezierPath *area = [NSBezierPath bezierPath];
        const size_t count = MIN((size_t)splmeter::history_length, (size_t)st.historyCount);
        const CGFloat stepX = plot.size.width / (CGFloat)(splmeter::history_length - 1);
        const size_t startIdx = st.historyCount - count;
        BOOL first = YES;
        for (size_t i = 0; i < count; ++i) {
            const size_t ringIdx = (startIdx + i) % splmeter::history_length;
            const CGFloat x = plot.origin.x + (CGFloat)i * stepX;
            const CGFloat y = yFor(st.historySPL[ringIdx]);
            if (first) { [area moveToPoint:NSMakePoint(x, plot.origin.y)]; [area lineToPoint:NSMakePoint(x, y)]; first = NO; }
            else { [area lineToPoint:NSMakePoint(x, y)]; }
        }
        [area lineToPoint:NSMakePoint(plot.origin.x + (CGFloat)(count - 1) * stepX, plot.origin.y)];
        [area closePath];
        [[NSColor colorWithCalibratedRed:0.10 green:0.75 blue:0.55 alpha:0.55] setFill];
        [area fill];

        NSBezierPath *trace = [NSBezierPath bezierPath];
        first = YES;
        for (size_t i = 0; i < count; ++i) {
            const size_t ringIdx = (startIdx + i) % splmeter::history_length;
            const CGFloat x = plot.origin.x + (CGFloat)i * stepX;
            const CGFloat y = yFor(st.historySPL[ringIdx]);
            if (first) { [trace moveToPoint:NSMakePoint(x, y)]; first = NO; }
            else { [trace lineToPoint:NSMakePoint(x, y)]; }
        }
        trace.lineWidth = 1.5;
        [[NSColor colorWithCalibratedRed:0.20 green:0.95 blue:0.70 alpha:1.0] setStroke];
        [trace stroke];
    }

    // Current level marker line
    const CGFloat cy = yFor(st.estimatedSPL);
    NSBezierPath *current = [NSBezierPath bezierPath];
    current.lineWidth = 2.0;
    const BOOL over = st.estimatedSPL >= cfg.thresholdDbSPL;
    [over ? [NSColor colorWithCalibratedRed:1.0 green:0.2 blue:0.2 alpha:1.0]
          : [NSColor colorWithCalibratedRed:0.95 green:0.85 blue:0.2 alpha:1.0] setStroke];
    [current moveToPoint:NSMakePoint(plot.origin.x, cy)];
    [current lineToPoint:NSMakePoint(NSMaxX(plot), cy)];
    [current stroke];

    // Big "over threshold" warning
    if (over) {
        NSDictionary *warnAttrs = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:20],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:1.0 green:0.25 blue:0.25 alpha:1.0]
        };
        NSString *warn = @"⚠ EXCEEDED 80 dB — TURN IT DOWN";
        [warn drawAtPoint:NSMakePoint(NSMidX(plot) - 130.0, NSMaxY(plot) - 26.0) withAttributes:warnAttrs];
    }
}

@end

@implementation SPLMeterViewController

- (void)loadView {
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 200)];

    self.bigReadout = [NSTextField labelWithString:@"-- dB SPL"];
    self.bigReadout.font = [NSFont monospacedDigitSystemFontOfSize:26 weight:NSFontWeightBold];
    self.bigReadout.frame = NSMakeRect(12, 160, 220, 30);
    [root addSubview:self.bigReadout];

    self.subReadout = [NSTextField labelWithString:@"peak -- · threshold 80 dB"];
    self.subReadout.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    self.subReadout.frame = NSMakeRect(12, 140, 320, 18);
    [root addSubview:self.subReadout];

    self.graph = [[SPLGraphView alloc] initWithFrame:NSMakeRect(0, 0, 460, 140)];
    self.graph.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:self.graph];

    self.view = root;

    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)refresh {
    const splmeter::MeterState st = splmeter::get_meter_state();
    const splmeter::MeterSettings cfg = splmeter::get_settings();
    self.bigReadout.stringValue = [NSString stringWithFormat:@"%.1f dB SPL", st.estimatedSPL];
    self.bigReadout.textColor = st.estimatedSPL >= cfg.thresholdDbSPL
        ? [NSColor colorWithCalibratedRed:1.0 green:0.3 blue:0.3 alpha:1.0]
        : [NSColor colorWithCalibratedWhite:0.9 alpha:1.0];
    self.subReadout.stringValue = [NSString stringWithFormat:@"peak %.1f dB · RMS %.1f dBFS · limit %.0f dB",
        st.estimatedPeakSPL, st.rmsDbFS, cfg.thresholdDbSPL];
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
