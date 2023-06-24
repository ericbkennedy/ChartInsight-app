#import "ChartInsight-Swift.h" // for BarData *
#import "StockData.h"

@interface StockData () {
@private
    BOOL sma50, sma200, bb20;
    double pxHeight, sparklineHeight, volumeBase, volumeHeight;
    dispatch_queue_t concurrentQueue;
    NSInteger _newestBarShown;
}
@property (nonatomic, strong) NSMutableArray<BarData *> *dailyData;
@property (nonatomic, strong) NSMutableArray<BarData *> *periodData;   // points to dailyData except for monthly or weekly
@property (nonatomic, copy) NSDictionary<NSString*, NSArray<NSDecimalNumber*>*> *fundamentalColumns;
@property (nonatomic, strong) DataFetcher *fetcher;
@property (nonatomic, strong) FundamentalFetcher *fundamentalFetcher;
@end

@implementation StockData

/// Get barData for period (month, week or day) at index with inout param indicating if close was up from prior day
- (BarData *) barAtIndex:(NSInteger)index setUpClose:(BOOL *)upClose {
    if (index >= self.periodCount) {
        return nil;
    }
    *upClose = YES;
    BarData *bar = self.periodData[index];
    
    if (index < self.periodCount - 2) { // check for up/down close
        if (bar.close < self.periodData[index + 1].close) {
            *upClose = NO;
        }
    } else if (self.periodData[index].close < self.periodData[index].open) {
        *upClose = NO;
    }
    return bar;
}

- (NSInteger) periodCount {
    return self.periodData.count;
}

- (NSInteger) newestBarShown { return _newestBarShown; }

- (void) setNewestBarShown:(NSInteger)offsetBar {         // avoid negative values for newest bar
    if (offsetBar < 0) {       
        _newestBarShown = 0;
    } else {
        _newestBarShown = offsetBar;
    }
}

- (void) setPxHeight:(double)h withSparklineHeight:(double)s {
    sparklineHeight = s;
    pxHeight = h - sparklineHeight;
    
    volumeHeight = 40 * UIScreen.mainScreen.scale;
    
    volumeBase = h - volumeHeight/2;

    self.chartBase = [[[NSDecimalNumber alloc] initWithDouble:(volumeBase - volumeHeight/2 - sparklineHeight)] autorelease];
}

// Will invalidate the NSURLSession used to fetch price data and clear references to trigger dealloc
- (void)invalidateAndCancel {
    // fundamentalFetcher uses the sharedSession so don't invalidate it
    [self.fundamentalFetcher setDelegate:nil];
    self.fundamentalFetcher = nil; // will trigger deinit on fundamentalFetcher
    [self.fetcher invalidateAndCancel];
    [self.fetcher setDelegate:nil];
    self.fetcher = nil;
}

- (void)dealloc {
    NSLog(@"%@ is being deallocated", self.stock.ticker);
    self.delegate = nil;
    // don't release memory I didn't alloc in StockData, like the gregorian calendar
    
    free(_blackVolume);
    free(_filledGreenBars);
    free(_fundamentalAlignments);
    free(_greenBars);
    free(_grids);
    free(_hollowRedBars);
    free(_lbb);
    free(_mbb);
    free(_monthLines);
    free(_movingAvg1);
    free(_movingAvg2);
    free(_points);
    free(_redBars);
    free(_redPoints);
    free(_redVolume);
    free(_ubb);

    dispatch_release(concurrentQueue);
    [super dealloc];
}

- (instancetype) init {
    [super init];
    _newestBarShown = _oldestReport = _newestReport = _movingAvg1Count = _movingAvg2Count = 0;
    _busy = _ready = NO;
    [self setPercentChange:[NSDecimalNumber one]];
    [self setChartPercentChange:[NSDecimalNumber one]];
    
    [self setMaxHigh:[NSDecimalNumber zero]];
    [self setMinLow:[NSDecimalNumber zero]];
    
    self.fetcher = [[DataFetcher alloc] init];
    self.dailyData = [NSMutableArray array];
    self.periodData = self.dailyData;
    
    [self setMonthLabels:[NSMutableArray arrayWithCapacity:50]];
    
    // TODO: replace with NSArray containing NSValue elements
    NSInteger maxBars = 2 * (UIScreen.mainScreen.bounds.size.height - 60) * UIScreen.mainScreen.scale;
    
    _blackVolume = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    _filledGreenBars = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    _fundamentalAlignments = (CGFloat *)malloc(sizeof(CGFloat)*99);
    _greenBars = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    _grids = (CGPoint*)malloc(sizeof(CGPoint)*20);
    _hollowRedBars = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    _lbb = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    _mbb = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    _monthLines = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    _movingAvg1 = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    _movingAvg2 = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    _points = (CGPoint*)malloc(sizeof(CGPoint) * maxBars * 6);
    _redBars = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    _redPoints = (CGPoint*)malloc(sizeof(CGPoint) * maxBars * 2);
    _redVolume = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    _ubb = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    
    [self setLastPrice:[NSDecimalNumber zero]];
    return self;
}

