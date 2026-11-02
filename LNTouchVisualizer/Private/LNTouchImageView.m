//
//  LNTouchSpotView.m
//  LNTouchVisualizer
//
//  Created by Joseph Blau on 11/30/17.
//  Copyright © 2017 conopsys. All rights reserved.
//

#import "LNTouchImageView.h"

@implementation LNTouchImageView

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window && self.image.images.count > 1) {
        self.animationImages = self.image.images;
        self.animationDuration = self.image.duration;
        self.animationRepeatCount = 0;
        [self startAnimating];
    } else {
        [self stopAnimating];
        self.animationImages = nil;
    }
}

@end
