#import <QuartzCore/QuartzCore.h>
#import "Comparison.h"
#import "ProgressIndicator.h"

@class ScrollChartController;

@interface ScrollChartController : UIView {
    @public
    CGFloat         xFactor, svWidth, pxWidth, barUnit, svHeight, maxWidth, scaledWidth, pxHeight;
    BOOL            showDotGrips;
    
    @private
    CGFloat         pt2px, gripOffset, scaleShift, sparklineHeight;
}

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

- (UIImage *) screenshot;

- (UIImage *) magnifyBarAtX:(CGFloat)x y:(CGFloat)y;

- (void) resetPressedBar;

- (NSDictionary *) infoForPressedBar;

- (void) resize;       // used when WebView is shown and when RVC rotates
- (void) resizeChart:(CGFloat)newScale;
- (void) resizeChartImage:(CGFloat)newScale withCenter:(CGFloat)touchMidpoint;

- (void) requestFailedWithMessage:(NSString *)message;

- (void) requestFinished:(NSDecimalNumber *)newPercentChange;

- (void) updateMaxPercentChangeWithBarsShifted:(NSInteger)barsShifted;

- (void) redrawCharts;

@end