
typedef struct CBarData {
    NSInteger year, month, day;
    double open, high, low, close, adjClose, volume, movingAvg1, movingAvg2, mbb, stdev, splitRatio;
} BarStruct;

@class DataAPI;

@interface DataAPI : NSObject {
    double maxHigh, minLow, maxVolume;
    
    @public
    BarStruct *cArray;
    BarStruct intradayBar;
    NSInteger existingBars;
    NSInteger countBars, dataOffset;
}

@property (nonatomic, assign) id delegate;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic) NSInteger seriesId;
@property (strong, nonatomic) NSDate *nextClose;
@property (strong, nonatomic) NSDate *requestOldestDate;
@property (strong, nonatomic) NSDate *requestNewestDate;
@property (strong, nonatomic) NSDate *oldestDate;
@property (strong, nonatomic) NSDate *newestDate;
@property (strong, nonatomic) NSDateFormatter *dateFormatter;
@property (strong, nonatomic) NSCalendar *gregorian;

- (id) init;

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

- (NSString *)URLEncode:(NSString *)string;     // called by stock data for infoForPressedBar

@end
