#import <Foundation/Foundation.h>
static inline NSString *TVZTouchVizStorageTestRootPath(NSString *path) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if ([path isEqualToString:@"/var/mobile/Library/Touch-Viz"])
        return [documents stringByAppendingPathComponent:@"TVZStorageTestImages"];
    return path;
}
#define JBROOT_PATH_NSSTRING(path) TVZTouchVizStorageTestRootPath(path)