- (void) fetchStockData {
    NSDate *desiredDate = [NSDate date];
    
    [self updateBools];
    self.fetcher.requestNewest = desiredDate;
    [self.fetcher setRequestOldestWithStartString:self.stock.startDateString];
    [self setNewest:self.fetcher.requestOldest];
    
    self.fetcher.ticker = self.stock.ticker;
    self.fetcher.stockId = self.stock.id;
    self.fetcher.gregorian = self.gregorian;
    self.fetcher.delegate = self;
        
    NSString *concurrentName = [NSString stringWithFormat:@"com.chartinsight.%ld", self.stock.id];
    
    concurrentQueue = dispatch_queue_create([concurrentName UTF8String], DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_set_target_queue(concurrentQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));

    [self.fetcher fetchNewerThanDate:[NSDate distantPast]];

    if ([self.stock fundamentalList].length > 4) {
        [self.delegate performSelector:@selector(showProgressIndicator)];
        self.fundamentalFetcher = [[FundamentalFetcher alloc] init];
        [self.fundamentalFetcher getFundamentalsFor:self.stock withDelegate:self];
    }
}

/// FundamentalFetcher calls StockData with the columns parsed out of the API
- (void) fetcherLoadedFundamentals:(NSDictionary<NSString*, NSArray<NSDecimalNumber*>*>*) columns {
    self.fundamentalColumns = columns;
    
    if (self.busy == NO && self.periodCount > 1) {
        dispatch_barrier_sync(concurrentQueue, ^{ [self updateFundamentalAlignment];
                                                                            [self computeChart];    });
        [self.delegate performSelectorOnMainThread:@selector(requestFinished:) withObject:self.percentChange waitUntilDone:NO];
    } else {
        [self.delegate performSelectorOnMainThread:@selector(stopProgressIndicator) withObject:nil waitUntilDone:NO];
    }
}

/// Returns all fundamental metric keys or [] if fundamentals aren't loaded
- (NSArray <NSString *> *) fundamentalKeys {
    if (self.fundamentalColumns != nil && self.fundamentalColumns.count > 0) {
        return self.fundamentalColumns.allKeys;
    }
    return @[];
}

/// Metric value (or .notANumber) for a report index and metric key
- (NSDecimalNumber *) fundamentalValueForReport:(NSInteger)report metric:(NSString *)metric {
    if (self.fundamentalColumns != nil) {
        NSArray *valuesForMetric = self.fundamentalColumns[metric];
        if (valuesForMetric != nil && report < valuesForMetric.count) {
            return valuesForMetric[report];
        }
    }
    return NSDecimalNumber.notANumber;
}

// When calculating the simple moving average, there are 3 possible cases:
// 1. all values in self.periodData are new
//        Start with bar 0 and continue until the end
// 
// 2. adding self.barCount to the front
//        Start with bar 0 and continue until the first old bar
// 
// 3. adding self.barCount to the end
//        Start with the oldest bar and walk towards the start of the array to find the first empty moving average
// 
// For example, div LINE the ratio of the adjusted close varies slightly
- (void) calculateSMA {
    
    NSInteger oldest50available, oldest150available, oldest200available;
    oldest50available = self.periodCount - 50;
    oldest150available = self.periodCount - 150;
    oldest200available = self.periodCount - 200;
    
    if (oldest50available > 0) {
        double movingSum50 = 0.0f;
        double movingSum150 = 0.0f;
        
        // add last n self.barCount, then start subtracting i + n - 1 bar to compute average
    
        for (NSInteger i = self.periodCount - 1; i >= 0; i--) {
            movingSum50 += self.periodData[i].close;
            
            if (i < oldest50available) { 
                movingSum150 += self.periodData[i + 50].close;
                movingSum50 -= self.periodData[i + 50].close;
                if (i < oldest200available) {
                    movingSum150 -= self.periodData[i + 200].close; // i + n - 1, so for bar zero it subtracks bar 199 (200th bar)
                    self.periodData[i].movingAvg2 = (movingSum50 + movingSum150) / 200;
                } else if (i == oldest200available) {
                    self.periodData[i].movingAvg2 = (movingSum50 + movingSum150) / 200;
                }
                self.periodData[i].movingAvg1 = movingSum50 / 50;
                
            } else if (i == oldest50available) {            // already reached oldest available
                self.periodData[i].movingAvg1 = movingSum50 / 50;
            }
        }
    }
}

