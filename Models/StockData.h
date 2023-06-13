#import "DataAPI.h"

 // forward declaration to avoid circular header inclusion
@class FundamentalAPI;
@class Stock;

// when comparing against the present, we want to refresh the current

@interface StockData : NSObject 

@property (nonatomic) NSInteger dailyBars;
@property (nonatomic) NSInteger oldestBarShown;
@property (nonatomic) NSInteger monthCount;
@property (nonatomic) NSInteger movingAvg1Count;
@property (nonatomic) NSInteger movingAvg2Count;
@property (nonatomic) NSInteger bbCount;
@property (nonatomic) NSInteger hollowRedCount;
@property (nonatomic) NSInteger filledGreenCount;
@property (nonatomic) CGFloat xFactor;
@property (nonatomic) CGFloat yFloor;
@property (nonatomic) CGFloat yFactor;
@property (nonatomic) CGFloat barUnit;
@property (nonatomic) CGFloat *fundamentalAlignments;
@property (nonatomic) CGPoint *monthLines;

@property (nonatomic) double maxVolume;
@property (nonatomic) NSInteger bars;
@property (nonatomic) BOOL      ready;
@property (nonatomic) BOOL      busy;
@property (nonatomic) NSInteger pointCount;
@property (nonatomic) NSInteger redPointCount;
@property (nonatomic) NSInteger lastMonth;
@property (nonatomic) NSInteger year;
@property (nonatomic) NSInteger redBarCount;
@property (nonatomic) NSInteger whiteBarCount;
@property (nonatomic) NSInteger blackCount;
@property (nonatomic) NSInteger redCount;
@property (nonatomic) NSInteger oldestReport;
@property (nonatomic) NSInteger newestReport;
@property (nonatomic) CGPoint  *points;
@property (nonatomic) CGPoint  *redPoints;
@property (nonatomic) CGPoint  *movingAvg1;
@property (nonatomic) CGPoint  *movingAvg2;
@property (nonatomic) CGPoint  *ubb;
@property (nonatomic) CGPoint  *mbb;
@property (nonatomic) CGPoint  *lbb;
@property (nonatomic) CGPoint  *grids;

@property (nonatomic) CGRect  *greenBars;
@property (nonatomic) CGRect  *filledGreenBars;
@property (nonatomic) CGRect  *hollowRedBars;
@property (nonatomic) CGRect  *redBars;
@property (nonatomic) CGRect  *redVolume;
@property (nonatomic) CGRect  *blackVolume;

@property (strong, nonatomic) Stock *stock;
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

// Will invalidate the NSURLSession used to fetch price data and clear references to trigger dealloc
- (void) invalidateAndCancel;

@end
