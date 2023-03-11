
typedef struct CBarData {
    NSInteger year, month, day;
    double open, high, low, close, adjClose, volume, movingAvg1, movingAvg2, mbb, stdev, splitRatio;
} BarStruct;

// NSDate category
@interface NSDate (DataAPI)
- (NSInteger) formatDate:(NSCalendar *)calendar;
- (BOOL) isHoliday:(NSCalendar *)calendar;
- (BOOL) isTodayIntraday;
- (NSDate *) nextTradingDate:(NSCalendar *)calendar;
@end

@class DataAPI;

@interface DataAPI : NSObject {
    double maxHigh, minLow, maxVolume;
    
    @public
    BarStruct *cArray;
    BarStruct intradayBar;
    NSInteger existingBars;
    BOOL intraday;
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
@property (strong, nonatomic) NSCalendar *gregorian;

- (id) init;

- (NSInteger) maxBars;

- (void) getInitialData;

- (void) getIntradayQuote;

// StockData sets requestStart to avoid requesting dates prior to IPO
- (void) getOlderDataFrom:(NSDate *)requestStart untilDate:(NSDate *)currentOldest;

- (void) getNewerThanDate:(NSDate *)currentNewest screenBarWidth:(NSInteger)screenBarWidth;

- (BarStruct *) getCBarData;

- (void) setBarData:(BarStruct *)barData;

- (NSDate *) dateFromBar:(BarStruct)bar;

// called after 1000 bars are deleted
- (void) adjustNewestDateLoadedTo:(NSDate *)adjustedDate;

- (NSString *)URLEncode:(NSString *)string;     // called by stock data for infoForPressedBar

@end
