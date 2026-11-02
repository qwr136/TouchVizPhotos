#include "TVZTouchVizImageFrames.h"
#include "TVZTouchVizTimeline.h"
#include <ImageIO/ImageIO.h>
#include <sys/stat.h>
#include <string.h>
#include <math.h>

static double TVZTouchVizNumber(CFDictionaryRef dict, CFStringRef key, double fallback) {
    if (!dict) return fallback;
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    double result = fallback;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &result);
    return result;
}

void TVZTouchVizReleaseFrames(TVZTouchVizDecodedFrames *output) {
    if (!output) return;
    if (output->frames) CFRelease(output->frames);
    memset(output, 0, sizeof(*output));
}

bool TVZTouchVizDecodeFile(CFURLRef url, TVZTouchVizDecodedFrames *output) {
    if (!url || !output) return false;
    memset(output, 0, sizeof(*output));
    UInt8 path[4096];
    struct stat fileStat;
    if (!CFURLGetFileSystemRepresentation(url, true, path, sizeof(path)) ||
        stat((const char *)path, &fileStat) || !S_ISREG(fileStat.st_mode) ||
        fileStat.st_size <= 0 || fileStat.st_size > TVZTouchVizMaxFileBytes) return false;

    const void *sourceKeys[] = { kCGImageSourceShouldCache };
    const void *sourceValues[] = { kCFBooleanFalse };
    CFDictionaryRef sourceOptions = CFDictionaryCreate(NULL, sourceKeys, sourceValues, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CGImageSourceRef source = CGImageSourceCreateWithURL(url, sourceOptions);
    CFRelease(sourceOptions);
    if (!source) return false;
    size_t count = CGImageSourceGetCount(source);
    bool isGIF = CGImageSourceGetType(source) &&
        CFEqual(CGImageSourceGetType(source), CFSTR("com.compuserve.gif"));
    bool valid = count > 0 && count <= TVZTouchVizMaxFrames &&
        CGImageSourceGetStatus(source) == kCGImageStatusComplete;
    size_t decodedCount = isGIF ? count : 1;
    double delays[TVZTouchVizMaxFrames] = {0};
    CFMutableArrayRef images = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    size_t totalBytes = 0;
    int maxPixels = TVZTouchVizMaxPixels;
    CFNumberRef pixels = CFNumberCreate(NULL, kCFNumberIntType, &maxPixels);
    const void *thumbKeys[] = { kCGImageSourceCreateThumbnailFromImageAlways,
        kCGImageSourceCreateThumbnailWithTransform, kCGImageSourceThumbnailMaxPixelSize,
        kCGImageSourceShouldCacheImmediately };
    const void *thumbValues[] = { kCFBooleanTrue, kCFBooleanTrue, pixels, kCFBooleanTrue };
    CFDictionaryRef options = CFDictionaryCreate(NULL, thumbKeys, thumbValues, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    for (size_t i = 0; valid && i < decodedCount; i++) {
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
        double width = TVZTouchVizNumber(properties, kCGImagePropertyPixelWidth, 0);
        double height = TVZTouchVizNumber(properties, kCGImagePropertyPixelHeight, 0);
        valid = isfinite(width) && isfinite(height) && width > 0 && height > 0 &&
            width <= 8192 && height <= 8192 && width * height <= 16000000;
        if (isGIF && properties) {
            CFDictionaryRef gif = (CFDictionaryRef)CFDictionaryGetValue(properties, kCGImagePropertyGIFDictionary);
            if (gif && CFGetTypeID(gif) != CFDictionaryGetTypeID()) gif = NULL;
            delays[i] = TVZTouchVizNumber(gif, kCGImagePropertyGIFUnclampedDelayTime,
                TVZTouchVizNumber(gif, kCGImagePropertyGIFDelayTime, 0.10));
        }
        if (properties) CFRelease(properties);
        if (!valid) break;
        CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, i, options);
        if (!image || CGImageSourceGetStatusAtIndex(source, i) != kCGImageStatusComplete) {
            if (image) CGImageRelease(image);
            valid = false;
            break;
        }
        size_t bytes = CGImageGetBytesPerRow(image) * CGImageGetHeight(image);
        if (bytes > TVZTouchVizMaxDecodedBytes - totalBytes) {
            CGImageRelease(image);
            valid = false;
            break;
        }
        totalBytes += bytes;
        CFArrayAppendValue(images, image);
        CGImageRelease(image);
    }
    CFRelease(options);
    CFRelease(pixels);
    CFRelease(source);
    if (valid && isGIF && decodedCount > 1)
        valid = TVZTouchVizPlanTimeline(delays, decodedCount, output->repeats, &output->duration);
    else if (valid) output->repeats[0] = 1;
    if (!valid) { CFRelease(images); memset(output, 0, sizeof(*output)); return false; }
    output->frames = images;
    output->count = decodedCount;
    output->animated = isGIF && decodedCount > 1;
    return true;
}