- (void) calculateBollingerBands {
    // Middle Band = 20-day simple moving average (SMA)
    // Upper Band = 20-day SMA + (20-day standard deviation of price x 2)
    // Lower Band = 20-day SMA - (20-day standard deviation of price x 2)
    // use regular close instead of adjusted close or the bollinger bands will deviate from price for stocks or ETFs with dividends
    
    NSInteger period = 20;
    NSInteger firstFullPeriod = self.periodCount - period;
    
    if (firstFullPeriod > 0) {
        double movingSum = 0.0f;
        double powerSumAvg = 0.0f;
        
        // add last n self.barCount, then start subtracting i + n - 1 bar to compute average
        
        for (NSInteger i = self.periodCount - 1; i >= 0; i--) {
            movingSum += self.periodData[i].close;
            
            if (i < firstFullPeriod) {
                movingSum -= self.periodData[i + period].close;
                
                self.periodData[i].mbb = movingSum / period;
                powerSumAvg += (self.periodData[i].close * self.periodData[i].close - self.periodData[i + period].close * self.periodData[i + period].close)/(period);
 
                self.periodData[i].stdev = sqrt(powerSumAvg - self.periodData[i].mbb * self.periodData[i].mbb);
                                 
            } else if (i >= firstFullPeriod) {
                powerSumAvg += (self.periodData[i].close * self.periodData[i].close - powerSumAvg)/(self.periodCount - i);
                 
                if (i == firstFullPeriod) {            // already reached oldest available
                    self.periodData[i].mbb = movingSum / period;
                    self.periodData[i].stdev = sqrt(powerSumAvg - self.periodData[i].mbb * self.periodData[i].mbb);
                 }
            }
        }
    }
}

// Align the array of fundamental data points to an offset into the self.periodData array
- (void) updateFundamentalAlignment {
    if (self.fundamentalFetcher != nil && self.fundamentalFetcher.isLoadingData == NO && self.fundamentalFetcher.columns.count > 0) {
        
        NSInteger i = 0, r = 0;
        for (r = 0; r < self.fundamentalFetcher.year.count; r++) {
            
            NSInteger lastReportYear = self.fundamentalFetcher.year[r].intValue;
            NSInteger lastReportMonth = self.fundamentalFetcher.month[r].intValue;
            
            while (i < self.periodCount && (self.periodData[i].year > lastReportYear ||  self.periodData[i].month > lastReportMonth)) {
                i++;
            }
            if (i < self.periodCount && self.periodData[i].year == lastReportYear && self.periodData[i].month == lastReportMonth) {
                
                [self.fundamentalFetcher setBarAlignment:i report:r];
            }
        }
    }   
}

// Called after shiftRedraw shifts self.oldestBarShown and newestBarShown during scrolling
- (void) updateHighLow {
    
    if (self.periodCount == 0) {
        NSLog(@"No bars so exiting");
        return;
    }
      
    if (self.oldestBarShown <= 0) {
        NSLog(@"resetting oldestBarShown %ld to MIN(50, %ld)", self.oldestBarShown, self.periodCount);
        self.oldestBarShown = MIN(50, self.periodCount);
    } else if (self.oldestBarShown >= self.periodCount) {
        self.oldestBarShown = self.periodCount -1;
    }
    
    double max = 0.0, min = 0.0;
    self.maxVolume = 0.0;
        
    for (NSInteger a = self.oldestBarShown; a >= _newestBarShown ; a--) {
        if (self.periodData[a].volume > self.maxVolume) {
            self.maxVolume = self.periodData[a].volume;
        }
        
        if (self.periodData[a].low > 0.0f) {
            if (min == 0.0f) {
                min = self.periodData[a].low;
            } else if (min > self.periodData[a].low) {
                min = self.periodData[a].low;
            }
        }
        
        if (max < self.periodData[a].high) {
            max = self.periodData[a].high;
        }
    }
    
    [self setMaxHigh:[[[NSDecimalNumber alloc] initWithDouble:max] autorelease]];
    [self setMinLow:[[[NSDecimalNumber alloc] initWithDouble:min] autorelease]];
    [self setScaledLow:self.minLow];

    if ([self.minLow doubleValue] > 0) {
        [self setPercentChange:[self.maxHigh decimalNumberByDividingBy:self.minLow]];
        
        if ([self.percentChange compare:self.chartPercentChange] == NSOrderedDescending) {
            [self setChartPercentChange:self.percentChange];
        }
        [self setScaledLow:[self.maxHigh decimalNumberByDividingBy:self.chartPercentChange]];
    }
    
    [self computeChart];
}

- (NSDecimalNumber *) shiftRedraw:(NSInteger)barsShifted withBars:(NSInteger)screenBarWidth {
    
    if (self.oldestBarShown + barsShifted >= self.periodCount) {
        NSLog(@"early return because oldestBarShown %ld + barsShifted %ld > %ld barCount", self.oldestBarShown, barsShifted, self.periodCount);
        return self.percentChange;
    }
    self.oldestBarShown += barsShifted;
        
    [self setNewestBarShown:(self.oldestBarShown - screenBarWidth)];     // handles negative values
        
    if (self.oldestBarShown <= 0) {  // nothing to show yet
        NSLog(@"%@ self.oldestBarShown is less than zero at %ld", self.stock.ticker, self.oldestBarShown);
        [self clearChart];

    } else if (self.busy) {
        // Avoid deadlock by limiting concurrentQueue to updateHighLow and didFinishFetch

        dispatch_sync(concurrentQueue,  ^{    [self updateHighLow];     });
        return self.percentChange;
    }

    if (0 == self.newestBarShown) {
        
        if ([self.fetcher shouldFetchIntradayQuote]) {
            self.busy = YES;
            [self.fetcher fetchIntradayQuote];

        } else if (self.fetcher.isLoadingData == NO && [self.fetcher.nextClose compare:[NSDate date]] == NSOrderedAscending) {
            // next close is in the past
            NSLog(@"api.nextClose %@ vs now %@", self.fetcher.nextClose, [NSDate date]);
            self.busy = YES;
            [self.delegate performSelectorOnMainThread:@selector(showProgressIndicator) withObject:nil waitUntilDone:NO];
            [self.fetcher fetchNewerThanDate:self.newest];
        }
    }
    
    dispatch_sync(concurrentQueue,  ^{    [self updateHighLow];     });
    
    return self.percentChange;
}

