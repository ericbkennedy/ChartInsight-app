#import "DataAPI.h"

 // forward declaration to avoid circular header inclusion
@class FundamentalAPI;
@class Series;

// when comparing against the present, we want to refresh the current

@interface StockData : NSObject {
    @private
    BarStruct   *dailyData;     // for parallelism, dataAPI writes to a separate block of memory
    BarStruct   *barData;       // points to dailyData except for monthly or weekly
    BOOL sma50, sma200, bb20;
    double pxHeight, sparklineHeight, volumeBase, volumeHeight;
    dispatch_queue_t concurrentQueue;
    
    @public
    double      maxVolume;
    NSInteger         bars, dailyBars, oldestBarShown, newestBarShown;
    BOOL        ready;
    BOOL        busy;
    CGFloat     xFactor, yFloor, yFactor, barUnit;
    NSInteger pointCount, redPointCount, lastMonth, year, redBarCount, whiteBarCount, monthCount, blackCount, redCount;
    CGPoint    *points, *redPoints, *movingAvg1, *movingAvg2, *ubb, *mbb, *lbb, *monthLines, *grids;
    CGFloat    *fundamentalAlignments;
    NSInteger  movingAvg1Count, movingAvg2Count, bbCount, hollowRedCount, filledGreenCount;
    NSInteger oldestReport, newestReport;
    CGRect          *redBars, *hollowRedBars, *greenBars, *filledGreenBars, *redVolume, *blackVolume;
}

@property (strong, nonatomic) Series *series;
@property (strong, nonatomic) NSMutableArray *monthLabels;
@property (strong, nonatomic) NSCalendar *gregorian;
@property (strong, nonatomic) NSDecimalNumber *percentChange;  // only for this stock
@property (strong, nonatomic) NSDecimalNumber *chartPercentChange;  // for all stocks

@property (strong, nonatomic) NSDecimalNumber *maxHigh;
@property (strong, nonatomic) NSDecimalNumber *minLow;
@property (strong, nonatomic) NSDecimalNumber *scaledLow;
@property (strong, nonatomic) NSDecimalNumber *lastPrice;
@property (strong, nonatomic) NSDecimalNumber *bookValue;

@property (strong, nonatomic) DataAPI *api;
@property (nonatomic) CGContextRef offscreenContext;
@property (strong, nonatomic) NSDateComponents *days;
@property (strong, nonatomic) NSDecimalNumber *lastSplitRatio;
@property (strong, nonatomic) NSDecimalNumber *chartBase;
@property (strong, nonatomic) NSMutableArray *reportBarIndex;

@property (strong, nonatomic) FundamentalAPI *fundamentalAPI;
@property (strong, nonatomic) NSDate *oldest;
@property (strong, nonatomic) NSDate *newest;   // newest date loaded, not the newest date shown

@property (nonatomic, assign) id delegate;

- (void) setPxHeight:(double)h withSparklineHeight:(double)s;

- (BarStruct *) barAtIndex:(NSInteger)index setUpClose:(BOOL *)upClose;

- (NSDictionary *) infoForBarAtIndex:(NSInteger)index;

- (NSString *) monthName:(NSInteger)month;

- (NSInteger) newestBarShown;

- (void) setNewestBarShown:(NSInteger)offsetBar;      // called after rotation

- (void) initWithDaysAgo:(NSInteger)daysAgo;

- (void) summarizeByDateFrom:(NSInteger)startCalculation oldBars:(NSInteger)oldBars;

- (NSDecimalNumber *) shiftRedraw:(NSInteger)barsShifted withBars:(NSInteger)maxBarOffset;

- (void) updateHighLow;

- (void) updateLayer:(NSDecimalNumber *)maxPercentChange forceRecompute:(BOOL)force;

- (void) APILoadedHistoricalData:(DataAPI *)dp;

- (void) APILoadedIntraday:(DataAPI *)dp;

- (void) APIFailed:(NSString *)message;

- (void) APICanceled:(DataAPI *) dp;

// Note this takes doubles even on 32 bit platforms because a double modulo function is used
- (double) pxAlign:(double)raw alignTo:(double)alignTo;

@end
