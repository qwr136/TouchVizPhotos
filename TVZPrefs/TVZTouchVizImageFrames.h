#ifndef TVZ_TOUCHVIZ_IMAGE_FRAMES_H
#define TVZ_TOUCHVIZ_IMAGE_FRAMES_H

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    TVZTouchVizMaxFileBytes = 12 * 1024 * 1024,
    TVZTouchVizMaxFrames = 120,
    TVZTouchVizMaxPixels = 192,
    TVZTouchVizMaxDecodedBytes = 24 * 1024 * 1024,
    TVZTouchVizMaxTimelineFrames = 600
};

typedef struct {
    CFArrayRef frames; /* Owned array of CGImageRef; caller releases. */
    uint16_t repeats[TVZTouchVizMaxFrames];
    size_t count;
    double duration;
    bool animated;
} TVZTouchVizDecodedFrames;

/* Fail closed for damaged/oversized media; no partial animation is returned. */
bool TVZTouchVizDecodeFile(CFURLRef url, TVZTouchVizDecodedFrames *output);
void TVZTouchVizReleaseFrames(TVZTouchVizDecodedFrames *output);

#ifdef __cplusplus
}
#endif
#endif