- (void) updateBools {
    
    BOOL sma50old = sma50, sma200old = sma200;
    
    sma50 = [[self.stock technicalList] rangeOfString:@"sma50"].length > 0 ? YES : NO;
    sma200 = [[self.stock technicalList] rangeOfString:@"sma200"].length > 0 ? YES : NO;
    
    if ((sma200 && sma200old == NO) || (sma50 && sma50old == NO)) {
        [self calculateSMA];
    }
    
    if ([[self.stock technicalList] rangeOfString:@"bollingerBand"].length > 0) {
        if (!bb20) {
            [self calculateBollingerBands];
        }
        bb20 = YES;
    } else {
        bb20 = NO;
    }

}

// Determines if the percent change has increased and we need to redraw
- (void) updateLayer:(NSDecimalNumber *)maxPercentChange forceRecompute:(BOOL)force {
    
    [self updateBools];
    
    double pctDifference = [[maxPercentChange decimalNumberBySubtracting:self.chartPercentChange] doubleValue];
    
    if (force || pctDifference > 0.02 ) {
        
        [self setChartPercentChange:maxPercentChange];
        
        [self setScaledLow:[self.maxHigh decimalNumberByDividingBy:self.chartPercentChange]];
        
        dispatch_sync(concurrentQueue, ^{   [self computeChart];    });
    } else {
        [self setChartPercentChange:maxPercentChange];
        [self setScaledLow:[self.maxHigh decimalNumberByDividingBy:self.chartPercentChange]];
    }
}

/// DataFetcher has an active download that must be allowed to finish or fail before accepting an additional request
- (void) fetcherCanceled {
    self.busy = NO;
    NSString *message = @"Canceled request";
    [self.delegate performSelectorOnMainThread:@selector(requestFailedWithMessage:) withObject:message waitUntilDone:NO];
}

/// DataFetcher failed downloading historical data or intraday data
-(void) fetcherFailed:(NSString *)message {
    self.busy = NO;
    NSLog(@"%@", message);
    [self.delegate performSelectorOnMainThread:@selector(requestFailedWithMessage:) withObject:message waitUntilDone:NO];
}

/// DataFetcher calls StockData with intraday price data
-(void) fetcherLoadedIntradayBar:(BarData *)intradayBar {
    
    // Avoid deadlock by limiting concurrentQueue to updateHighLow and fetcherLoaded*    

    dispatch_barrier_sync(concurrentQueue, ^{
            
        double oldMovingAvg1, oldMovingAvg2;
        
        NSDate *apiNewest = [self.fetcher dateFromBar:intradayBar];
        
        CGFloat dateDiff = [apiNewest timeIntervalSinceDate:[self newest]];
       // NSLog(@"intrday datediff is %f when comparing %@ to %@", dateDiff, [self newest], apiNewest);
        
        if (dateDiff > 84600) {
            NSLog(@"intraday moving %ld self.bars by 1", self.periodCount);
            [self.dailyData insertObject:intradayBar atIndex:0];
            // self.barCount may or may not increase; let summarizeByDate figure that out
            oldMovingAvg1 = oldMovingAvg2 = .0f;

        } else {
            oldMovingAvg1 = self.dailyData[0].movingAvg1;
            oldMovingAvg2 = self.dailyData[0].movingAvg2;
            [self.dailyData replaceObjectAtIndex:0 withObject:intradayBar];
        }
        
        [self setLastPrice:[[[NSDecimalNumber alloc] initWithDouble:self.dailyData[0].close] autorelease]];
        
        [self setNewest:apiNewest];

        // For intraday update to weekly or monthly chart, decrement self.oldestBarShown only if
        //    the intraday bar is for a different period (week or month) than the existing newest bar
        
        [self updatePeriodDataByDayWeekOrMonth];
        [self updateHighLow]; // must be a separate call to handle daysAgo shifting

        self.busy = NO;
    });
    
    [self.delegate performSelectorOnMainThread:@selector(requestFinished:) withObject:self.percentChange waitUntilDone:NO];
};

