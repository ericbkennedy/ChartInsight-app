
@interface ProgressIndicator : UIView {
   @public
    double activeDownloads;          // 1000 x active requests
    double progressNumerator;        // divide by active downloads to get value of progressIndicator
}

@property (nonatomic, strong) UIProgressView	*progressView;
@property (nonatomic, strong) NSTimer           *timer;

- (void) reset;

- (void) startAnimating;

- (void) stopAnimating;

@end


/* Progress Indicators go from .0 to 1. and it needs to handle multiple requests.
 
 progressIndicator.value =  progressNumerator / activeDownloads;
 
 Each second, progressNumerator += 0.025 * activeDownloads so if the requests times out at 30 seconds it will be incomplete
 
 When a process completes, subtract its share of progress (progressNumerator / activeDownloads) and remove it from activeDownloads
 
 This might look a littl strange on fast connections, since it could finish in less than 1 second.  But that's ok.
 
 */