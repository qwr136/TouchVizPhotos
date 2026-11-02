#ifndef TVZ_TOUCHVIZ_TIMELINE_H
#define TVZ_TOUCHVIZ_TIMELINE_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

/* Twenty-millisecond ticks preserve unequal frame delays with bounded storage. */
static inline bool TVZTouchVizPlanTimeline(const double *delays, size_t count,
                                          uint16_t *repeats, double *duration) {
    if (!delays || !repeats || !duration || count == 0 || count > 120) return false;
    unsigned int ticks[120];
    unsigned int total = 0;
    for (size_t i = 0; i < count; i++) {
        double delay = delays[i];
        if (!isfinite(delay) || delay < 0 || delay > 10.0) return false;
        if (delay < 0.02) delay = 0.10;
        ticks[i] = (unsigned int)floor(delay * 50.0 + 0.5);
        if (!ticks[i]) ticks[i] = 1;
        total += ticks[i];
    }
    if (total > 3000) return false; /* Maximum loop duration: 60 seconds. */
    unsigned int divisor = ticks[0];
    for (size_t i = 1; i < count; i++) {
        unsigned int b = ticks[i];
        while (b) { unsigned int r = divisor % b; divisor = b; b = r; }
    }
    if (!divisor || total / divisor > 600) return false;
    for (size_t i = 0; i < count; i++) repeats[i] = (uint16_t)(ticks[i] / divisor);
    *duration = total / 50.0;
    return true;
}
#endif