- (void) groupByWeek:(NSDate *)startDate dailyIndex:(NSInteger)iNewest weeklyIndex:(NSInteger)wi {
    
    // Note, we are going backwards, so the most recent daily close is the close of the week
    BarData *weeklyBar = [[BarData alloc] init];
    [self.periodData insertObject:weeklyBar atIndex:wi];
    weeklyBar.close = self.dailyData[iNewest].close;
    weeklyBar.adjClose = self.dailyData[iNewest].adjClose;
    weeklyBar.high = self.dailyData[iNewest].high;
    weeklyBar.low  = self.dailyData[iNewest].low;
    weeklyBar.volume = self.dailyData[iNewest].volume;
    weeklyBar.movingAvg1 = weeklyBar.movingAvg2 = weeklyBar.mbb = weeklyBar.stdev = 0.;
    
    NSInteger i = iNewest + 1;    // iNewest values already saved to self.periodData

    NSDateComponents *componentsToSubtract = [[NSDateComponents alloc] init];
    NSDateComponents *weekdayComponents = [self.gregorian components:NSCalendarUnitWeekday fromDate:startDate];

    // Get the previous Friday, convert it into an NSInteger and then group all dates LARGER than it into the current week
    // Friday is weekday 6 in Gregorian calendar, so subtract current weekday and -1 to get previous Friday
    [componentsToSubtract setDay: -1 - [weekdayComponents weekday]];
    NSDate *lastFriday = [self.gregorian dateByAddingComponents:componentsToSubtract toDate:startDate options:0];
    
    NSUInteger unitFlags = NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitYear;
    NSDateComponents *friday = [self.gregorian components:unitFlags fromDate:lastFriday];
    
    while (i < self.dailyData.count && 0 < 20000 * (self.dailyData[i].year - friday.year) + 100 * (self.dailyData[i].month - friday.month) + self.dailyData[i].day - friday.day) {
        
        if (self.dailyData[i].high > weeklyBar.high) {
            weeklyBar.high = self.dailyData[i].high;
        }
        if (self.dailyData[i].low < weeklyBar.low) {
            weeklyBar.low = self.dailyData[i].low;
        }
        weeklyBar.volume += self.dailyData[i].volume;
        i++;
    }
    
    weeklyBar.year = self.dailyData[i - 1].year;
    weeklyBar.month = self.dailyData[i - 1].month;
    weeklyBar.day = self.dailyData[i - 1].day;
    weeklyBar.open = self.dailyData[i - 1].open;
    
    if (i < self.dailyData.count) {
        wi++;
        [self groupByWeek:lastFriday dailyIndex:i weeklyIndex:wi];
    }
}

- (void) groupByMonthFromDailyIndex:(NSInteger)iNewest monthlyIndex:(NSInteger)mi {
    
    BarData *monthlyBar = [[BarData alloc] init];
    [self.periodData insertObject:monthlyBar atIndex:mi];
    
    // Note, we are going backwards, so the most recent daily close is the close of the week
    monthlyBar.close = self.dailyData[iNewest].close;
    monthlyBar.adjClose = self.dailyData[iNewest].adjClose;
    monthlyBar.high = self.dailyData[iNewest].high;
    monthlyBar.low  = self.dailyData[iNewest].low;
    monthlyBar.volume = self.dailyData[iNewest].volume;
    monthlyBar.year = self.dailyData[iNewest].year;
    monthlyBar.month = self.dailyData[iNewest].month;
    monthlyBar.movingAvg1 = monthlyBar.movingAvg2 = monthlyBar.mbb = monthlyBar.stdev = 0.;
    
    NSInteger i = iNewest + 1;    // iNewest values already saved to self.periodData
        
    while (i <  self.dailyData.count && self.dailyData[i].month == monthlyBar.month) {
        
        if (self.dailyData[i].high > monthlyBar.high) {
            monthlyBar.high = self.dailyData[i].high;
        }
        if (self.dailyData[i].low < monthlyBar.low) {
            monthlyBar.low = self.dailyData[i].low;
        }
        monthlyBar.volume += self.dailyData[i].volume;
        i++;
    }
    
    monthlyBar.open = self.dailyData[i - 1].open;
    monthlyBar.day = self.dailyData[i - 1].day;
    
    if (i <  self.dailyData.count) {
        mi++;
        [self groupByMonthFromDailyIndex:i monthlyIndex:mi];
    }
}

/// Return the number of bars at the newBarUnit scale to check if one stock in a comparison
/// will limit the date range that can be charted in the comparison
- (NSInteger) maxPeriodSupportedForBarUnit:(CGFloat)newBarUnit {
    return floor(self.dailyData.count / newBarUnit);
}

- (void) updatePeriodDataByDayWeekOrMonth {

    if (self.barUnit == 1.) {
        self.periodData = self.dailyData;
    } else if (self.barUnit > 3 && self.periodData == self.dailyData) {
        self.periodData = [NSMutableArray array];
    } else if (self.periodData != self.dailyData){ // switching between monthly and weekly
        [self.periodData removeAllObjects];
    }
    
    if (self.barUnit > 5) {
        [self groupByMonthFromDailyIndex:0 monthlyIndex:0];
    } else if (self.barUnit > 3) {
        [self groupByWeek:self.newest dailyIndex:0 weeklyIndex:0];
    }
    [self updateFundamentalAlignment];
    
    if (sma200 || sma50) {
        [self calculateSMA];
    }
    
    if (bb20) {
        [self calculateBollingerBands];
    }

    // don't call updateHighLow here because summarizeByDate doesn't consider daysAgo but updateHighLow must be called AFTER shifting newestBarShown
}

