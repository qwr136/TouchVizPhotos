//
//  LNTouchSpotView.m
//  LNTouchVisualizer
//
//  Created by Joseph Blau on 11/30/17.
//  Copyright © 2017 conopsys. All rights reserved.
//

#import "LNTouchImageView.h"
#import "TVZTouchVizImageControlMath.h"

@implementation LNTouchImageView
@synthesize tvzGIFPlaybackRate = _tvzGIFPlaybackRate;

- (double)tvzGIFPlaybackRate {
    return _tvzGIFPlaybackRate > 0.0 ? _tvzGIFPlaybackRate : 1.0;
}

- (void)setTvzGIFPlaybackRate:(double)tvzGIFPlaybackRate {
    double rate = TVZTouchVizPlaybackRate(tvzGIFPlaybackRate);
    if (self.tvzGIFPlaybackRate == rate) return;
    _tvzGIFPlaybackRate = rate;
    if (self.window && self.image.images.count > 1) [self tvz_startGIFPlayback];
}

- (void)tvz_startGIFPlayback {
    if (!self.window || self.image.images.count < 2) return;
    [self stopAnimating];
    self.animationImages = self.image.images;
    self.animationDuration = TVZTouchVizPlaybackDuration(self.image.duration, self.tvzGIFPlaybackRate);
    self.animationRepeatCount = 0;
    [self startAnimating];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && self.image.images.count > 1) {
        [self tvz_startGIFPlayback];
    } else {
        [self stopAnimating];
        self.animationImages = nil;
    }
}

@end
