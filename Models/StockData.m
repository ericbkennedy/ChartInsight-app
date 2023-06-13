#include <dispatch/dispatch.h>
#import <CoreGraphics/CoreGraphics.h>
#import "FundamentalAPI.h"
#import "StockData.h"
#import <QuartzCore/QuartzCore.h>
#import "Stock.h"


@interface StockData () {
    
@private
    BarStruct   *dailyData;     // for parallelism, dataAPI writes to a separate block of memory
    BarStruct   *barData;       // points to dailyData except for monthly or weekly
    BOOL sma50, sma200, bb20;
    double pxHeight, sparklineHeight, volumeBase, volumeHeight;
    dispatch_queue_t concurrentQueue;
    NSInteger _newestBarShown;
}
@end

@implementation StockData

- (BarStruct *) barAtIndex:(NSInteger)index setUpClose:(BOOL *)upClose {
    if (index > self.bars) {
        return nil;
    }
   *upClose = YES;
    
    if (index < self.bars - 1) { // check for up/down close
        if (barData[index].close < barData[index + 1].close) {
            *upClose = NO;
        }
    } else if (barData[index].close < barData[index].open) {
        *upClose = NO;
    }
    return &barData[index];
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
    // fundamentalAPI uses the sharedSession so don't invalidate it
    [self.fundamentalAPI setDelegate:nil];
    [self.fundamentalAPI release];
    self.fundamentalAPI = nil; // will trigger dealloc on fundamentalAPI
    [self.api invalidateAndCancel];
    [self.api setDelegate:nil];
    [self.api release];
    self.api = nil;
}

- (void)dealloc {
    DLog(@"%@ is being deallocated", self.stock.symbol);
    self.delegate = nil;
    // don't release memory I didn't alloc in StockData, like the gregorian calendar
    
    if (barData != dailyData) {
        // DLog(@"Dealloc: barData has a different address than dailyData");
        free(barData);
    }
    free(dailyData);
    
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
    [self.days release];
    [super dealloc];
}

- (void) initWithDaysAgo:(NSInteger)daysAgo {

    _bars = _dailyBars = _newestBarShown = _oldestReport = _newestReport = _movingAvg1Count = _movingAvg2Count = 0;
    self.api = NULL;
    _busy = _ready = NO;
    [self setPercentChange:[NSDecimalNumber one]];
    [self setChartPercentChange:[NSDecimalNumber one]];
    
    [self setMaxHigh:[NSDecimalNumber zero]];
    [self setMinLow:[NSDecimalNumber zero]];
    [self setBookValue:[NSDecimalNumber notANumber]]; 
    
    self.api = [[DataAPI alloc] init];
    dailyData = (BarStruct *)malloc(sizeof(BarStruct)*[self.api maxBars]);
    barData = dailyData;
    
    [self setMonthLabels:[NSMutableArray arrayWithCapacity:50]];
    
    NSInteger maxBars = (UIScreen.mainScreen.bounds.size.height - 60) * UIScreen.mainScreen.scale;
    
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
    
    self.days = [[NSDateComponents alloc] init];
    [self setLastPrice:[NSDecimalNumber zero]];
    
    NSDate *desiredDate = [NSDate date];
    if (daysAgo > 0) {
        [self.days setDay:-daysAgo];
       // [self setNewest:[self.gregorian dateByAddingComponents:self.days toDate:[NSDate date] options:0]];
        desiredDate = [self.gregorian dateByAddingComponents:self.days toDate:[NSDate date] options:0];
    }
    
    [self updateBools];
    [self.api setRequestNewestDate:desiredDate];
    
    [self.stock convertDateStringToDateWithFormatter:self.api.dateFormatter];
    
    self.api.requestOldestDate = [self.stock.startDate laterDate:[NSDate dateWithTimeInterval:(200+self.oldestBarShown * self.barUnit)*-240000 sinceDate:desiredDate]];

    [self setNewest:self.api.requestOldestDate];    // better than oldestPast
    
    self.api.symbol = self.stock.symbol;
    self.api.stockId = self.stock.id;
    self.api.gregorian = self.gregorian;
    self.api.delegate = self;
        
    NSString *concurrentName = [NSString stringWithFormat:@"com.chartinsight.%ld.%ld", self.stock.id, daysAgo];
    
    concurrentQueue = dispatch_queue_create([concurrentName UTF8String], DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_set_target_queue(concurrentQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));

    [self setFundamentalAPI:nil];

    [self.api fetchInitialData];

    if ([self.stock fundamentalList].length > 4) {
        [self.delegate performSelector:@selector(showProgressIndicator)];
        [self setFundamentalAPI:[[FundamentalAPI alloc] init]];
        [self.fundamentalAPI getFundamentalsForStock:self.stock withDelegate:self];
    }
}

