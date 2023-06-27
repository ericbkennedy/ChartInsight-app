#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@class Comparison;
@class ProgressIndicator;

@protocol StockDataDelegate <NSObject>
- (void) showProgressIndicator;
- (void) stopProgressIndicator;
- (void) requestFailedWithMessage:(NSString *)message;
- (void) requestFinished:(NSDecimalNumber *)newPercentChange;
@end

@interface ScrollChartView : UIView <StockDataDelegate>

@property (nonatomic) CGFloat barUnit;
@property (nonatomic) CGFloat pxWidth;
@property (nonatomic) CGFloat svWidth;
@property (nonatomic) CGFloat xFactor;

@property (strong, nonatomic) Comparison *comparison;
@property (strong, nonatomic) ProgressIndicator	*progressIndicator; // reference to WatchlistVC property

/// Create rendering context to match scrollChartViews.bounds. Called on initial load and after rotation
- (void) resize;

/// Ensure any pending requests for prior comparison are invalidated and set stockData.delegate = nil
- (void) clearChart;

/// Render charts for the stocks in scrollChartView.comparison and fetch data as needed
- (void) loadChart;

/// Enlarged screenshot of chart under user's finger with a bar highlighted if coordinates match
- (UIImage *) magnifyBarAtX:(CGFloat)x y:(CGFloat)y;

/// Clear prior pressedBar after user starts a long press gesture
- (void) resetPressedBar;

/// Horizontally scale chart image during pinch/zoom gesture and calculate change in bars shown for scaleChart call
- (void) scaleChartImage:(CGFloat)newScale withCenter:(CGFloat)touchMidpoint;

/// Complete pinch/zoom transformation by rerendering the chart with the newScale
/// Uses scaleShift set by resizeChartImage so the rendered chart matches the temporary transformation
- (void) scaleChart:(CGFloat)newScale;

/// User panned WatchlistViewController by barsShifted. Resize and rerender chart.
- (void) updateMaxPercentChangeWithBarsShifted:(NSInteger)barsShifted;

/// Redraw charts without loading any data if a stock color, chart type or technical changes
- (void) redrawCharts;

@end
