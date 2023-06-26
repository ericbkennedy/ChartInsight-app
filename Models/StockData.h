#import "ChartInsight-Swift.h" // for Stock and other Swift classes

@interface StockData : NSObject<DataFetcherDelegate>

@property (nonatomic) NSInteger oldestBarShown;
@property (nonatomic) CGFloat xFactor;
@property (nonatomic) CGFloat yFloor;
@property (nonatomic) CGFloat yFactor;
@property (nonatomic) CGFloat barUnit;
@property (nonatomic, strong) NSArray <NSNumber *> *fundamentalAlignments; // contains CGFloat
@property (nonatomic, strong) NSArray <NSValue *> *monthLines; // value = CGPoint

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
@property (nonatomic, strong) NSArray <NSValue *> *points;
@property (nonatomic, strong) NSArray <NSValue *> *redPoints;
@property (nonatomic, strong) NSArray <NSValue *> *movingAvg1;
@property (nonatomic, strong) NSArray <NSValue *> *movingAvg2;
@property (nonatomic, strong) NSArray <NSValue *> *upperBollingerBand;
@property (nonatomic, strong) NSArray <NSValue *> *middleBollingerBand;
@property (nonatomic, strong) NSArray <NSValue *> *lowerBollingerBand;

// CGRect values
@property (nonatomic, strong) NSArray <NSValue *> *greenBars;
@property (nonatomic, strong) NSArray <NSValue *> *filledGreenBars;
@property (nonatomic, strong) NSArray <NSValue *> *hollowRedBars;
@property (nonatomic, strong) NSArray <NSValue *> *redBars;
@property (nonatomic, strong) NSArray <NSValue *> *redVolume;
@property (nonatomic, strong) NSArray <NSValue *> *blackVolume;

@property (strong, nonatomic) Stock *stock;
@property (strong, nonatomic) NSArray <NSString *> *monthLabels;
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

/// Count of total bars (either monthly, weekly or daily) which determines the oldest date available for display
- (NSInteger) periodCount;

/// Return the number of bars at the newBarUnit scale to check if one stock in a comparison
/// will limit the date range that can be charted in the comparison
- (NSInteger) maxPeriodSupportedForBarUnit:(CGFloat)newBarUnit;

- (NSString *) monthName:(NSInteger)month;

- (NSInteger) newestBarShown;

- (void) setNewestBarShown:(NSInteger)offsetBar;      // called after rotation

- (void) fetchStockData;

- (void) updatePeriodDataByDayWeekOrMonth;

- (NSDecimalNumber *) shiftRedraw:(NSInteger)barsShifted withBars:(NSInteger)maxBarOffset;

- (void) updateHighLow;

- (void) updateLayer:(NSDecimalNumber *)maxPercentChange forceRecompute:(BOOL)force;

// Note this takes doubles even on 32 bit platforms because a double modulo function is used
- (double) pxAlign:(double)raw alignTo:(double)alignTo;


/// Returns all fundamental metric keys or [] if fundamentals aren't loaded
- (NSArray <NSString *> *) fundamentalKeys;

/// Metric value (or .notANumber) for a report index and metric key
- (NSDecimalNumber *) fundamentalValueForReport:(NSInteger)report metric:(NSString *)metric;

// Will invalidate the NSURLSession used to fetch price data and clear references to trigger dealloc
- (void) invalidateAndCancel;

@end
