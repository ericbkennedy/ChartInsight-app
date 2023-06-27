#import "ChartInsight-Swift.h" // for Stock and other Swift classes

@interface StockData : NSObject<DataFetcherDelegate>

@property (nonatomic) NSInteger newestBarShown;
@property (nonatomic) NSInteger oldestBarShown;
@property (nonatomic) CGFloat xFactor;
@property (nonatomic) CGFloat yFloor;
@property (nonatomic) CGFloat yFactor;
@property (nonatomic) CGFloat barUnit;

@property (nonatomic) double maxVolume;
@property (nonatomic) BOOL      ready;
@property (nonatomic) BOOL      busy;
@property (nonatomic) NSInteger lastMonth;
@property (strong, nonatomic) NSDate *oldest;
@property (nonatomic) NSInteger oldestReport;
@property (nonatomic) NSInteger oldestReportInView;
@property (strong, nonatomic) NSDate *newest;   // newest date loaded, not the newest date shown
@property (nonatomic) NSInteger newestReport;
@property (nonatomic) NSInteger newestReportInView;

@property (nonatomic, strong) ChartElements *chartElements;
@property (strong, nonatomic) Stock *stock;

/// Bars (either monthly, weekly or daily) which determines the oldest date available for display and is exposed for periodData.count
@property (nonatomic, strong) NSMutableArray<BarData *> *periodData;
@property (strong, nonatomic) NSCalendar *gregorian;
@property (strong, nonatomic) NSDecimalNumber *percentChange;  // only for this stock
@property (strong, nonatomic) NSDecimalNumber *chartPercentChange;  // for all stocks

@property (strong, nonatomic) NSDecimalNumber *maxHigh;
@property (strong, nonatomic) NSDecimalNumber *minLow;
@property (strong, nonatomic) NSDecimalNumber *scaledLow;
@property (strong, nonatomic) NSDecimalNumber *lastPrice;

@property (strong, nonatomic) NSDecimalNumber *chartBase;

@property (nonatomic, assign) id delegate;

- (void) setPxHeight:(double)h withSparklineHeight:(double)s;

- (BarData *) barAtIndex:(NSInteger)index setUpClose:(BOOL *)upClose;

/// Return the number of bars at the newBarUnit scale to check if one stock in a comparison
/// will limit the date range that can be charted in the comparison
- (NSInteger) maxPeriodSupportedForBarUnit:(CGFloat)newBarUnit;

- (NSInteger) newestBarShown;

- (void) setNewestBarShown:(NSInteger)offsetBar;      // called after rotation

- (void) fetchStockData;

- (void) updatePeriodDataByDayWeekOrMonth;

- (NSDecimalNumber *) shiftRedraw:(NSInteger)barsShifted withBars:(NSInteger)maxBarOffset;

- (void) updateHighLow;

- (void) recompute:(NSDecimalNumber *)maxPercentChange forceRecompute:(BOOL)force;

/// Create a readonly copy of the values mutated on a background thread by computeChart for use on the mainThread
/// This is primarily needed for intraday updates which can return fast enough (especially in the simulator) to be ready
/// to mutate the array values while ScrollChartView is iterating through the arrays.
- (void) copyArrayValues;

// Note this takes doubles even on 32 bit platforms because a double modulo function is used
- (double) pxAlign:(double)raw alignTo:(double)alignTo;


/// Returns all fundamental metric keys or [] if fundamentals aren't loaded
- (NSArray <NSString *> *) fundamentalKeys;

/// Metric value (or .notANumber) for a report index and metric key
- (NSDecimalNumber *) fundamentalValueForReport:(NSInteger)report metric:(NSString *)metric;

// Will invalidate the NSURLSession used to fetch price data and clear references to trigger dealloc
- (void) invalidateAndCancel;

@end
