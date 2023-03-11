#import "ProgressIndicator.h"
#import <QuartzCore/QuartzCore.h>

@implementation ProgressIndicator

- (id)initWithFrame:(CGRect)frame {
    
    if (self = [super initWithFrame:frame]) {
        
        [self setProgressView:[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar]];
        [self.progressView setFrame:frame];
        [self addSubview:self.progressView];
        
        // Create the timer object
        self.timer = nil;
    }
    return self;
}

- (BOOL) isOpaque {
    return NO;
}

- (void) reset {
    [self.timer invalidate];
    self.activeDownloads = self.progressNumerator = 0.;
}

- (void) startAnimating {
    self.activeDownloads += 1000.;
    if (self.timer == nil) {
        [self setHidden:NO];
        // use [NSTimer alloc] to ensure it gets allocated to higher priority modes than static initializers would
        
        [self setTimer:[[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:0.1] interval:0.1 target:self selector:@selector(updateActivityIndicator:) userInfo:nil repeats:YES]];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:UITrackingRunLoopMode];
    }
    
    [self.progressView setProgress:(self.progressNumerator / self.activeDownloads) animated:NO]; // or it will animate backwards!
    [self setHidden:NO];
    
}

- (void) updateActivityIndicator:(NSTimer *)incomingTimer {
    double progressAchieved = self.progressView.progress;
    if (progressAchieved == 1.0) {
        [self setHidden:YES];
        [self.timer invalidate];
        [self setTimer:nil];
        return;
    }
    
    // timeout is 60 seconds, so ensure that a failed download doesn't reach 1.0 before timeout
    // (1.0 / 70) * 0.1 = 0.00142

    if (self.activeDownloads <= 1 || self.progressNumerator > self.activeDownloads) {
        // TO DO: figure out why progressNumerator goes past activeDownloads without a timeout canceling the timer
        while (progressAchieved < 1) {
            progressAchieved += 0.25;
            [self.progressView setProgress:progressAchieved animated:YES];
        }
        [self.progressView setProgress:1.0 animated:YES];

        return;
    } else if (self.progressView.progress < .7) {
        self.progressNumerator = self.progressNumerator + 25.;
        progressAchieved = self.progressNumerator / self.activeDownloads;
    } else {
        self.progressNumerator += 1.;
        progressAchieved = self.progressNumerator / self.activeDownloads;
    }
    [self.progressView setProgress:progressAchieved animated:YES];
}

- (void) stopAnimating {
    double progressAchieved = self.progressView.progress;

    if (self.activeDownloads >= 1000.) {
        //    When a process completes, subtract its share of progress (progressNumerator / activeDownloads) and remove it from activeDownloads
        self.progressNumerator -= (self.progressNumerator / self.activeDownloads);
        self.activeDownloads -= 1000.;
        
        double progressCalc = 1.0; // (self.progressNumerator / self.activeDownloads);
        [self.progressView setProgress:progressCalc animated:YES];
    } else {
        
        while (progressAchieved < 1) {
            progressAchieved += 0.25;
            [self.progressView setProgress:progressAchieved animated:YES];
        }
        
        [self setHidden:YES];
        [self.timer invalidate];
        [self setTimer:nil];
    }
}

@end
