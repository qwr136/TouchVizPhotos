#import <UIKit/UIKit.h>
#import "../LNTouchVisualizer/LNTouchVisualizerWindow.h"
#import "../LNTouchVisualizer/Private/LNTouchImageView.h"
#import "../LNTouchVisualizer/Private/LNTouchImageFactory.h"
#import "../LNTouchVisualizer/Private/TVZTouchVizImageControlConfig.h"
#import "../TVZPrefs/TVZUserDefaults.h"
#import "shims/TouchViz-Swift.h"

// The target renderer is real; only external orientation and QuickPath services are doubles.
@implementation TVZQuickPathViewController
@end
@implementation UIWindow (TVZImageControlTestQuickPath)
- (void)sendQuickPathEvent:(UIEvent *)event { (void)event; }
@end
@interface FBSOrientationObserver : NSObject
- (void)setHandler:(void (^)(id))handler;
- (void)invalidate;
@end
@implementation FBSOrientationObserver
- (void)setHandler:(void (^)(id))handler { (void)handler; }
- (void)invalidate {}
@end

@interface LNTouchVisualizerWindow (TVZControlTesting)
@property(nonatomic, strong) UIWindow *overlayWindow;
- (CGPoint)locationOfTouch:(UITouch *)touch;
- (CGAffineTransform)coordinateTransform;
- (void)_scheduleFingerTipRemoval;
@end
@interface TVZControlTestWindow : LNTouchVisualizerWindow
@property(nonatomic) CGAffineTransform tvzTestAxes;
@end
@implementation TVZControlTestWindow
- (CGPoint)locationOfTouch:(UITouch *)touch { return [touch locationInView:nil]; }
- (CGAffineTransform)coordinateTransform { return self.tvzTestAxes; }
- (void)_scheduleFingerTipRemoval {}
@end
@interface TVZControlTestTouch : UITouch
@property(nonatomic) CGPoint tvzPoint;
@property(nonatomic) UITouchPhase tvzPhase;
@property(nonatomic) NSUInteger tvzIdentifier;
@end
@implementation TVZControlTestTouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.tvzPoint; }
- (UITouchType)type { return UITouchTypeDirect; }
- (UITouchPhase)phase { return self.tvzPhase; }
- (NSUInteger)hash { return self.tvzIdentifier; }
- (NSTimeInterval)timestamp { return NSProcessInfo.processInfo.systemUptime; }
@end
@interface TVZControlTestEvent : UIEvent
@property(nonatomic, copy) NSSet<UITouch *> *tvzTouches;
@end
@implementation TVZControlTestEvent
- (NSSet<UITouch *> *)allTouches { return self.tvzTouches; }
@end

static BOOL TVZControlClose(double a, double b) { return fabs(a-b) < 0.001; }
static BOOL TVZControlPoint(CGPoint p, CGFloat x, CGFloat y) {
    return TVZControlClose(p.x,x) && TVZControlClose(p.y,y);
}
#define TVZ_CONTROLS_CHECK(c, msg) do { if (!(c)) return (msg); } while (0)

