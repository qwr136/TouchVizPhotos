#ifndef TVZ_TOUCHVIZ_IMAGE_CONTROL_MATH_H
#define TVZ_TOUCHVIZ_IMAGE_CONTROL_MATH_H
#include <math.h>
#include <stdbool.h>

static inline double TVZTouchVizPlaybackRate(double value) {
    if (!isfinite(value)) return 1.0;
    return fmin(2.0, fmax(0.5, value));
}

static inline double TVZTouchVizImageOffset(double value) {
    if (!isfinite(value)) return 0.0;
    return fmin(100.0, fmax(-100.0, value));
}

static inline double TVZTouchVizPlaybackDuration(double original, double rate) {
    if (!isfinite(original) || original <= 0.0) return 0.0;
    return original / TVZTouchVizPlaybackRate(rate);
}

typedef struct { double x, y; } TVZTouchVizPoint;

/* Translate only the drawing. Use interface axes, never the rotating image's axes. */
static inline TVZTouchVizPoint TVZTouchVizDisplayPoint(double rawX, double rawY,
    bool hasImage, double offsetX, double offsetY, double a, double b, double c, double d) {
    TVZTouchVizPoint result = { rawX, rawY };
    if (!hasImage || !isfinite(a) || !isfinite(b) || !isfinite(c) || !isfinite(d)) return result;
    double x = TVZTouchVizImageOffset(offsetX), y = TVZTouchVizImageOffset(offsetY);
    result.x += a * x + c * y;
    result.y += b * x + d * y;
    return result;
}
#endif
