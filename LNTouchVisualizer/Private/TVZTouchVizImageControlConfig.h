#ifndef TVZ_TOUCHVIZ_IMAGE_CONTROL_CONFIG_H
#define TVZ_TOUCHVIZ_IMAGE_CONTROL_CONFIG_H
#import <Foundation/Foundation.h>
#import <LNTouchVisualizer/LNTouchConfig.h>
#import "TVZTouchVizImageControlMath.h"

static inline double TVZTouchVizStoredNumber(NSUserDefaults *defaults, NSString *key, double fallback) {
    id value = [defaults objectForKey:key];
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
        return fallback;
    double result = [value doubleValue];
    return isfinite(result) ? result : fallback;
}

/* Called on configuration reload, never from the per-touch hot path. */
static inline void TVZTouchVizLoadImageControls(NSUserDefaults *defaults,
                                               LNTouchConfig *contact, LNTouchConfig *ripple) {
    double rate = TVZTouchVizPlaybackRate(TVZTouchVizStoredNumber(defaults, @"tvzGIFPlaybackRate", 1.0));
    double x = TVZTouchVizImageOffset(TVZTouchVizStoredNumber(defaults, @"tvzImageOffsetX", 0.0));
    double y = TVZTouchVizImageOffset(TVZTouchVizStoredNumber(defaults, @"tvzImageOffsetY", 0.0));
    contact.tvzGIFPlaybackRate = ripple.tvzGIFPlaybackRate = rate;
    contact.tvzImageOffsetX = ripple.tvzImageOffsetX = x;
    contact.tvzImageOffsetY = ripple.tvzImageOffsetY = y;
}
#endif
