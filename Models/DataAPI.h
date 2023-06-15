#import "ChartInsight-Swift.h"

@class DataAPI;

@interface DataAPI : NSObject

@property (nonatomic, strong) BarData *intradayBar;
@property (nonatomic) double maxHigh;
@property (nonatomic) double minLow;
@property (nonatomic) NSInteger countBars;
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

/// Fetch all price data from local DB and remainder from API
- (void) fetchInitialData;

- (BOOL) shouldFetchIntradayQuote;

- (void) fetchIntradayQuote;

/// Fetch price data after currentNewest from API
- (void) fetchNewerThanDate:(NSDate *)currentNewest;

- (NSDate *) dateFromBar:(BarData *)bar;

// called after 1000 bars are deleted
- (void) adjustNewestDateLoadedTo:(NSDate *)adjustedDate;

// called by StockData when a stock is removed or the chart is cleared before switching stocks
- (void) invalidateAndCancel;

@end
