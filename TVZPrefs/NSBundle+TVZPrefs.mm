#import "NSBundle+TVZPrefs.h"
#import "TVZTouchVizImageLoader.h"
#import <ImageIO/ImageIO.h>

#import <Foundation/NSFileManager.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUUID.h>
#import <HBLog.h>

#import <libroot.h>

@implementation NSBundle (TouchViz)

+ (NSBundle *)tvz_supportBundle {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"TVZPrefs"
                                                                  ofType:@"bundle"];
      NSString *aliasBundlePath;
      aliasBundlePath = JBROOT_PATH_NSSTRING(@"/Library/PreferenceBundles/TVZPrefs.bundle");
      bundle = [NSBundle bundleWithPath:tweakBundlePath ?: aliasBundlePath];
#if TARGET_IPHONE_SIMULATOR
      if (!bundle) {
          aliasBundlePath = @"/opt/simject/PreferenceBundles/TVZPrefs.bundle";
          bundle = [NSBundle bundleWithPath:aliasBundlePath];
      }
#endif
      NSLog(@"[TouchViz] Support bundle path: %@", [bundle bundlePath]);
    });
    return bundle;
}

+ (NSString *)tvz_packageVersion {
    return @PACKAGE_VERSION;
}

+ (NSString *)tvz_fillImageRoot {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      path = JBROOT_PATH_NSSTRING(@"/var/mobile/Library/Touch-Viz");
#if DEBUG
      HBLogWarn(@"[Touch-Viz] Fill image root: %@", path);
#endif
    });
    return path;
}

+ (BOOL)tvz_ensureFillImageRoot {
    return [[NSFileManager defaultManager] createDirectoryAtPath:[self tvz_fillImageRoot]
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:nil];
}

+ (UIImage *)tvz_defaultFillImage {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      image = [UIImage imageNamed:@"default"
                       inBundle:[self tvz_supportBundle]
  compatibleWithTraitCollection:nil];
    });
    return image;
}

+ (UIImage *)tvz_fillImageNamed:(NSString *)name {
    if (!name || [name isEqualToString:@"default.png"]) {
        return [self tvz_defaultFillImage];
    }
    if (![name isEqualToString:name.lastPathComponent]) return [self tvz_defaultFillImage];
    static NSString *tvz_cachedPath;
    static NSDictionary *tvz_cachedAttributes;
    static UIImage *tvz_cachedImage;
    NSString *imagePath = [[self tvz_fillImageRoot] stringByAppendingPathComponent:name];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:imagePath error:nil];
    @synchronized(self) {
        if ([tvz_cachedPath isEqualToString:imagePath] && [tvz_cachedAttributes isEqual:attributes])
            return tvz_cachedImage ?: [self tvz_defaultFillImage];
        tvz_cachedImage = [TVZTouchVizImageLoader imageAtPath:imagePath];
        tvz_cachedPath = imagePath;
        tvz_cachedAttributes = attributes;
        return tvz_cachedImage ?: [self tvz_defaultFillImage];
    }
}

+ (NSString *)tvz_saveFillImageWithPath:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![TVZTouchVizImageLoader imageAtPath:path] || ![self tvz_ensureFillImageRoot]) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return nil;
    BOOL isGIF = CGImageSourceGetType(source) && CFEqual(CGImageSourceGetType(source), CFSTR("com.compuserve.gif"));
    CFRelease(source);
    NSString *imageExt = isGIF ? @"gif" : ([path pathExtension].length ? [path pathExtension] : @"image");
    NSString *imageName = [NSString stringWithFormat:@"%@.%@", [[NSUUID UUID] UUIDString], imageExt];
    NSString *imagePath = [[self tvz_fillImageRoot] stringByAppendingPathComponent:imageName];
    BOOL copied = [fileManager copyItemAtPath:path toPath:imagePath error:nil];
    if (!copied) { [fileManager removeItemAtPath:imagePath error:nil]; return nil; }
    [fileManager setAttributes:@{NSFileModificationDate : [NSDate date], NSFilePosixPermissions : @0644}
                       ofItemAtPath:imagePath error:nil];
    return imageName;
}

+ (NSString *)tvz_saveFillImageWithImage:(UIImage *)image {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *imageName = [NSString stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]];
    [self tvz_ensureFillImageRoot];
    NSString *imagePath = [[self tvz_fillImageRoot] stringByAppendingPathComponent:imageName];
    [fileManager removeItemAtPath:imagePath error:nil];
    BOOL wrote = [UIImagePNGRepresentation(image) writeToFile:imagePath atomically:YES];
    [fileManager setAttributes:@{NSFileModificationDate : [NSDate date]} ofItemAtPath:imagePath error:nil];
    return wrote ? imageName : nil;
}

+ (BOOL)tvz_removeAllFillImages {
    [[NSFileManager defaultManager] removeItemAtPath:[self tvz_fillImageRoot] error:nil];
    return [self tvz_ensureFillImageRoot];
}

@end
