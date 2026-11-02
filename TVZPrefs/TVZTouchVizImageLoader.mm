#import "TVZTouchVizImageLoader.h"
#import "TVZTouchVizImageFrames.h"

@implementation TVZTouchVizImageLoader
+ (UIImage *)imageAtPath:(NSString *)path {
    TVZTouchVizDecodedFrames decoded = {0};
    if (!TVZTouchVizDecodeFile((__bridge CFURLRef)[NSURL fileURLWithPath:path], &decoded)) return nil;
    NSMutableArray<UIImage *> *frames = [NSMutableArray array];
    for (size_t i = 0; i < decoded.count; i++) {
        UIImage *frame = [UIImage imageWithCGImage:(CGImageRef)CFArrayGetValueAtIndex(decoded.frames, i)
                                            scale:1 orientation:UIImageOrientationUp];
        for (uint16_t j = 0; j < decoded.repeats[i]; j++) [frames addObject:frame];
    }
    UIImage *image = decoded.animated ? [UIImage animatedImageWithImages:frames duration:decoded.duration] : frames.firstObject;
    TVZTouchVizReleaseFrames(&decoded);
    return image;
}
@end
