
typedef struct CBarData {
    NSInteger year, month, day;
    double open, high, low, close, adjClose, volume, movingAvg1, movingAvg2, mbb, stdev, splitRatio;
} BarStruct;

@class DataAPI;

@interface DataAPI : NSObject {
    // public BarStruct iVars so StockData can memcpy values from this DataAPI
    @public
    BarStruct *cArray;
    BarStruct intradayBar;
}

@property (nonatomic) double maxHigh;
@property (nonatomic) double minLow;
@property (nonatomic) NSInteger existingBars;
@property (nonatomic) NSInteger countBars;
@property (nonatomic) NSInteger dataOffset;
@property (nonatomic, assign) id delegate;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic) NSInteger stockId;
@property (strong, nonatomic) NSDate *nextClose;
@property (strong, nonatomic) NSDate *requestOldestDate;
@property (strong, nonatomic) NSDate *requestNewestDate;
@property (strong, nonatomic) NSDate *oldestDate;
@property (strong, nonatomic) NSDate *newestDate;
@property (strong, nonatomic) NSDateFormatter *dateFormatter;
@property (strong, nonatomic) NSCalendar *gregorian;

- (instancetype) init;

- (NSInteger) maxBars;

- (void) fetchInitialData;

- (BOOL) shouldFetchIntradayQuote;

- (void) fetchIntradayQuote;

// StockData sets requestStart to avoid requesting dates prior to IPO
- (void) fetchOlderDataFrom:(NSDate *)requestStart untilDate:(NSDate *)currentOldest;

- (void) fetchNewerThanDate:(NSDate *)currentNewest screenBarWidth:(NSInteger)screenBarWidth;

- (BarStruct *) getCBarData;

- (void) setBarData:(BarStruct *)barData;

- (NSDate *) dateFromBar:(BarStruct)bar;

// called after 1000 bars are deleted
- (void) adjustNewestDateLoadedTo:(NSDate *)adjustedDate;

// called by StockData when a stock is removed or the chart is cleared before switching stocks
- (void) invalidateAndCancel;

- (NSString *)URLEncode:(NSString *)string;

@end