/// DataFetcher calls StockData with the array of historical price data
-(void) fetcherLoadedHistoricalData:(NSArray<BarData*> *)loadedData {

    /* Three cases since intraday updates are a separate callback:
     1. First request: [self.dailyData addObjectsFromArray:dataAPI.dailyData];
     2. Insert newer dates (not intraday update): [self.dailyData insertObjects:dataAPI.dailyData atIndexes:indexSet];
     3. Append older dates: [self.dailyData addObjectsFromArray:dataAPI.dailyData];
     */
    
    if (loadedData == nil || loadedData.count == 0) {
        return;
    }
    
    dispatch_barrier_sync(concurrentQueue, ^{
        BarData *newestBar = loadedData[0];
        NSDate *apiNewest = [self.fetcher dateFromBar:newestBar];
        
        if ( self.dailyData.count == 0) { // case 1. First request
            [self setNewest:apiNewest];
            [self setLastPrice:[[NSDecimalNumber alloc] initWithDouble:newestBar.close]];  // if daysAgo > 0, lastPrice will be off until all newer data is fetched
            [self setOldest:[self.fetcher oldestDate]];

            NSLog(@"%@ added %ld new barData.count to %ld exiting self.dailyData.count", self.stock.ticker, loadedData.count, self.dailyData.count);
            
            [self.dailyData addObjectsFromArray:loadedData];
            
        } else if ([self.newest compare:apiNewest] == NSOrderedAscending) {         // case 2. Newer dates
            NSLog(@"api is newer, so inserting %ld bars at start of dailyData", loadedData.count);
        
            for (NSInteger i = 0; i < loadedData.count; i++) {
                [self.dailyData insertObject:loadedData[i] atIndex:i];
            }

            [self setNewest:apiNewest];
            [self setLastPrice:[[NSDecimalNumber alloc] initWithDouble:newestBar.close]];  // if daysAgo > 0, lastPrice will be off until all newer data is fetched
            
        } else if ([self.oldest compare:[self.fetcher oldestDate]] == NSOrderedDescending) {    // case 3. Older dates
            
            [self.dailyData addObjectsFromArray:loadedData];
            
            NSLog(@"%@ older dates %ld new barData.count to %ld exiting self.dailyData.count", self.stock.ticker, loadedData.count, self.dailyData.count);
            
            [self setOldest:[self.fetcher oldestDate]];
        }
    
        [self updatePeriodDataByDayWeekOrMonth];
            
        [self updateHighLow];

        if ([self.fetcher shouldFetchIntradayQuote]) {
            self.busy = YES;
            [self.fetcher fetchIntradayQuote];
        } else {
            self.busy = NO;
            [self.delegate performSelectorOnMainThread:@selector(stopProgressIndicator) withObject:nil waitUntilDone:NO];
        }
      });
    
    NSLog(@"%@ fetcherLoadedHistoricalData dailyData.count %ld, newest %@ and oldest %@", self.stock.ticker, self.dailyData.count, self.newest, self.oldest);

    [self.delegate performSelectorOnMainThread:@selector(requestFinished:) withObject:self.percentChange waitUntilDone:NO];
}

// Center a stroked line in the center of a pixel.  From a point context, it can be at 0.25, 0.5 or 0.75
// bitmap graphics always use pixel context, so they always have alignTo=0.5
// see https://developer.mozilla.org/En/Canvas_tutorial/Applying_styles_and_colors#A_lineWidth_example
- (double) pxAlign:(double)raw alignTo:(double)alignTo {
    
    double intVal;
    if ( modf(raw, &intVal) != alignTo) {
        return intVal + alignTo;
    }
    return raw;
}

- (void) clearChart {
    _pointCount = _redBarCount = _whiteBarCount = _monthCount = _blackCount = _redCount = _redPointCount = 0;
    _movingAvg1Count = _movingAvg2Count = _bbCount = _hollowRedCount = _filledGreenCount = 0;
}

- (NSString *) monthName:(NSInteger)month {
    switch (month) {
        case 1:
            return @"Jan ";
        case 2:
            return @"Feb ";
        case 3:
            return @"Mar ";
        case 4:
            return @"Apr ";
        case 5:
            return @"May ";
        case 6:
            return @"Jun ";
        case 7:
            return @"Jul ";
        case 8:
            return @"Aug ";
        case 9:
            return @"Sep ";
        case 10:
            return @"Oct ";
        case 11:
            return @"Nov ";
        case 12:
            return @"Dec ";
        default:
            return @" ";
    }
}

