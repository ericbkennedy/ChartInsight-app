#import <QuartzCore/QuartzCore.h>
#import "Comparison.h"
#import "ProgressIndicator.h"

@class ScrollChartView;

@interface ScrollChartView : UIView

@property (nonatomic) CGFloat barUnit;
@property (nonatomic) CGFloat pxWidth;
@property (nonatomic) CGFloat svWidth;
@property (nonatomic) CGFloat xFactor;

@property (strong, nonatomic) Comparison *comparison;
@property (strong, nonatomic) NSCalendar *gregorian;
@property (strong, nonatomic) ProgressIndicator	*progressIndicator;

- (NSInteger) maxBarOffset;

- (void) resetDimensions;

- (void) createLayerContext;

- (void) removeStockAtIndex:(NSInteger)i;

- (void) renderCharts;

- (void) clearChart;

- (void) showProgressIndicator;

- (void) stopProgressIndicator;

- (void) loadChart;

/// Enlarged screenshot of chart under user's finger with a bar highlighted if coordinates match
- (UIImage *) magnifyBarAtX:(CGFloat)x y:(CGFloat)y;

/// Clear prior pressedBar after user starts a long press gesture
- (void) resetPressedBar;

- (void) resize;       // used when WebView is shown and when RVC rotates
- (void) resizeChart:(CGFloat)newScale;
- (void) resizeChartImage:(CGFloat)newScale withCenter:(CGFloat)touchMidpoint;

- (void) requestFailedWithMessage:(NSString *)message;

- (void) requestFinished:(NSDecimalNumber *)newPercentChange;

- (void) updateMaxPercentChangeWithBarsShifted:(NSInteger)barsShifted;

- (void) redrawCharts;

@end