extern "C" NSString *TVZTouchVizRunImageControlTests(void) {
    TVZUserDefaults *defaults = [TVZUserDefaults standardUserDefaults];
    [defaults resetToDefaultValues];
    LNTouchConfig *contact = [LNTouchConfig touchConfig], *ripple = [LNTouchConfig rippleConfig];
    TVZTouchVizLoadImageControls(defaults, contact, ripple);
    TVZ_CONTROLS_CHECK(contact.tvzGIFPlaybackRate == 1 && contact.tvzImageOffsetX == 0 &&
        contact.tvzImageOffsetY == 0, @"new controls did not preserve old defaults");
    [defaults setObject:@"invalid" forKey:@"tvzGIFPlaybackRate"];
    [defaults setObject:@YES forKey:@"tvzImageOffsetX"];
    [defaults setObject:@(INFINITY) forKey:@"tvzImageOffsetY"];
    TVZTouchVizLoadImageControls(defaults,contact,ripple);
    TVZ_CONTROLS_CHECK(contact.tvzGIFPlaybackRate==1 && contact.tvzImageOffsetX==0 &&
        contact.tvzImageOffsetY==0, @"invalid preference fallback failed");
    [defaults setObject:@9 forKey:@"tvzGIFPlaybackRate"];
    [defaults setObject:@999 forKey:@"tvzImageOffsetX"];
    [defaults setObject:@(-999) forKey:@"tvzImageOffsetY"];
    TVZTouchVizLoadImageControls(defaults,contact,ripple);
    TVZ_CONTROLS_CHECK(contact.tvzGIFPlaybackRate==2 && ripple.tvzGIFPlaybackRate==2 &&
        contact.tvzImageOffsetX==100 && ripple.tvzImageOffsetY==-100, @"consumer range validation failed");

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24,24)];
    UIImage *red = [renderer imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [UIColor.redColor setFill]; [c fillRect:CGRectMake(0,0,24,24)];
    }];
    UIImage *blue = [renderer imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [UIColor.blueColor setFill]; [c fillRect:CGRectMake(0,0,24,24)];
    }];
    UIImage *gif = [UIImage animatedImageWithImages:@[red,blue] duration:0.4];
    UIWindow *overlay = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    overlay.rootViewController = [UIViewController new];
    overlay.hidden = NO;
    TVZControlTestWindow *window = [[TVZControlTestWindow alloc] initWithFrame:overlay.bounds
        touchVisualizationEnabled:YES quickPathEnabled:NO morphEnabled:NO trackingEnabled:NO
        contactConfig:contact rippleConfig:ripple];
    window.overlayWindow = overlay;
    window.tvzTestAxes = CGAffineTransformIdentity;
    contact.fillImage = gif;
    contact.fillColor = UIColor.clearColor;
    contact.strokeColor = UIColor.clearColor;
    contact.tvzGIFPlaybackRate = 2;
    contact.tvzImageOffsetX = 30;
    contact.tvzImageOffsetY = -40;
    window.touchContactConfig = contact;
    TVZControlTestTouch *touch = [TVZControlTestTouch new];
    touch.tvzIdentifier = 1001; touch.tvzPoint = CGPointMake(140,240); touch.tvzPhase = UITouchPhaseBegan;
    TVZControlTestEvent *event = [TVZControlTestEvent new]; event.tvzTouches = [NSSet setWithObject:touch];
    [window sendTouchEvent:event];
    LNTouchImageView *view = (LNTouchImageView *)[overlay viewWithTag:1001];
    TVZ_CONTROLS_CHECK(view && TVZControlPoint(view.center,170,200), @"first touch image offset failed");
    TVZ_CONTROLS_CHECK(TVZControlPoint(view.tvzRawCenter,140,240) && TVZControlPoint(touch.tvzPoint,140,240), @"display offset changed raw touch");
    TVZ_CONTROLS_CHECK(view.isAnimating && TVZControlClose(view.animationDuration,0.2), @"2x touch GIF duration failed");
    TVZ_CONTROLS_CHECK(TVZControlClose(contact.fadeDuration,0.3) && contact.liftScale==2, @"speed changed lift/fade parameters");
    contact.tvzGIFPlaybackRate=0.5; contact.tvzImageOffsetX=-20; contact.tvzImageOffsetY=15;
    window.touchContactConfig=contact;
    TVZ_CONTROLS_CHECK(TVZControlClose(view.animationDuration,0.8) && TVZControlPoint(view.center,120,255), @"live parameter refresh failed");
    contact.shouldAutoRotate=YES;
    touch.tvzPoint=CGPointMake(150,240); touch.tvzPhase=UITouchPhaseMoved;
    [window sendTouchEvent:event];
    TVZ_CONTROLS_CHECK(TVZControlPoint(view.center,130,255) && TVZControlClose(view.transform.a,0) &&
        TVZControlClose(view.transform.b,1), @"offset polluted movement heading");
    CGAffineTransform orientations[] = {CGAffineTransformIdentity, CGAffineTransformMakeRotation(M_PI_2),
        CGAffineTransformMakeRotation(-M_PI_2), CGAffineTransformMakeRotation(M_PI)};
    for (int i=0;i<4;i++) {
        contact.shouldAutoRotate=NO; window.tvzTestAxes=orientations[i];
        [window sendTouchEvent:event];
        CGPoint v=CGPointApplyAffineTransform(CGPointMake(-20,15),orientations[i]);
        TVZ_CONTROLS_CHECK(TVZControlPoint(view.center,150+v.x,240+v.y), @"interface-axis offset failed");
    }
    window.tvzTestAxes=CGAffineTransformIdentity;
    window.trackingEnabled=YES;
    ripple.fillImage=gif; ripple.tvzGIFPlaybackRate=2; ripple.tvzImageOffsetX=30; ripple.tvzImageOffsetY=-40;
    window.touchRippleConfig=ripple;
    [window sendTouchEvent:event];
    LNTouchImageView *trail=nil;
    for (LNTouchImageView *candidate in overlay.subviews)
        if ([candidate isKindOfClass:LNTouchImageView.class] && candidate.tvzIsRipple) trail=candidate;
    TVZ_CONTROLS_CHECK(trail && TVZControlPoint(trail.center,180,200) &&
        TVZControlClose(trail.animationDuration,0.2), @"image trail missed speed or offset");
    contact.fillImage=nil;
    window.touchContactConfig=contact;
    touch.tvzPoint=CGPointMake(160,250);
    [window sendTouchEvent:event];
    TVZ_CONTROLS_CHECK(TVZControlPoint(view.center,160,250), @"non-image touch was shifted");
    window.trackingEnabled=NO;
    [view removeFromSuperview];
    TVZ_CONTROLS_CHECK(!view.isAnimating, @"detached GIF did not stop");
    contact.fillImage=red; contact.tvzGIFPlaybackRate=2; window.touchContactConfig=contact;
    touch.tvzPhase=UITouchPhaseBegan; [window sendTouchEvent:event];
    view=(LNTouchImageView *)[overlay viewWithTag:1001];
    TVZ_CONTROLS_CHECK(view && !view.isAnimating && TVZControlPoint(view.center,140,265), @"static image/Emoji offset failed");
    touch.tvzPhase=UITouchPhaseEnded; [window sendTouchEvent:event];
    TVZ_CONTROLS_CHECK(view.isFadingOut && TVZControlPoint(view.center,140,265), @"lift lost image offset");
    [NSObject cancelPreviousPerformRequestsWithTarget:view];
    for(UIView *candidate in overlay.subviews.copy) [candidate removeFromSuperview];
    overlay.hidden=YES;
    [defaults resetToDefaultValues];
    TVZTouchVizLoadImageControls(defaults,contact,ripple);
    TVZ_CONTROLS_CHECK(contact.tvzGIFPlaybackRate==1 && contact.tvzImageOffsetX==0 && contact.tvzImageOffsetY==0,
                      @"Reset did not restore speed/offset defaults");
    NSLog(@"PASS production UIKit: GIF rates, live refresh, raw hit coordinates, heading, four orientations, trails, static images and lift");
    return nil;
}