- (void) computeChart {
 
    self.ready = NO;
    
    CGFloat xRaw, barCenter, barHeight;
    double oldestClose, volumeFactor;
    NSInteger oldestValidBar; 
    xRaw = self.xFactor/2;
    
    [self clearChart];
    
    if (self.oldestBarShown < 1 || self.periodCount == 0) {
        self.ready = YES;
        return; // No self.bars to draw
        
    } else if (self.oldestBarShown < self.periodCount) {
        oldestValidBar = self.oldestBarShown;
        if (oldestValidBar < self.periodCount - 1) {
            oldestClose = self.periodData[oldestValidBar + 1].close;
        } else {
            oldestClose = self.periodData[oldestValidBar].open; // No older data so use open in lieu of prior close
        }
        
    } else if (self.oldestBarShown >= self.periodCount) {    // user scrolled older than dates available
        oldestValidBar = self.periodCount - 1;
        xRaw += self.xFactor * (self.oldestBarShown - oldestValidBar);
        oldestClose = self.periodData[oldestValidBar].open; // No older data so use open in lieu of prior close
    }
    
    if (self.fundamentalFetcher.isLoadingData == NO && self.fundamentalFetcher.columns.count > 0) {
        
        self.oldestReport = self.fundamentalFetcher.year.count - 1;
        
        self.newestReport = 0;
        NSInteger lastBarAlignment = 0;
        
        for (NSInteger r = 0; r <= self.oldestReport; r++) {
            
            lastBarAlignment = [self.fundamentalFetcher barAlignmentForReport:r];
            
            if (self.newestReport > 0 && lastBarAlignment == -1) {
              //  NSLog(@"ran out of trading data after report %d", newestReport);

            } else if (lastBarAlignment > 0 && lastBarAlignment <= _newestBarShown) { // && lastBarAlignment <= newestBarShown) {
               //  NSLog(@"lastBarAlignment %d <= %d so newestReport = %d", lastBarAlignment, newestBarShown, r);
                self.newestReport = r;
            }
            
            if (lastBarAlignment > oldestValidBar || -1 == lastBarAlignment) {
                self.oldestReport = r;       // first report just out of view
                // NSLog(@" lastBarAlignment %d > %d oldestValidBar or not defined", lastBarAlignment, oldestValidBar);
                break;
            }
        }        
        
        if (self.oldestReport == self.newestReport) {     // include offscreen report
            if (self.newestReport > 0) {
                self.newestReport--;
            } else if (self.oldestReport == 0) {
                self.oldestReport++;
            }
        }
        
        // Only ScrollChartView can calculate min and max values across multiple stocks in a comparison.
        // ScrollChartView will also calculate the labels, so keep the NSDecimalNumber originals and
        // just calculate quarter-end x values.
        
        NSInteger r = self.newestReport;
        self.newestReportInView = self.newestReport;
        
        NSInteger barAlignment = lastBarAlignment = -1;
        
        do {
            lastBarAlignment = barAlignment;
            barAlignment = [self.fundamentalFetcher barAlignmentForReport:r];
            
            if (barAlignment < 0) {
                break;
            }
            
            _fundamentalAlignments[r] = (oldestValidBar - barAlignment + 1) * self.xFactor + xRaw;
            r++;
        } while (r <= self.oldestReport);
        
        if (barAlignment < 0) {
            _fundamentalAlignments[r] = (oldestValidBar - lastBarAlignment + 1) * self.xFactor + xRaw;
        }
        
        self.oldestReportInView = r;
    }
    
    // TO DO: move this to updateHighLow    
    NSDecimalNumber *range = [self.maxHigh decimalNumberBySubtracting:self.scaledLow];
    
    if ([range isEqualToNumber:[NSDecimalNumber zero]] == NO) {
        
        self.yFactor = [[self.chartBase decimalNumberByDividingBy:range] doubleValue];
    } else {
       // NSLog(@"%@ range is %@ so would be a divide by zero, skipping computeChart", stock.ticker, range);
        self.ready = YES;    // prevent unending scroll wheel
        return;
    }
        
    self.yFloor = self.yFactor * [self.maxHigh doubleValue] + sparklineHeight;

    volumeFactor = self.maxVolume/volumeHeight;

    // If we lack older data, estimate lastClose using oldest open
    [self.monthLabels removeAllObjects];
    
    NSString *label;
    
    self.lastMonth = self.periodData[oldestValidBar].month;

    for (NSInteger a = oldestValidBar; a >= _newestBarShown; a--) {
        barCenter = [self pxAlign:xRaw alignTo:0.5]; // pixel context
        
        if (self.periodData[a].month != self.lastMonth) {
            label = [self monthName:self.periodData[a].month];
            if (self.periodData[a].month == 1) {
                if (self.periodCount <  self.dailyData.count || self.xFactor < 4) { // not enough room
                    label = [[NSString stringWithFormat:@"%ld", (long)self.periodData[a].year] substringFromIndex:2];
                } else {
                    label = [label stringByAppendingString:[[NSString stringWithFormat:@"%ld", (long)self.periodData[a].year] substringFromIndex:2]];
                }
                
            } else if (self.barUnit > 5) {   // only year markets
                label = @"";
            } else if (self.periodCount <  self.dailyData.count || self.xFactor < 2) { // shorten months
                label = [label substringToIndex:1];
            }

            if (label.length > 0) {
                [self.monthLabels addObject:label];
                _monthLines[_monthCount++] = CGPointMake(barCenter - 2, sparklineHeight);
                _monthLines[_monthCount++] = CGPointMake(barCenter - 2, volumeBase);
            }
            
        }
        self.lastMonth = self.periodData[a].month;
        
        if (self.stock.chartType < 2) {      //OHLC or HLC
            
            if (oldestClose > self.periodData[a].close) { // green bar
                if (self.stock.chartType == 0) { // include open
                    _redPoints[_redPointCount++] = CGPointMake(barCenter - _xFactor/2, _yFloor - _yFactor * self.periodData[a].open);
                    _redPoints[_redPointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].open);
                }
                
                _redPoints[_redPointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].high);
                _redPoints[_redPointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].low);
                
                _redPoints[_redPointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].close);
                _redPoints[_redPointCount++] = CGPointMake(barCenter + _xFactor/2, _yFloor - _yFactor * self.periodData[a].close);
                
            } else {    // red bar
                if (self.stock.chartType == 0) { // include open
                    _points[_pointCount++] = CGPointMake(barCenter - self.xFactor/2, _yFloor - _yFactor * self.periodData[a].open);
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].open);
                }
                
                _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].high);
                _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].low);
                
                _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].close);
                _points[_pointCount++] = CGPointMake(barCenter + _xFactor/2, _yFloor - _yFactor * self.periodData[a].close);
            }
            
        } else if (self.stock.chartType == 2 ) { // candlestick
            
            barHeight = _yFactor * (self.periodData[a].open - self.periodData[a].close);
            
            if (fabs(barHeight) < 1) {
                barHeight = barHeight > 0 ? 1 : -1;
            }
            
            // Filled up closes or hollow down closes are rare, so draw those points directly to avoid an extra array
            
            if (self.periodData[a].open >= self.periodData[a].close) {  // filled bar (StockCharts colors closes higher > lastClose && close < open as filled black barData.count)
                
                if (oldestClose < self.periodData[a].close) { // filled green bar
                    
                    _filledGreenBars[_filledGreenCount++] = CGRectMake(barCenter - _xFactor * 0.4, _yFloor - _yFactor * self.periodData[a].open, 0.8 * self.xFactor, barHeight);
                    
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].high);
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].low);
                    
                } else {
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].high);
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].low);
                    _redBars[_redBarCount++] = CGRectMake(barCenter - self.xFactor * 0.4, _yFloor - _yFactor * self.periodData[a].open, 0.8 * self.xFactor, barHeight);
                }
                
            } else {
                
                if (oldestClose > self.periodData[a].close) { // red hollow bar
                    
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].high);
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].close);
                    
                    _hollowRedBars[_hollowRedCount++] = CGRectMake(barCenter - self.xFactor * 0.4, _yFloor - _yFactor * self.periodData[a].open, 0.8 * self.xFactor, barHeight);
                    
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].open);
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].low);
                    
                } else {
                    
                    _greenBars[_whiteBarCount++] = CGRectMake(barCenter - self.xFactor * 0.4, _yFloor - _yFactor * self.periodData[a].open, 0.8 * _xFactor, barHeight);
                    
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].high);
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].close);
                    
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].open);
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].low);
                }
            }
            
        } else if (self.stock.chartType == 3 ) { // Close
            _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].close);
        }

        // It may seem inefficient to check the BOOL and the CGFloat value, but this is optimal
        // the indicator counts are based on the number of points in view, not the number calculated
        // that's why the counts must be reset after each redraw instead of when recalculating the indicators
        NSInteger offset = a - _newestBarShown;
        
        if (sma50 && self.periodData[a].movingAvg1 > 0.) {
            _movingAvg1Count++;
            _movingAvg1[offset] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].movingAvg1);
        }
        
        if (sma200 && self.periodData[a].movingAvg2 > 0.) {
            _movingAvg2Count++;
            _movingAvg2[offset] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].movingAvg2);
        }
        
        if (bb20 && self.periodData[a].mbb > 0.) {
            _bbCount++;
            _ubb[offset] = CGPointMake(barCenter, _yFloor - _yFactor * (self.periodData[a].mbb + 2*self.periodData[a].stdev));
            _mbb[offset] = CGPointMake(barCenter, _yFloor - _yFactor * self.periodData[a].mbb);
            _lbb[offset] = CGPointMake(barCenter, _yFloor - _yFactor * (self.periodData[a].mbb - 2*self.periodData[a].stdev));
        }
        
        if (self.periodData[a].volume <= 0) {
     //       NSLog(@"volume shouldn't be zero but is for a=%ld", a);
        } else {
            if (oldestClose > self.periodData[a].close) {
                    _redVolume[_redCount++] = CGRectMake(barCenter - _xFactor/2, volumeBase, _xFactor, - self.periodData[a].volume/volumeFactor);
                    
            } else { 
                    _blackVolume[_blackCount++] = CGRectMake(barCenter - _xFactor/2, volumeBase, _xFactor, - self.periodData[a].volume/volumeFactor);
            }
        }
    
        oldestClose = self.periodData[a].close;
        xRaw += _xFactor;            // keep track of the unaligned value or the chart will end too soon
    }
    self.ready = YES;
}

@end
