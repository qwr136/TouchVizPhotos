#import "NSBundle+TVZPrefs.h"
#import "TVZTouchVizImageLoader.h"
#import "TVZTouchVizImageRetention.h"
#import "TVZUserDefaults.h"
#import <ImageIO/ImageIO.h>
#include <vector>

static NSMutableSet<NSString *> *TVZTouchVizPendingFillImages(void) {
    static NSMutableSet<NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ names = [NSMutableSet set]; });
    return names;
}

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
    if (![TVZTouchVizImageLoader imageAtPath:path]) return nil;
    @synchronized(self) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![self tvz_ensureFillImageRoot]) return nil;
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
        if (!source) return nil;
        BOOL isGIF = CGImageSourceGetType(source) && CFEqual(CGImageSourceGetType(source), CFSTR("com.compuserve.gif"));
        CFRelease(source);
        NSString *identifier = [[NSUUID UUID] UUIDString];
        NSString *imageExt = isGIF ? @"gif" : ([path pathExtension].length ? [path pathExtension] : @"image");
        NSString *imageName = [NSString stringWithFormat:@"%@.%@", identifier, imageExt];
        if (!TVZTouchVizIsManagedImage(imageName.UTF8String))
            imageName = [identifier stringByAppendingPathExtension:@"image"];
        NSString *imagePath = [[self tvz_fillImageRoot] stringByAppendingPathComponent:imageName];
        BOOL copied = [fileManager copyItemAtPath:path toPath:imagePath error:nil];
        if (!copied) { [fileManager removeItemAtPath:imagePath error:nil]; return nil; }
        [fileManager setAttributes:@{NSFileModificationDate : [NSDate date], NSFilePosixPermissions : @0644}
                           ofItemAtPath:imagePath error:nil];
        [TVZTouchVizPendingFillImages() addObject:imageName];
        return imageName;
    }
}

+ (NSString *)tvz_saveFillImageWithImage:(UIImage *)image {
    NSData *data = UIImagePNGRepresentation(image);
    if (!data.length) return nil;
    @synchronized(self) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![self tvz_ensureFillImageRoot]) return nil;
        NSString *imageName = [NSString stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]];
        NSString *imagePath = [[self tvz_fillImageRoot] stringByAppendingPathComponent:imageName];
        BOOL wrote = [data writeToFile:imagePath atomically:YES];
        if (!wrote) { [fileManager removeItemAtPath:imagePath error:nil]; return nil; }
        [fileManager setAttributes:@{NSFileModificationDate : [NSDate date], NSFilePosixPermissions : @0644}
                           ofItemAtPath:imagePath error:nil];
        [TVZTouchVizPendingFillImages() addObject:imageName];
        return imageName;
    }
}

+ (BOOL)tvz_commitFillImageNamed:(NSString *)name emoji:(NSString *)emoji {
    @synchronized(self) {
        if (!name.length || ![name isEqualToString:name.lastPathComponent]) return NO;
        if (![name isEqualToString:@"default.png"] &&
            ![TVZTouchVizImageLoader imageAtPath:[[self tvz_fillImageRoot] stringByAppendingPathComponent:name]]) return NO;
        TVZUserDefaults *defaults = [TVZUserDefaults standardUserDefaults];
        NSString *previousName = [defaults stringForKey:@"imageFillName"] ?: @"default.png";
        NSString *previousEmoji = [defaults stringForKey:@"selectedEmoji"] ?: @"";
        [defaults beginUpdates];
        [defaults setObject:name forKey:@"imageFillName"];
        [defaults setObject:emoji ?: @"" forKey:@"selectedEmoji"];
        BOOL saved = [defaults synchronize];
        if (!saved) {
            [defaults setObject:previousName forKey:@"imageFillName"];
            [defaults setObject:previousEmoji forKey:@"selectedEmoji"];
            [defaults synchronize];
        }
        [defaults endUpdates];
        return saved;
    }
}

+ (BOOL)tvz_pruneFillImagesAfterSelectingName:(NSString *)completedName {
    @synchronized(self) {
        if (completedName) [TVZTouchVizPendingFillImages() removeObject:completedName];
        TVZUserDefaults *defaults = [TVZUserDefaults standardUserDefaults];
        if (![defaults synchronize]) return NO;
        // A delayed cleanup always keeps today's committed selection, never its old callback argument.
        NSString *name = [defaults stringForKey:@"imageFillName"];
        if (!name.length || ![name isEqualToString:name.lastPathComponent]) return NO;
        NSString *root = [self tvz_fillImageRoot];
        if (![name isEqualToString:@"default.png"] &&
            ![TVZTouchVizImageLoader imageAtPath:[root stringByAppendingPathComponent:name]]) return NO;
        NSArray<NSString *> *pending = TVZTouchVizPendingFillImages().allObjects;
        std::vector<const char *> protectedNames;
        for (NSString *pendingName in pending) protectedNames.push_back(pendingName.UTF8String);
        size_t removed = 0;
        int error = TVZTouchVizPruneImageDirectory(root.fileSystemRepresentation, name.UTF8String,
                                                  protectedNames.data(), protectedNames.size(), &removed);
        if (error == ENOENT && [name isEqualToString:@"default.png"]) return YES;
        if (error) NSLog(@"[Touch-Viz] Material cleanup incomplete (error %d); selected file preserved.", error);
        return error == 0;
    }
}

+ (BOOL)tvz_removeAllFillImages {
    @synchronized(self) {
        NSError *error = nil;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *root = [self tvz_fillImageRoot];
        if ([fileManager fileExistsAtPath:root] && ![fileManager removeItemAtPath:root error:&error]) return NO;
        [TVZTouchVizPendingFillImages() removeAllObjects];
        return [self tvz_ensureFillImageRoot];
    }
}

@end
