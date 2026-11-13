#import "storage_test.h"
#import "../TVZPrefs/NSBundle+TVZPrefs.h"
#import "../TVZPrefs/TVZUserDefaults.h"
#import "../TVZPrefs/TVZTouchVizImageRetention.h"
#import <UIKit/UIKit.h>
#import <libroot.h>

#define TVZ_STORAGE_CHECK(condition, message) do { if (!(condition)) return (message); } while (0)

NSString *TVZTouchVizRunStorageTests(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = JBROOT_PATH_NSSTRING(@"/var/mobile/Library/Touch-Viz");
    [fm removeItemAtPath:root error:nil];
    TVZUserDefaults *defaults = [TVZUserDefaults standardUserDefaults];
    [defaults resetToDefaultValues];
    [defaults synchronize];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.redColor setFill]; [context fillRect:CGRectMake(0, 0, 24, 24)];
    }];
    NSString *photo = [NSTemporaryDirectory() stringByAppendingPathComponent:@"source-original.png"];
    NSData *original = UIImagePNGRepresentation(image);
    TVZ_STORAGE_CHECK([original writeToFile:photo atomically:YES], @"test source write failed");
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        NSString *name = [NSBundle tvz_saveFillImageWithPath:photo];
        TVZ_STORAGE_CHECK(name.length, @"image import failed");
        [names addObject:name];
        TVZ_STORAGE_CHECK([NSBundle tvz_commitFillImageNamed:name emoji:@""], @"selection commit failed");
    }
    NSString *current = names.lastObject;
    // Complete the newest cleanup before its older callbacks: all end up keeping C.
    for (NSString *name in names.reverseObjectEnumerator) {
        TVZ_STORAGE_CHECK([NSBundle tvz_pruneFillImagesAfterSelectingName:name], @"out-of-order cleanup failed");
    }
    NSArray *files = [fm contentsOfDirectoryAtPath:root error:nil];
    TVZ_STORAGE_CHECK(files.count == 1 && [files.firstObject isEqualToString:current], @"A B C did not converge to C");
    TVZ_STORAGE_CHECK([[NSData dataWithContentsOfFile:photo] isEqualToData:original], @"album source changed");

    // A staged photo is preserved until its selection callback finishes.
    NSString *pending = [NSBundle tvz_saveFillImageWithImage:image];
    TVZ_STORAGE_CHECK(pending.length, @"staged Emoji save failed");
    TVZ_STORAGE_CHECK([NSBundle tvz_pruneFillImagesAfterSelectingName:nil], @"cleanup during staging failed");
    TVZ_STORAGE_CHECK([fm fileExistsAtPath:[root stringByAppendingPathComponent:pending]], @"pending material was deleted");
    TVZ_STORAGE_CHECK([NSBundle tvz_commitFillImageNamed:pending emoji:@"😀"], @"Emoji commit failed");
    TVZ_STORAGE_CHECK([NSBundle tvz_pruneFillImagesAfterSelectingName:pending], @"Emoji cleanup failed");
    files = [fm contentsOfDirectoryAtPath:root error:nil];
    TVZ_STORAGE_CHECK(files.count == 1 && [files.firstObject isEqualToString:pending], @"Emoji left older material");

    NSString *invalid = [NSBundle tvz_saveFillImageWithPath:[photo stringByAppendingString:@".missing"]];
    TVZ_STORAGE_CHECK(invalid == nil, @"invalid import accepted");
    TVZ_STORAGE_CHECK(![NSBundle tvz_commitFillImageNamed:@"missing.gif" emoji:@""], @"missing selected image committed");
    TVZ_STORAGE_CHECK([NSBundle tvz_pruneFillImagesAfterSelectingName:@"missing.gif"], @"failed selection cleanup failed");
    TVZ_STORAGE_CHECK([[defaults stringForKey:@"imageFillName"] isEqualToString:pending], @"failed selection overwrote current");
    TVZ_STORAGE_CHECK([fm fileExistsAtPath:[root stringByAppendingPathComponent:pending]], @"failed selection deleted current");

    // Legacy UUID files from prior versions are removed on opening the preferences page.
    for (NSUInteger i = 0; i < 2; i++) {
        NSString *legacy = [[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"GIF"];
        [original writeToFile:[root stringByAppendingPathComponent:legacy] atomically:YES];
    }
    TVZ_STORAGE_CHECK([NSBundle tvz_pruneFillImagesAfterSelectingName:nil], @"legacy cleanup failed");
    files = [fm contentsOfDirectoryAtPath:root error:nil];
    TVZ_STORAGE_CHECK(files.count == 1 && [files.firstObject isEqualToString:pending], @"legacy files remain");

    // Exercise actual GIF preservation through ImageIO and the storage API.
    NSString *gif = [NSBundle.mainBundle pathForResource:@"unequal" ofType:@"gif"];
    NSString *gifName = [NSBundle tvz_saveFillImageWithPath:gif];
    TVZ_STORAGE_CHECK(gifName.length, @"GIF import failed");
    TVZ_STORAGE_CHECK([NSBundle tvz_commitFillImageNamed:gifName emoji:@""], @"GIF commit failed");
    TVZ_STORAGE_CHECK([NSBundle tvz_pruneFillImagesAfterSelectingName:gifName], @"GIF cleanup failed");
    TVZ_STORAGE_CHECK([NSBundle tvz_fillImageNamed:gifName].images.count > 1, @"GIF stopped animating after cleanup");
    TVZ_STORAGE_CHECK([[NSData dataWithContentsOfFile:gif] isEqualToData:[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:gifName]]], @"GIF bytes changed");
    files = [fm contentsOfDirectoryAtPath:root error:nil];
    TVZ_STORAGE_CHECK(files.count == 1 && [files.firstObject isEqualToString:gifName], @"GIF left older material");
    return nil;
}
