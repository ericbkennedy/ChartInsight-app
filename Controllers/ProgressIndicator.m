#import "ProgressIndicator.h"
#import <QuartzCore/QuartzCore.h>

@implementation ProgressIndicator

- (id)initWithFrame:(CGRect)frame {
    
    if (self = [super initWithFrame:frame]) {
        CGFloat x = 0, y = 0; // frame.origin.x, y = frame.origin.y;
        
        [self setProgressView:[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar]];
        [self.progressView setFrame:CGRectMake(x + 5, y + 45, 150, 10)];
        [self.progressView setProgressTintColor:[UIColor whiteColor]];
        [self.progressView setTrackTintColor:[UIColor darkGrayColor]];
        [self addSubview:self.progressView];
        UILabel *downloading = [UILabel new];
        [downloading setText:@"Downloading..."];
        [downloading setTextColor:[UIColor whiteColor]];
        [downloading setBackgroundColor:[UIColor clearColor]];
        [downloading setFrame:CGRectMake(x + 20, y + 15, 140, 20)];
        [self addSubview:downloading];
        [self setBackgroundColor:[UIColor colorWithWhite:0.4 alpha:0.7]];
        self.layer.cornerRadius = 15.0f;
        self.layer.masksToBounds = YES;
        
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
    activeDownloads = progressNumerator = 0.;
}

- (void) startAnimating {
    activeDownloads += 1000.;
    if (self.timer == nil) {
        [self setHidden:NO];
        // use [NSTimer alloc] to ensure it gets allocated to higher priority modes than static initializers would
        
        [self setTimer:[[NSTimer alloc] initWithFireDate:[NSDate dateWithTimeIntervalSinceNow:0.1] interval:0.1 target:self selector:@selector(updateActivityIndicator:) userInfo:nil repeats:YES]];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:UITrackingRunLoopMode];
    }
    
    [self.progressView setProgress:(progressNumerator / activeDownloads) animated:NO]; // or it will animate backwards!
    [self setHidden:NO];
    
}

- (void) updateActivityIndicator:(NSTimer *)incomingTimer {
    
    // timeout is 60 seconds, so ensure that a failed download doesn't reach 1.0 before timeout
    // (1.0 / 70) * 0.1 = 0.00142
    
 
    
    if (activeDownloads <= 1 || progressNumerator > activeDownloads) {
        // TO DO: figure out why progressNumerator goes past activeDownloads without a timeout canceling the timer
        [self.progressView setProgress:1.0 animated:YES];
        [self setHidden:YES];
        [self.timer invalidate];
        [self setTimer:nil];
    } else if (self.progressView.progress < .7 ) {
        progressNumerator += 25.;
    } else {
         
       progressNumerator += 1.;
    }
    
    double progressCalc = (progressNumerator / activeDownloads);
    [self.progressView setProgress:progressCalc animated:YES];
}

- (void) stopAnimating {

 
    if (activeDownloads >= 1000.) {
        //    When a process completes, subtract its share of progress (progressNumerator / activeDownloads) and remove it from activeDownloads
        progressNumerator -= (progressNumerator / activeDownloads);
        activeDownloads -= 1000.;
        
        double progressCalc = (progressNumerator / activeDownloads);
        [self.progressView setProgress:progressCalc animated:YES];
    } else {
        [self.progressView setProgress:1.0 animated:YES];
        [self setHidden:YES];
        [self.timer invalidate];
        [self setTimer:nil];
    }
}

@end