- (void) APILoadedFundamentalData:(FundamentalAPI *)fundamental {
    
    // DLog(@"%d fundamental values loaded", [[fundamental year] count]);
    if (self.busy == NO && self.bars > 1) {
        dispatch_barrier_sync(concurrentQueue, ^{ [self updateFundamentalAlignment];
                                                                            [self computeChart];    });
        [self.delegate performSelectorOnMainThread:@selector(requestFinished:) withObject:self.percentChange waitUntilDone:NO];
    } else {
        [self.delegate performSelectorOnMainThread:@selector(stopProgressIndicator) withObject:nil waitUntilDone:NO];
    }
}


// When calculating the simple moving average, there are 3 possible cases:
// 1. all self.bars are new
//        Start with bar 0 and continue until the end
// 
// 2. adding self.bars to the front
//        Start with bar 0 and continue until the first old bar
// 
// 3. adding self.bars to the end
//        Start with the oldest bar and walk towards the start of the array to find the first empty moving average
// 
// For example, div LINE the ratio of the adjusted close varies slightly
- (void) calculateSMA {
    
    NSInteger oldest50available, oldest150available, oldest200available;
    oldest50available = self.bars - 50;
    oldest150available = self.bars - 150;
    oldest200available = self.bars - 200;
    
    if (oldest50available > 0) {
        double movingSum50 = 0.0f;
        double movingSum150 = 0.0f;
        
        // add last n self.bars, then start subtracting i + n - 1 bar to compute average
    
        for (NSInteger i = self.bars - 1; i >= 0; i--) {
            movingSum50 += barData[i].close;
            
            if (i < oldest50available) { 
                movingSum150 += barData[i + 50].close;                                    
                movingSum50 -= barData[i + 50].close; 
                if (i < oldest200available) {
                    movingSum150 -= barData[i + 200].close; // i + n - 1, so for bar zero it subtracks bar 199 (200th bar)                        
                    barData[i].movingAvg2 = (movingSum50 + movingSum150) / 200;
                } else if (i == oldest200available) {
                    barData[i].movingAvg2 = (movingSum50 + movingSum150) / 200;
                }
                barData[i].movingAvg1 = movingSum50 / 50;
                
            } else if (i == oldest50available) {            // don't subtract any self.bars
                barData[i].movingAvg1 = movingSum50 / 50;           
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
    NSInteger firstFullPeriod = self.bars - period;
    
    if (firstFullPeriod > 0) {
        double movingSum = 0.0f;
        double powerSumAvg = 0.0f;
        
        // add last n self.bars, then start subtracting i + n - 1 bar to compute average
        
        for (NSInteger i = self.bars - 1; i >= 0; i--) {
            movingSum += barData[i].close;
            
            if (i < firstFullPeriod) {
                movingSum -= barData[i + period].close;
                
                barData[i].mbb = movingSum / period;
                powerSumAvg += (barData[i].close * barData[i].close - barData[i + period].close * barData[i + period].close)/(period);
 
                barData[i].stdev = sqrt(powerSumAvg - barData[i].mbb * barData[i].mbb);
                                 
            } else if (i >= firstFullPeriod) {
                powerSumAvg += (barData[i].close * barData[i].close - powerSumAvg)/(self.bars - i);
                 
                if (i == firstFullPeriod) {            // don't subtract any self.bars
                    barData[i].mbb = movingSum / period;
                    barData[i].stdev = sqrt(powerSumAvg - barData[i].mbb * barData[i].mbb);
                 }
            }
        }
    }
}

// Align the array of fundamental data points to an offset into the barData struct
- (void) updateFundamentalAlignment {
    if (self.fundamentalAPI != nil && self.fundamentalAPI.columns.count > 0) {
        
        NSInteger i = 0, r = 0;
        for (r = 0; r < self.fundamentalAPI.year.count; r++) {
            
            NSInteger lastReportYear = [[[self.fundamentalAPI year] objectAtIndex:r] intValue];
            NSInteger lastReportMonth = [[[self.fundamentalAPI month] objectAtIndex:r] intValue];
            
            while (i < self.bars && (barData[i].year > lastReportYear ||  barData[i].month > lastReportMonth)) {
                i++;
            }
            if (i < self.bars && barData[i].year == lastReportYear && barData[i].month == lastReportMonth) {
                
                [self.fundamentalAPI setBarAlignment:i forReport:r];
            }
        }
    }   
}

// Called after shiftRedraw shifts self.oldestBarShown and newestBarShown during scrolling
- (void) updateHighLow {
    
    if (self.oldestBarShown <= 0) {
        return;
    }
    
    double max = 0.0, min = 0.0;
    self.maxVolume = 0.0;
        
    for (NSInteger a = self.oldestBarShown; a >= _newestBarShown ; a--) {
        if (barData[a].volume > self.maxVolume) {
            self.maxVolume = barData[a].volume;
        }
        
        if (barData[a].low > 0.0f) {
            if (min == 0.0f) {
                min = barData[a].low;
            } else if (min > barData[a].low) { 
                min = barData[a].low;
            }
        }
        
        if (max < barData[a].high) { 
            max = barData[a].high;
        }
    }
    
    [self setMaxHigh:[[[NSDecimalNumber alloc] initWithDouble:max] autorelease]];
    [self setMinLow:[[[NSDecimalNumber alloc] initWithDouble:min] autorelease]];
    [self setScaledLow:self.minLow];

    if ([self.minLow doubleValue] > 0) {
        [self setPercentChange:[self.maxHigh decimalNumberByDividingBy:self.minLow]];
        
        if ([self.percentChange compare:self.chartPercentChange] == NSOrderedDescending) {
            // DLog(@"percentChange %@ is bigger than %@ so adjusting", percentChange, chartPercentChange);
            [self setChartPercentChange:self.percentChange];
        }
        [self setScaledLow:[self.maxHigh decimalNumberByDividingBy:self.chartPercentChange]];
    }
    
    [self computeChart];
}

- (NSDecimalNumber *) shiftRedraw:(NSInteger)barsShifted withBars:(NSInteger)screenBarWidth {
    
    if (self.oldestBarShown + barsShifted >= [self.api maxBars]) {
        DLog(@"Early return because self.oldestBarShown %ld + self.barsShifted %ld > maxBars", self.oldestBarShown, barsShifted);
        // Simplify fetch logic by returning to prevent scrolling to older dates instead of calling removeNewerBars
        return self.percentChange;
    }
    self.oldestBarShown += barsShifted;
        
    [self setNewestBarShown:(self.oldestBarShown - screenBarWidth)];     // handles negative values
    
    // DLog(@"self.oldestBarShown %d and newestBarShown in shiftREdraw is %d", self.oldestBarShown, newestBarShown);
        
    if (self.oldestBarShown <= 0) {  // no self.bars to show yet
        // DLog(@"%@ self.oldestBarShown is less than zero at %d", self.stock.symbol, self.oldestBarShown);
        [self clearChart];

    } else if (self.busy) {
        // Avoid deadlock by limiting concurrentQueue to updateHighLow and didFinishFetch
       // DLog(@"%@ is busy", self.stock.symbol);

        dispatch_sync(concurrentQueue,  ^{    [self updateHighLow];     });
        return self.percentChange;
    }
            
    BOOL oldestNotYetLoaded = fabs([self.stock.startDate timeIntervalSinceDate:self.oldest]) > 90000 ? YES : NO;
    
    if (oldestNotYetLoaded && self.oldestBarShown > self.bars - 201) {      // load older dates or moving average will break

        self.busy = YES;
        [self.delegate performSelectorOnMainThread:@selector(showProgressIndicator) withObject:nil waitUntilDone:NO];
            
   //     NSDate *requestStart = [[self.stock startDate] laterDate:[self.oldest dateByAddingTimeInterval:MAX(365,screenBarWidth)* barUnit *-86400]];
                                    
        [self.api fetchOlderDataFrom:self.stock.startDate untilDate:self.oldest];

    } else if (0 == self.newestBarShown) {
        
        if ([self.api shouldFetchIntradayQuote]) {
            self.busy = YES;
            [self.api fetchIntradayQuote];

        } else if ([self.api.nextClose compare:[NSDate date]] == NSOrderedAscending) { // next close is in the past
            self.busy = YES;
            [self.delegate performSelectorOnMainThread:@selector(showProgressIndicator) withObject:nil waitUntilDone:NO];
            [self.api fetchNewerThanDate:[self newest] screenBarWidth:screenBarWidth];
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
        
        // DLog(@"%@ pctDifference %f so pct changing from %@ to %@", [self.stock symbol], pctDifference, self.chartPercentChange, maxPercentChange);
        [self setChartPercentChange:maxPercentChange];
        
        [self setScaledLow:[self.maxHigh decimalNumberByDividingBy:self.chartPercentChange]];
        
        dispatch_sync(concurrentQueue, ^{   [self computeChart];    });
    } else {
        [self setChartPercentChange:maxPercentChange];
        [self setScaledLow:[self.maxHigh decimalNumberByDividingBy:self.chartPercentChange]];
    }
}

- (void) APICanceled:(DataAPI *) dp {
    self.busy = NO;
    NSString *message = @"Canceled request";
    [self.delegate performSelectorOnMainThread:@selector(requestFailedWithMessage:) withObject:message waitUntilDone:NO];
}

// If we were redirected, then the user must be on a wifi network that requires login. Show a UIWebView to allow login
- (void) APIRedirected {
    self.busy = NO;
//    [self.delegate performSelectorOnMainThread:@selector(showWifiLogin) withObject:nil waitUntilDone:NO];
}


-(void) APIFailed:(NSString *)message {
    self.busy = NO;
    DLog(@"%@", message);
    [self.delegate performSelectorOnMainThread:@selector(requestFailedWithMessage:) withObject:message waitUntilDone:NO];
}

// memove won't throw away self.bars to avoid a buffer overrun, so we have to do it ourselves with memcpy
- (void) createNewBarDataWithShift:(NSInteger)shift fromIndex:(NSInteger)fromIndex {
    
    BarStruct *newDailyData = (BarStruct *)malloc(sizeof(BarStruct)*[self.api maxBars]);

    if (self. self.dailyBars + shift > [self.api maxBars]) {     // avoid buffer overrun
        self. self.dailyBars -= shift;
    }
    memcpy(&newDailyData[shift], &dailyData[fromIndex], self. self.dailyBars * sizeof(BarStruct));
    free(dailyData);
    dailyData = newDailyData;
}

-(void) APILoadedIntraday:(DataAPI *)dp {
    
    // Avoid deadlock by limiting concurrentQueue to updateHighLow and APILoaded*    

    dispatch_barrier_sync(concurrentQueue, ^{
            
        double oldMovingAvg1, oldMovingAvg2;
        
        NSDate *apiNewest = [self.api dateFromBar:dp->intradayBar];
        
        CGFloat dateDiff = [apiNewest timeIntervalSinceDate:[self newest]];
       // DLog(@"intrday datediff is %f when comparing %@ to %@", dateDiff, [self newest], apiNewest);
        
        if (dateDiff > 84600) {
          //  DLog(@"intraday moving %d self.bars by 1", self.bars);
            [self createNewBarDataWithShift:1 fromIndex:0];
            self. self.dailyBars += 1;
            // self.bars may or may not increase; let summarizeByDate figure that out
            oldMovingAvg1 = oldMovingAvg2 = .0f;

        } else { // save before overwriting with memcpy
            oldMovingAvg1 = dailyData[0].movingAvg1;
            oldMovingAvg2 = dailyData[0].movingAvg2;
        }
        
        // copy intraday data to barData
        memcpy( dailyData, &dp->intradayBar, sizeof(BarStruct));
        
        [self setLastPrice:[[[NSDecimalNumber alloc] initWithDouble:dailyData[0].close] autorelease]];
        
        [self setNewest:apiNewest];

        // For intraday update to weekly or monthly chart, decrement self.oldestBarShown only if
        //    the intraday bar is for a different period (week or month) than the existing newest bar
        
        [self summarizeByDateFrom:0 oldBars:0];
        [self updateHighLow]; // must be a separate call to handle daysAgo shifting

        self.busy = NO;
    });
    
    [self.delegate performSelectorOnMainThread:@selector(requestFinished:) withObject:self.percentChange waitUntilDone:NO];
};

- (void) groupByWeek:(NSDate *)startDate dailyIndex:(NSInteger)iNewest weeklyIndex:(NSInteger)wi {
    
    // Note, we are going backwards, so the most recent daily close is the close of the week
    barData[wi].close = dailyData[iNewest].close;
    barData[wi].adjClose = dailyData[iNewest].adjClose;
    barData[wi].high = dailyData[iNewest].high;
    barData[wi].low  = dailyData[iNewest].low;
    barData[wi].volume = dailyData[iNewest].volume;
    barData[wi].movingAvg1 = barData[wi].movingAvg2 = barData[wi].mbb = barData[wi].stdev = 0.;
    
    NSInteger i = iNewest + 1;    // iNewest values already saved to barData

    NSDateComponents *componentsToSubtract = [[NSDateComponents alloc] init];
    NSDateComponents *weekdayComponents = [self.gregorian components:NSCalendarUnitWeekday fromDate:startDate];

    // Get the previous Friday, convert it into an NSInteger and then group all dates LARGER than it into the current week
    // Friday is weekday 6 in Gregorian calendar, so subtract current weekday and -1 to get previous Friday
    [componentsToSubtract setDay: -1 - [weekdayComponents weekday]];
    NSDate *lastFriday = [self.gregorian dateByAddingComponents:componentsToSubtract toDate:startDate options:0];
    [componentsToSubtract release];
    
    NSUInteger unitFlags = NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitYear;
    NSDateComponents *friday = [self.gregorian components:unitFlags fromDate:lastFriday];
    
    while (i < self. self.dailyBars && 0 < 20000 * (dailyData[i].year - friday.year) + 100 * (dailyData[i].month - friday.month) + dailyData[i].day - friday.day) {
        
        if (dailyData[i].high > barData[wi].high) {
            barData[wi].high = dailyData[i].high;
        }
        if (dailyData[i].low < barData[wi].low) {
            barData[wi].low = dailyData[i].low;
        }
        barData[wi].volume += dailyData[i].volume;
        i++;
    }
    
    barData[wi].year = dailyData[i - 1].year;
    barData[wi].month = dailyData[i - 1].month;
    barData[wi].day = dailyData[i - 1].day;
    barData[wi].open = dailyData[i - 1].open;
    
    if (i < self. self.dailyBars) {
        self.bars = wi;
        wi++;
        [self groupByWeek:lastFriday dailyIndex:i weeklyIndex:wi];
    } else {
        self.bars = wi + 1;  // self.bars is a count not a zero index
    }
}

- (void) groupByMonthFromDailyIndex:(NSInteger)iNewest monthlyIndex:(NSInteger)mi {
    
    // Note, we are going backwards, so the most recent daily close is the close of the week
    barData[mi].close = dailyData[iNewest].close;
    barData[mi].adjClose = dailyData[iNewest].adjClose;
    barData[mi].high = dailyData[iNewest].high;
    barData[mi].low  = dailyData[iNewest].low;
    barData[mi].volume = dailyData[iNewest].volume;
    barData[mi].year = dailyData[iNewest].year;
    barData[mi].month = dailyData[iNewest].month;
    barData[mi].movingAvg1 = barData[mi].movingAvg2 = barData[mi].mbb = barData[mi].stdev = 0.;
    
    NSInteger i = iNewest + 1;    // iNewest values already saved to barData
        
    while (i <  self.dailyBars && dailyData[i].month == barData[mi].month) {
        
        if (dailyData[i].high > barData[mi].high) {
            barData[mi].high = dailyData[i].high;
        }
        if (dailyData[i].low < barData[mi].low) {
            barData[mi].low = dailyData[i].low;
        }
        barData[mi].volume += dailyData[i].volume;
        i++;
    }
    
    barData[mi].open = dailyData[i - 1].open;
    barData[mi].day = dailyData[i - 1].day;
    
    if (i <  self.dailyBars) {
        self.bars = mi;
        mi++;
        [self groupByMonthFromDailyIndex:i monthlyIndex:mi];
    } else {
        self.bars = mi + 1;  // self.bars is a count not a zero index
   //     // DLog(@"final self.bars value %d", self.bars);
    }
}

- (void) summarizeByDateFrom:(NSInteger)oldDailyBars oldBars:(NSInteger)oldBars {

    // on average there are about 4.6 trading days in a week. Dividing by 4 provides sufficient room
    
    if (self.barUnit == 1.) {
        barData = dailyData;
        self.bars =  self.dailyBars;
    } else if (self.barUnit > 3 && barData == dailyData) {
         barData = (BarStruct *)malloc(sizeof(BarStruct)*([self.api maxBars] / 4));
    }
    
    if (self.barUnit > 5) {
         [self groupByMonthFromDailyIndex:oldDailyBars monthlyIndex:oldBars];
    } else if (self.barUnit > 3) {
        if (oldDailyBars == 0) {
             [self groupByWeek:self.newest dailyIndex:0 weeklyIndex:0];
        } else if (oldBars > 0 && oldBars < oldDailyBars){
            
            oldBars--;   // to handle partial periods, start with 2nd to last bar.  Find the daily bar that matches the date
            
            do {
                oldDailyBars--;
                 
            } while (oldDailyBars > 0 && ((dailyData[oldDailyBars].month != barData[oldBars].month) || (dailyData[oldDailyBars].day != barData[oldBars].day)));
            
             [self groupByWeek:[self.api dateFromBar:dailyData[oldDailyBars]] dailyIndex:oldDailyBars weeklyIndex:oldBars];
        }
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

-(void) APILoadedHistoricalData:(DataAPI *)dp {

    /* Three cases since intraday updates are a separate callback:
     1. First request, so copy to dailyData[bars]
     2. Newer dates (not intraday update), so shift dailyData by dp.countBars and copy from dp->cArray to barData[0]
     3. Older dates, so copy to dailyData[bars]
     */
    
    dispatch_barrier_sync(concurrentQueue, ^{
        NSInteger startCopy = 0;             // copy to start of dailyData.  If  self.dailyBars > 0, move existing data first
        BOOL checkPrefetch = NO, shiftBarsShown = NO;
        NSDate *desiredDate;
        NSDate *apiNewest = [self.api dateFromBar:dp->cArray[0]];
    
        //DLog(@"%@  self.dailyBars %ld self.newest %@ and api.newest %@ and api.oldest %@", dp.symbol,  self.dailyBars, self.newest, apiNewest, self.api.oldestDate);
  
        if ( self.dailyBars == 0) { // case 1. First request
            if (self.stock.daysAgo > 0) {
                checkPrefetch = YES;
                [self.days setDay: - self.stock.daysAgo];
                // [self setNewest:[self.gregorian dateByAddingComponents:self.days toDate:[NSDate date] options:0]];
                desiredDate = [self.gregorian dateByAddingComponents:self.days toDate:[NSDate date] options:0];
             }
            [self setNewest:apiNewest];
            [self setLastPrice:[[[NSDecimalNumber alloc] initWithDouble:dp->cArray[0].close] autorelease]];  // if daysAgo > 0, lastPrice will be off until all newer data is fetched
            [self setOldest:[self.api oldestDate]];
            
        } else if ([self.newest compare:apiNewest] == NSOrderedAscending) {         // case 2. Newer dates
            DLog(@"api is newer, so moving by %ld self.bars", dp.countBars);
            checkPrefetch = YES;
            shiftBarsShown = YES;   // because of the following createNewBarDataWithShift call
            [self createNewBarDataWithShift:dp.countBars fromIndex:0];     // move current self.bars by dp.countBars
            [self setNewest:apiNewest];
            desiredDate = self.newest;
            [self setLastPrice:[[[NSDecimalNumber alloc] initWithDouble:dp->cArray[0].close] autorelease]];  // if daysAgo > 0, lastPrice will be off until all newer data is fetched
            
        } else if ([self.oldest compare:[self.api oldestDate]] == NSOrderedDescending) {    // case 3. Older dates
        
            if (( self.dailyBars + dp.countBars) > [self.api maxBars]) {
                DLog(@"removeNewerBars was needed to support historical charts back to the 1950s but is no longer supported");
            }
            startCopy =  self.dailyBars;      // copy to end of  self.dailyBars
            
            [self setOldest:[self.api oldestDate]];
        }
        
        if (dp.countBars > 0) {
            memcpy(&dailyData[startCopy], dp->cArray, dp.countBars * sizeof(BarStruct));        // copy to start of barData the dp->cArray NEWER data
       
            DLog(@"%@ added %ld new self.bars to %ld exiting  self.dailyBars", self.stock.symbol, dp.countBars,  self.dailyBars);
            
            NSInteger oldBars = self.bars;
            NSInteger oldDailyBars =  self.dailyBars;
             self.dailyBars += dp.countBars;
            
            [self summarizeByDateFrom:oldDailyBars oldBars:oldBars];
            
            if (shiftBarsShown) {
                _newestBarShown += (self.bars - oldBars);
                self.oldestBarShown += (self.bars - oldBars);
            }
            
            if (checkPrefetch) {
                 
                while ([desiredDate timeIntervalSinceDate:[self.api dateFromBar:barData[_newestBarShown]]] < 0) {        // prefetched dates newer than those requested, so shift newestBarShown
                    
                    self.newestBarShown += 1;
                    self.oldestBarShown += 1;
                }
            }
             [self updateHighLow];
        }
        self.busy = NO;
        [self.delegate performSelectorOnMainThread:@selector(stopProgressIndicator) withObject:nil waitUntilDone:NO];
      });
    
    DLog(@"after %ld self.bars (%ld new), newest %@ and oldest %@", self.bars, dp.countBars, self.newest, self.oldest);

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
    [self setBookValue:[NSDecimalNumber notANumber]];
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
    
    if (self.oldestBarShown < 1 || self.bars == 0) {
        self.ready = YES;
        return; // No self.bars to draw
        
    } else if (self.oldestBarShown < self.bars) {
        oldestValidBar = self.oldestBarShown;
        oldestClose = barData[oldestValidBar + 1].open;
        
    } else if (self.oldestBarShown >= self.bars) {    // don't load garbage data
        oldestValidBar = self.bars - 1;
        xRaw += self.xFactor * (self.oldestBarShown - oldestValidBar);
        oldestClose = barData[oldestValidBar].open;
    }
    
    if (self.fundamentalAPI.columns.count > 0) {
        
        self.oldestReport = self.fundamentalAPI.year.count - 1;
        
        self.newestReport = 0;
        NSInteger lastBarAlignment = 0;
        
        for (NSInteger r = 0; r <= self.oldestReport; r++) {
            
            lastBarAlignment = [self.fundamentalAPI barAlignmentForReport:r];
            
            if (self.newestReport > 0 && lastBarAlignment == -1) {
              //  DLog(@"ran out of trading data after report %d", newestReport);

            } else if (lastBarAlignment > 0 && lastBarAlignment <= _newestBarShown) { // && lastBarAlignment <= newestBarShown) {
               //  DLog(@"lastBarAlignment %d <= %d so newestReport = %d", lastBarAlignment, newestBarShown, r);
                self.newestReport = r;
            }
            
            if (lastBarAlignment > oldestValidBar || -1 == lastBarAlignment) {
                self.oldestReport = r;       // first report just out of view
                // DLog(@" lastBarAlignment %d > %d oldestValidBar or not defined", lastBarAlignment, oldestValidBar);
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
        
        NSDecimalNumber *reportValue;
        
        // Only ScrollChartView can calculate min and max values across multiple stocks in a comparison.
        // ScrollChartView will also calculate the labels, so keep the NSDecimalNumber originals and
        // just calculate quarter-end x values.
        
        // Use NSMutableArray to preserve the order 
        // book value must be handled separately because we DO need to calculate the min and max values and use those on the main chart
        // yFactor            
        
        if ([[self.fundamentalAPI columns] objectForKey:@"BookValuePerShare"] != nil) {
            NSInteger r = self.newestReport;
            
            do {
                reportValue = [self.fundamentalAPI valueForReport:r withKey:@"BookValuePerShare"];
                
            } while ([reportValue isEqualToNumber:[NSDecimalNumber notANumber]] && ++r <= self.oldestReport);
            
            if ([reportValue isEqualToNumber:[NSDecimalNumber notANumber]] == NO) {                
                [self setBookValue:reportValue];                    
            
                do {
                    reportValue = [self.fundamentalAPI valueForReport:r withKey:@"BookValuePerShare"];
                    if ([reportValue isEqualToNumber:[NSDecimalNumber notANumber]]) {
                        break;
                    }
                    
                    if ([self.maxHigh compare:reportValue] == NSOrderedAscending) {
                        [self setMaxHigh:reportValue];
                    }
                    if ([self.scaledLow compare:reportValue] == NSOrderedDescending) {
                        [self setScaledLow:reportValue];
                    }
                    r++;
                } while (r < self.oldestReport);
            }
        }
        
        NSInteger r = self.newestReport;
        self.fundamentalAPI.newestReportInView = self.newestReport;
        
        NSInteger barAlignment = lastBarAlignment = -1;
        
        do {
            lastBarAlignment = barAlignment;
            barAlignment = [self.fundamentalAPI barAlignmentForReport:r];
            
            if (barAlignment < 0) {
                break;
            }
            
            _fundamentalAlignments[r] = (oldestValidBar - barAlignment + 1) * self.xFactor + xRaw;
            r++;
        } while (r <= self.oldestReport);
        
        if (barAlignment < 0) {
            _fundamentalAlignments[r] = (oldestValidBar - lastBarAlignment + 1) * self.xFactor + xRaw;
        }
        
        self.fundamentalAPI.oldestReportInView = r;
    }
    
    // TO DO: move this to updateHighLow    
    NSDecimalNumber *range = [self.maxHigh decimalNumberBySubtracting:self.scaledLow];
    
    if ([range isEqualToNumber:[NSDecimalNumber zero]] == NO) {
        
        self.yFactor = [[self.chartBase decimalNumberByDividingBy:range] doubleValue];
    } else {
       // DLog(@"%@ range is %@ so would be a divide by zero, skipping computeChart", stock.symbol, range);
        self.ready = YES;    // prevent unending scroll wheel
        return;
    }
        
    self.yFloor = self.yFactor * [self.maxHigh doubleValue] + sparklineHeight;

    volumeFactor = self.maxVolume/volumeHeight;

    // If we lack older data, estimate lastClose using oldest open
    [self.monthLabels removeAllObjects];
    
    NSString *label;
    
    self.lastMonth = barData[oldestValidBar].month;

    for (NSInteger a = oldestValidBar; a >= _newestBarShown; a--) {
        
        barCenter = [self pxAlign:xRaw alignTo:0.5]; // pixel context
        
        if (barData[a].month != self.lastMonth) {
            label = [self monthName:barData[a].month];
            if (barData[a].month == 1) {
                if (self.bars <  self.dailyBars || self.xFactor < 4) { // not enough room
                    label = [[NSString stringWithFormat:@"%ld", (long)barData[a].year] substringFromIndex:2];
                } else {
                    label = [label stringByAppendingString:[[NSString stringWithFormat:@"%ld", (long)barData[a].year] substringFromIndex:2]];
                }
                
            } else if (self.barUnit > 5) {   // only year markets
                label = @"";
            } else if (self.bars <  self.dailyBars || self.xFactor < 2) { // shorten months
                label = [label substringToIndex:1];
            }

            if (label.length > 0) {
                [self.monthLabels addObject:label];
                _monthLines[_monthCount++] = CGPointMake(barCenter - 2, sparklineHeight);
                _monthLines[_monthCount++] = CGPointMake(barCenter - 2, volumeBase);
            }
            
        }
        self.lastMonth = barData[a].month;
        
        if (self.stock.chartType < 2) {      //OHLC or HLC
            
            if (oldestClose > barData[a].close) { // green bar
                if (self.stock.chartType == 0) { // include open
                    _redPoints[_redPointCount++] = CGPointMake(barCenter - _xFactor/2, _yFloor - _yFactor * barData[a].open);
                    _redPoints[_redPointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].open);
                }
                
                _redPoints[_redPointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].high);
                _redPoints[_redPointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].low);
                
                _redPoints[_redPointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].close);
                _redPoints[_redPointCount++] = CGPointMake(barCenter + _xFactor/2, _yFloor - _yFactor * barData[a].close);
                
            } else {    // red bar
                if (self.stock.chartType == 0) { // include open
                    _points[_pointCount++] = CGPointMake(barCenter - self.xFactor/2, _yFloor - _yFactor * barData[a].open);
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].open);
                }
                
                _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].high);
                _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].low);
                
                _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].close);
                _points[_pointCount++] = CGPointMake(barCenter + _xFactor/2, _yFloor - _yFactor * barData[a].close);
            }
            
        } else if (self.stock.chartType == 2 ) { // candlestick
            
            barHeight = _yFactor * (barData[a].open - barData[a].close);
            
            if (fabs(barHeight) < 1) {
                barHeight = barHeight > 0 ? 1 : -1;
            }
            
            // Filled up closes or hollow down closes are rare, so draw those points directly to avoid an extra array
            
            if (barData[a].open >= barData[a].close) {  // filled bar (StockCharts colors closes higher > lastClose && close < open as filled black self.bars)
                
                if (oldestClose < barData[a].close) { // filled green bar
                    
                    _filledGreenBars[_filledGreenCount++] = CGRectMake(barCenter - _xFactor * 0.4, _yFloor - _yFactor * barData[a].open, 0.8 * self.xFactor, barHeight);
                    
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].high);
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].low);
                    
                } else {
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * barData[a].high);
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * barData[a].low);
                    _redBars[_redBarCount++] = CGRectMake(barCenter - self.xFactor * 0.4, _yFloor - _yFactor * barData[a].open, 0.8 * self.xFactor, barHeight);
                }
                
            } else {
                
                if (oldestClose > barData[a].close) { // red hollow bar
                    
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * barData[a].high);
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * barData[a].close);
                    
                    _hollowRedBars[_hollowRedCount++] = CGRectMake(barCenter - self.xFactor * 0.4, _yFloor - _yFactor * barData[a].open, 0.8 * self.xFactor, barHeight);
                    
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * barData[a].open);
                    _redPoints[_redPointCount++] =  CGPointMake(barCenter, _yFloor - _yFactor * barData[a].low);
                    
                } else {
                    
                    _greenBars[_whiteBarCount++] = CGRectMake(barCenter - self.xFactor * 0.4, _yFloor - _yFactor * barData[a].open, 0.8 * _xFactor, barHeight);
                    
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].high);
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].close);
                    
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].open);
                    _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].low);
                }
            }
            
        } else if (self.stock.chartType == 3 ) { // Close
            _points[_pointCount++] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].close);
        }

        // It may seem inefficient to check the BOOL and the CGFloat value, but this is optimal
        // the indicator counts are based on the number of points in view, not the number calculated
        // that's why the counts must be reset after each redraw instead of when recalculating the indicators
        NSInteger offset = a - _newestBarShown;
        
        if (sma50 && barData[a].movingAvg1 > 0.) {
            _movingAvg1Count++;
            _movingAvg1[offset] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].movingAvg1);
        }
        
        if (sma200 && barData[a].movingAvg2 > 0.) {
            _movingAvg2Count++;
            _movingAvg2[offset] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].movingAvg2);
        }
        
        if (bb20 && barData[a].mbb > 0.) {
            _bbCount++;
            _ubb[offset] = CGPointMake(barCenter, _yFloor - _yFactor * (barData[a].mbb + 2*barData[a].stdev));
            _mbb[offset] = CGPointMake(barCenter, _yFloor - _yFactor * barData[a].mbb);
            _lbb[offset] = CGPointMake(barCenter, _yFloor - _yFactor * (barData[a].mbb - 2*barData[a].stdev));
        }
        
        if (barData[a].volume <= 0) {
     //       DLog(@"volume shouldn't be zero but is for a=%ld", a);
        } else {
            if (oldestClose > barData[a].close) {
                    _redVolume[_redCount++] = CGRectMake(barCenter - _xFactor/2, volumeBase, _xFactor, -barData[a].volume/volumeFactor);
                    
            } else { 
                    _blackVolume[_blackCount++] = CGRectMake(barCenter - _xFactor/2, volumeBase, _xFactor, -barData[a].volume/volumeFactor);
            }
        }
    
        oldestClose = barData[a].close;
        xRaw += _xFactor;            // keep track of the unaligned value or the chart will end too soon
    }
    self.ready = YES;
}

@end
