#include <dispatch/dispatch.h>
#import <CoreGraphics/CoreGraphics.h>
#import "FundamentalAPI.h"
#import "StockData.h"
#import <QuartzCore/QuartzCore.h>
#import "Series.h"


@implementation StockData

- (BarStruct *) barAtIndex:(NSInteger)index setUpClose:(BOOL *)upClose {
    if (index > bars) {
        return nil;
    }
   *upClose = YES;
    
    if (index < bars - 1) { // check for up/down close
        if (barData[index].close < barData[index + 1].close) {
            *upClose = NO;
        }
    } else if (barData[index].close < barData[index].open) {
        *upClose = NO;
    }
    return &barData[index];
}


- (NSDictionary *) infoForBarAtIndex:(NSInteger)index {

    if (index > bars) {
        return nil;
    }
    
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithCapacity:3];
    
    // edgar uses YYYYMMDD and Google uses M/d/YYYY so it's better to keep the date parts as separate ints in an array
    
    NSMutableArray *endDate = [NSMutableArray arrayWithCapacity:3];
   
    NSMutableArray *startDate = [NSMutableArray arrayWithCapacity:3];
    
    NSDate *barDate = [self.api dateFromBar:barData[index]];
    [self.days setDay:-5];      // start date should be a few days before to handle news posted on Friday after the close that is reflected on Monday
    barDate = [self.gregorian dateByAddingComponents:self.days toDate:barDate options:0];
    
    NSUInteger unitFlags = NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitYear;
    NSDateComponents *dateParts = [self.gregorian components:unitFlags fromDate:barDate];
    
    [startDate addObject:[NSNumber numberWithLong:[dateParts year]]];
    [startDate addObject:[NSNumber numberWithLong:[dateParts month]]];
    [startDate addObject:[NSNumber numberWithLong:[dateParts day]]];
    
    NSInteger endYear = 0;
    NSInteger endMonth = 0;
    NSInteger endDay = 0;
    
    if (barUnit == 1.) {
        endYear = barData[index].year;
        endMonth = barData[index].month;
        endDay = barData[index].day;
    } else if (index > 0 ) {
        // most efficient method is to get a newer bar and then subtract a day
        NSDate *nextBarDate = [self.api dateFromBar:barData[index - 1]];
        
        [self.days setDay:-1];
        nextBarDate = [self.gregorian dateByAddingComponents:self.days toDate:nextBarDate options:0];
        
        dateParts = [self.gregorian components:unitFlags fromDate:nextBarDate];
              
        endYear = [dateParts year];
        endMonth = [dateParts month];
        endDay = [dateParts day];
        
    } else {         // newest date
        endYear = dailyData[0].year;
        endMonth = dailyData[0].month;
        endDay = dailyData[0].day;
    }
    [endDate addObject:[NSNumber numberWithLong:endYear]];
    [endDate addObject:[NSNumber numberWithLong:endMonth]];
    [endDate addObject:[NSNumber numberWithLong:endDay]];
    
    // don't multiply by barUnit
    CGFloat x = 5 + xFactor * (0.5 + oldestBarShown - index) / UIScreen.mainScreen.scale;
    CGFloat y = 5 + (yFloor - yFactor * barData[index].high) / UIScreen.mainScreen.scale;
    
    [info setObject:startDate forKey:@"startDate" ];
    [info setObject:endDate forKey:@"endDate" ];
    [info setObject:[NSString stringWithFormat:@"%ld%02ld%02ldT20:00:00Z", endYear, endMonth, endDay] forKey:@"endDateString"];
    [info setObject:self.series.symbol forKey:@"symbol"];

    if (self.series->hasFundamentals > 0) {
        [info setObject:@"YES" forKey:@"hasFundamentals"];
    } else {
        [info setObject:@"NO" forKey:@"hasFundamentals"];
    }
    [info setObject:[NSValue valueWithCGPoint:CGPointMake(x,y)] forKey:@"arrowTip"];

    [info setObject:[self.api URLEncode:self.series.symbol] forKey:@"symbolEncoded"];
    
    return info;
}


- (NSInteger) newestBarShown { return newestBarShown; }

- (void) setNewestBarShown:(NSInteger)offsetBar {         // avoid negative values for newest bar
    if (offsetBar < 0) {       
        newestBarShown = 0;
    } else {
        newestBarShown = offsetBar;
    }
}

- (void) setPxHeight:(double)h withSparklineHeight:(double)s {
    sparklineHeight = s;
    pxHeight = h - sparklineHeight;
    
    volumeHeight = 40 * UIScreen.mainScreen.scale;
    
    volumeBase = h - volumeHeight/2;

    self.chartBase = [[[NSDecimalNumber alloc] initWithDouble:(volumeBase - volumeHeight/2 - sparklineHeight)] autorelease];
}

- (void)dealloc {
    [self.fundamentalAPI setDelegate:nil];
    [_fundamentalAPI release];
    [self.api setDelegate:nil];
    [self.api release];
    self.delegate = nil;
    // don't release memory I didn't alloc in StockData, like the gregorian calendar
    
    if (barData != dailyData) {
        // DLog(@"Dealloc: barData has a different address than dailyData");
        free(barData);
    }
    free(dailyData);
    
    free(blackVolume);
    free(filledGreenBars);
    free(fundamentalAlignments);
    free(greenBars);
    free(grids);
    free(hollowRedBars);
    free(lbb);
    free(mbb);
    free(monthLines);
    free(movingAvg1);
    free(movingAvg2);
    free(points);
    free(redBars);
    free(redPoints);
    free(redVolume);
    free(ubb);

    dispatch_release(concurrentQueue);
    [self.days release];
    [super dealloc];
}

- (void) initWithDaysAgo:(NSInteger)daysAgo {

    bars = dailyBars = newestBarShown = oldestReport = newestReport = movingAvg1Count = movingAvg2Count = 0;
    self.api = NULL;
    busy = ready = NO;
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
    
    blackVolume = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    filledGreenBars = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    fundamentalAlignments = (CGFloat *)malloc(sizeof(CGFloat)*99);
    greenBars = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    grids = (CGPoint*)malloc(sizeof(CGPoint)*20);
    hollowRedBars = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    lbb = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    mbb = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    monthLines = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    movingAvg1 = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    movingAvg2 = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    points = (CGPoint*)malloc(sizeof(CGPoint) * maxBars * 6);
    redBars = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    redPoints = (CGPoint*)malloc(sizeof(CGPoint) * maxBars * 2);
    redVolume = (CGRect *)malloc(sizeof(CGRect) * maxBars);
    ubb = (CGPoint *)malloc(sizeof(CGRect) * maxBars);
    
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
    
    [self.series convertDateStringToDateWithFormatter:self.api.dateFormatter];
    
    [self.api setRequestOldestDate:[self.series.startDate laterDate:[NSDate dateWithTimeInterval:(200+oldestBarShown * barUnit)*-240000 sinceDate:desiredDate]]];

    [self setNewest:self.api.requestOldestDate];    // better than oldestPast
    
    [self.api setSymbol:self.series.symbol];
    [self.api setSeriesId:self.series->id];
    [self.api setGregorian:self.gregorian];
    [self.api setDelegate:self];
        
    NSString *concurrentName = [NSString stringWithFormat:@"com.chartinsight.%ld.%ld", self.series->id, daysAgo];
    
    concurrentQueue = dispatch_queue_create([concurrentName UTF8String], DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_set_target_queue(concurrentQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));

    [self setFundamentalAPI:nil];

    [self.api getInitialData];

    if ([self.series fundamentalList].length > 4) {
        [self.delegate performSelector:@selector(showProgressIndicator)];
        [self setFundamentalAPI:[[FundamentalAPI alloc] init]];
        [self.fundamentalAPI getFundamentalsForSeries:self.series withDelegate:self];
    }
}

- (void) APILoadedFundamentalData:(FundamentalAPI *)fundamental {
    
    // DLog(@"%d fundamental values loaded", [[fundamental year] count]);
    if (self->busy == NO && bars > 1) {
        dispatch_barrier_sync(concurrentQueue, ^{ [self updateFundamentalAlignment];
                                                                            [self computeChart];    });
        [self.delegate performSelectorOnMainThread:@selector(requestFinished:) withObject:self.percentChange waitUntilDone:NO];
    } else {
        [self.delegate performSelectorOnMainThread:@selector(stopProgressIndicator) withObject:nil waitUntilDone:NO];
    }
}


// When calculating the simple moving average, there are 3 possible cases:
// 1. all bars are new
//        Start with bar 0 and continue until the end
// 
// 2. adding bars to the front
//        Start with bar 0 and continue until the first old bar
// 
// 3. adding bars to the end
//        Start with the oldest bar and walk towards the start of the array to find the first empty moving average
// 
// For example, div LINE the ratio of the adjusted close varies slightly
- (void) calculateSMA {
    
    NSInteger oldest50available, oldest150available, oldest200available;
    oldest50available = bars - 50;
    oldest150available = bars - 150;
    oldest200available = bars - 200;
    
    if (oldest50available > 0) {
        double movingSum50 = 0.0f;
        double movingSum150 = 0.0f;
        
        // add last n bars, then start subtracting i + n - 1 bar to compute average
    
        for (NSInteger i = bars - 1; i >= 0; i--) {
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
                
            } else if (i == oldest50available) {            // don't subtract any bars
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
    NSInteger firstFullPeriod = bars - period;
    
    if (firstFullPeriod > 0) {
        double movingSum = 0.0f;
        double powerSumAvg = 0.0f;
        
        // add last n bars, then start subtracting i + n - 1 bar to compute average
        
        for (NSInteger i = bars - 1; i >= 0; i--) {
            movingSum += barData[i].close;
            
            if (i < firstFullPeriod) {
                movingSum -= barData[i + period].close;
                
                barData[i].mbb = movingSum / period;
                powerSumAvg += (barData[i].close * barData[i].close - barData[i + period].close * barData[i + period].close)/(period);
 
                barData[i].stdev = sqrt(powerSumAvg - barData[i].mbb * barData[i].mbb);
                                 
            } else if (i >= firstFullPeriod) {
                powerSumAvg += (barData[i].close * barData[i].close - powerSumAvg)/(bars - i);
                 
                if (i == firstFullPeriod) {            // don't subtract any bars
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
            
            while (i < bars && (barData[i].year > lastReportYear ||  barData[i].month > lastReportMonth)) {
                i++;
            }
            if (i < bars && barData[i].year == lastReportYear && barData[i].month == lastReportMonth) {
                
                [self.fundamentalAPI setBarAlignment:i forReport:r];
            }
        }
    }   
}

// Called after shiftRedraw shifts the oldestBarShown and newestBarShown during scrolling
- (void) updateHighLow {
    
    if (oldestBarShown <= 0) {
        return;
    }
    
    double max = 0.0, min = 0.0;
    maxVolume = 0.0;
        
    for (NSInteger a = oldestBarShown; a >= newestBarShown ; a--) {
        if (barData[a].volume > maxVolume) {
            maxVolume = barData[a].volume;
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

- (void) removeNewerBars:(NSInteger)dailyBarsToRemove {
    
    if (dailyBars < dailyBarsToRemove) {
        DLog(@"%@ only has %ld dailyBars, so canceling removeNewerBars", self.series.symbol, dailyBars);
        return;
    }
    DLog(@"%@ adding to %ld dailyBars would exceed %ld so removing %ld newer bars", self.series.symbol, dailyBars, [self.api maxBars], dailyBarsToRemove);
    
    dailyBars -= dailyBarsToRemove;        // remove 1000 bars
    
    NSInteger summaryBarsToRemove = (dailyBarsToRemove/barUnit);
    bars -= summaryBarsToRemove;
    
    [self createNewBarDataWithShift:0 fromIndex:dailyBarsToRemove];
  
    newestBarShown -= summaryBarsToRemove;
    oldestBarShown -= summaryBarsToRemove;
    
    [self setNewest:[self.api dateFromBar:dailyData[0]]];
    [self.api adjustNewestDateLoadedTo:self.newest];
    DLog(@"%@ after removing 1000 dailyBars, newwest is %@", self.series.symbol, self.newest);
    [self updateFundamentalAlignment];  // bar alignment will be off by 1000 bars
}

- (NSDecimalNumber *) shiftRedraw:(NSInteger)barsShifted withBars:(NSInteger)screenBarWidth {
    
    if (oldestBarShown + barsShifted >= [self.api maxBars]) {
        [self removeNewerBars:screenBarWidth];
    }
    oldestBarShown += barsShifted;
        
    [self setNewestBarShown:(oldestBarShown - screenBarWidth)];     // handles negative values
    
    // DLog(@"oldestBarShown %d and newestBarShown in shiftREdraw is %d", oldestBarShown, newestBarShown);
        
    if (oldestBarShown <= 0) {  // no bars to show yet
        // DLog(@"%@ oldestBarShown is less than zero at %d", self.series.symbol, oldestBarShown);
        [self clearChart];

    } else if (busy) {
        // Avoid deadlock by limiting concurrentQueue to updateHighLow and didFinishFetch
       // DLog(@"%@ is busy", self.series.symbol);

        dispatch_sync(concurrentQueue,  ^{    [self updateHighLow];     });
        return self.percentChange;
    }
            
    BOOL oldestNotYetLoaded = fabs([self.series.startDate timeIntervalSinceDate:self.oldest]) > 90000 ? YES : NO;
    
    if (oldestNotYetLoaded && oldestBarShown > bars - 201) {      // load older dates or moving average will break

        busy = YES;
        [self.delegate performSelectorOnMainThread:@selector(showProgressIndicator) withObject:nil waitUntilDone:NO];
            
   //     NSDate *requestStart = [[self.series startDate] laterDate:[self.oldest dateByAddingTimeInterval:MAX(365,screenBarWidth)* barUnit *-86400]];
                                    
        [self.api getOlderDataFrom:self.series.startDate untilDate:self.oldest];

    } else if (0 == newestBarShown) {
        
        if ([self.api.nextClose isTodayIntraday]) {
            busy = YES;
            [self.api getIntradayQuote];

        } else if ([self.api.nextClose compare:[NSDate date]] == NSOrderedAscending) { // next close is in the past
            busy = YES;            
            [self.delegate performSelectorOnMainThread:@selector(showProgressIndicator) withObject:nil waitUntilDone:NO];
            [self.api getNewerThanDate:[self newest] screenBarWidth:screenBarWidth];
        }
    }
    
    dispatch_sync(concurrentQueue,  ^{    [self updateHighLow];     });
    
    return self.percentChange;
}

- (void) updateBools {
    
    BOOL sma50old = sma50, sma200old = sma200;
    
    sma50 = [[self.series technicalList] rangeOfString:@"sma50"].length > 0 ? YES : NO;
    sma200 = [[self.series technicalList] rangeOfString:@"sma200"].length > 0 ? YES : NO;
    
    if ((sma200 && sma200old == NO) || (sma50 && sma50old == NO)) {
        [self calculateSMA];
    }
    
    if ([[self.series technicalList] rangeOfString:@"bollingerBand"].length > 0) {
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
        
        // DLog(@"%@ pctDifference %f so pct changing from %@ to %@", [self.series symbol], pctDifference, self.chartPercentChange, maxPercentChange);
        [self setChartPercentChange:maxPercentChange];
        
        [self setScaledLow:[self.maxHigh decimalNumberByDividingBy:self.chartPercentChange]];
        
        dispatch_sync(concurrentQueue, ^{   [self computeChart];    });
    } else {
        [self setChartPercentChange:maxPercentChange];
        [self setScaledLow:[self.maxHigh decimalNumberByDividingBy:self.chartPercentChange]];
    }
}

- (void) APICanceled:(DataAPI *) dp {
    busy = NO;
    NSString *message = @"Canceled request";
    [self.delegate performSelectorOnMainThread:@selector(requestFailedWithMessage:) withObject:message waitUntilDone:NO];
}

// If we were redirected, then the user must be on a wifi network that requires login. Show a UIWebView to allow login
- (void) APIRedirected {
    busy = NO;
//    [self.delegate performSelectorOnMainThread:@selector(showWifiLogin) withObject:nil waitUntilDone:NO];
}


-(void) APIFailed:(NSString *)message {
    busy = NO;
    [self.delegate performSelectorOnMainThread:@selector(requestFailedWithMessage:) withObject:message waitUntilDone:NO];
}

// memove won't throw away bars to avoid a buffer overrun, so we have to do it ourselves with memcpy
- (void) createNewBarDataWithShift:(NSInteger)shift fromIndex:(NSInteger)fromIndex {
    
    BarStruct *newDailyData = (BarStruct *)malloc(sizeof(BarStruct)*[self.api maxBars]);

    if (dailyBars + shift > [self.api maxBars]) {     // avoid buffer overrun
        dailyBars -= shift;
    }
    memcpy(&newDailyData[shift], &dailyData[fromIndex], dailyBars * sizeof(BarStruct));
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
          //  DLog(@"intraday moving %d bars by 1", bars);
            [self createNewBarDataWithShift:1 fromIndex:0];
            dailyBars++;
            // bars may or may not increase; let summarizeByDate figure that out
            oldMovingAvg1 = oldMovingAvg2 = .0f;

        } else { // save before overwriting with memcpy
            oldMovingAvg1 = dailyData[0].movingAvg1;
            oldMovingAvg2 = dailyData[0].movingAvg2;
        }
        
        // copy intraday data to barData
        memcpy( dailyData, &dp->intradayBar, sizeof(BarStruct));
        
        [self setLastPrice:[[[NSDecimalNumber alloc] initWithDouble:dailyData[0].close] autorelease]];
        
        [self setNewest:apiNewest];

        // For intraday update to weekly or monthly chart, decrement oldestBarShown only if
        //    the intraday bar is for a different period (week or month) than the existing newest bar
        
        [self summarizeByDateFrom:0 oldBars:0];
        [self updateHighLow]; // must be a separate call to handle daysAgo shifting

        self->busy = NO;
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
    
    while (i < dailyBars && 0 < 20000 * (dailyData[i].year - friday.year) + 100 * (dailyData[i].month - friday.month) + dailyData[i].day - friday.day) {
        
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
    
    if (i < dailyBars) {
        bars = wi;
        wi++;
        [self groupByWeek:lastFriday dailyIndex:i weeklyIndex:wi];
    } else {
        bars = wi + 1;  // bars is a count not a zero index
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
        
    while (i < dailyBars && dailyData[i].month == barData[mi].month) {
        
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
    
    if (i < dailyBars) {
        bars = mi;
        mi++;
        [self groupByMonthFromDailyIndex:i monthlyIndex:mi];
    } else {
        bars = mi + 1;  // bars is a count not a zero index
   //     // DLog(@"final bars value %d", bars);
    }
}

- (void) summarizeByDateFrom:(NSInteger)oldDailyBars oldBars:(NSInteger)oldBars {

    // on average there are about 4.6 trading days in a week. Dividing by 4 provides sufficient room
    
    if (barUnit == 1.) {
        barData = dailyData;
        bars = dailyBars;
    } else if (barUnit > 3 && barData == dailyData) {
         barData = (BarStruct *)malloc(sizeof(BarStruct)*([self.api maxBars] / 4));
    }
    
    if (barUnit > 5) {
         [self groupByMonthFromDailyIndex:oldDailyBars monthlyIndex:oldBars];
    } else if (barUnit > 3) {
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
        NSInteger startCopy = 0;             // copy to start of dailyData.  If dailyBars > 0, move existing data first
        BOOL checkPrefetch = NO, shiftBarsShown = NO;
        NSDate *desiredDate;
        NSDate *apiNewest = [self.api dateFromBar:dp->cArray[0]];
    
        //DLog(@"%@ dailyBars %ld self.newest %@ and api.newest %@ and api.oldest %@", dp.symbol, dailyBars, self.newest, apiNewest, self.api.oldestDate);
  
        if (dailyBars == 0) { // case 1. First request
            if (self.series->daysAgo > 0) {
                checkPrefetch = YES;
                [self.days setDay: - self.series->daysAgo];
                // [self setNewest:[self.gregorian dateByAddingComponents:self.days toDate:[NSDate date] options:0]];
                desiredDate = [self.gregorian dateByAddingComponents:self.days toDate:[NSDate date] options:0];
             }
            [self setNewest:apiNewest];
            [self setLastPrice:[[[NSDecimalNumber alloc] initWithDouble:dp->cArray[0].close] autorelease]];  // if daysAgo > 0, lastPrice will be off until all newer data is fetched
            [self setOldest:[self.api oldestDate]];
            
        } else if ([self.newest compare:apiNewest] == NSOrderedAscending) {         // case 2. Newer dates
            DLog(@"api is newer, so moving by %ld bars", dp->countBars);
            checkPrefetch = YES;
            shiftBarsShown = YES;   // because of the following createNewBarDataWithShift call
            [self createNewBarDataWithShift:dp->countBars fromIndex:0];     // move current bars by dp->countBars
            [self setNewest:apiNewest];
            desiredDate = self.newest;
            [self setLastPrice:[[[NSDecimalNumber alloc] initWithDouble:dp->cArray[0].close] autorelease]];  // if daysAgo > 0, lastPrice will be off until all newer data is fetched
            
        } else if ([self.oldest compare:[self.api oldestDate]] == NSOrderedDescending) {    // case 3. Older dates
        
            if ((dailyBars + dp->countBars) > [self.api maxBars]) {
                [self removeNewerBars:dp->countBars];
            }
            startCopy = dailyBars;      // copy to end of dailyDaily
            
            [self setOldest:[self.api oldestDate]];
        }
        
        if (dp->countBars > 0) {
            memcpy(&dailyData[startCopy], dp->cArray, dp->countBars * sizeof(BarStruct));        // copy to start of barData the dp->cArray NEWER data
       
            DLog(@"%@ added %ld new bars to %ld exiting dailyBars", self.series.symbol, dp->countBars, dailyBars);
            
            NSInteger oldBars = bars;
            NSInteger oldDailyBars = dailyBars;
            dailyBars += dp->countBars;
            
            [self summarizeByDateFrom:oldDailyBars oldBars:oldBars];
            
            if (shiftBarsShown) {
                newestBarShown += (bars - oldBars);
                oldestBarShown += (bars - oldBars);
            }
            
            if (checkPrefetch) {
                 
                while ([desiredDate timeIntervalSinceDate:[self.api dateFromBar:barData[newestBarShown]]] < 0) {        // prefetched dates newer than those requested, so shift newestBarShown
                    
                     ++newestBarShown;
                     ++oldestBarShown;
                }
            }
             [self updateHighLow];
        }
        busy = NO;
        [self.delegate performSelectorOnMainThread:@selector(stopProgressIndicator) withObject:nil waitUntilDone:NO];
      });
    
    DLog(@"after %ld bars (%ld new), newest %@ and oldest %@", bars, dp->countBars, self.newest, self.oldest);

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
    pointCount = redBarCount = whiteBarCount = monthCount = blackCount = redCount = redPointCount = movingAvg1Count = movingAvg2Count = bbCount = 0;
    hollowRedCount = filledGreenCount = 0;
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
 
    ready = NO;
    
    CGFloat xRaw, barCenter, barHeight;
    double oldestClose, volumeFactor;
    NSInteger oldestValidBar; 
    xRaw = xFactor/2;
    
    [self clearChart];
    
    if (oldestBarShown < 1 || bars == 0) { 
        ready = YES;
        return; // No bars to draw
        
    } else if (oldestBarShown < bars) {
        oldestValidBar = oldestBarShown;
        oldestClose = barData[oldestValidBar + 1].open;
        
    } else if (oldestBarShown >= bars) {    // don't load garbage data
        oldestValidBar = bars - 1;        
        xRaw += xFactor * (oldestBarShown - oldestValidBar);
        oldestClose = barData[oldestValidBar].open;
    }
    
    if (self.fundamentalAPI.columns.count > 0) {
        
        oldestReport = self.fundamentalAPI.year.count - 1;
        
        newestReport = 0;
        NSInteger lastBarAlignment = 0;
        
        for (NSInteger r = 0; r <= oldestReport; r++) {
            
            lastBarAlignment = [self.fundamentalAPI barAlignmentForReport:r];
            
            if (newestReport > 0 && lastBarAlignment == -1) { 
              //  DLog(@"ran out of trading data after report %d", newestReport);

            } else if (lastBarAlignment > 0 && lastBarAlignment <= newestBarShown) { // && lastBarAlignment <= newestBarShown) {
               //  DLog(@"lastBarAlignment %d <= %d so newestReport = %d", lastBarAlignment, newestBarShown, r);
                newestReport = r;
            }
            
            if (lastBarAlignment > oldestValidBar || -1 == lastBarAlignment) {
                oldestReport = r;       // first report just out of view
                // DLog(@" lastBarAlignment %d > %d oldestValidBar or not defined", lastBarAlignment, oldestValidBar);
                break;
            }
        }        
        
        if (oldestReport == newestReport) {     // include offscreen report
            if (newestReport > 0) {
                newestReport--;
            } else if (oldestReport == 0) {
                oldestReport++;
            }
        }
        
        NSDecimalNumber *reportValue;
        
        // Only SCC can calculate min and max values across multiple stocks in a comparison
        // SCC will also calculate the labels, so keep the NSDecimalNumber originals and just calculate quarter-end x values
        
        // Use NSMutableArray to preserve the order 
        // book value must be handled separately because we DO need to calculate the min and max values and use those on the main chart
        // yFactor            
        
        if ([[self.fundamentalAPI columns] objectForKey:@"BookValuePerShare"] != nil) {
            NSInteger r = newestReport;
            
            do {
                reportValue = [self.fundamentalAPI valueForReport:r withKey:@"BookValuePerShare"];
                
            } while ([reportValue isEqualToNumber:[NSDecimalNumber notANumber]] && ++r <= oldestReport);
            
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
                } while (r < oldestReport);
            }
        }
        
        NSInteger r = newestReport;
        self.fundamentalAPI.newestReportInView = newestReport;
        
        NSInteger barAlignment = lastBarAlignment = -1;
        
        do {
            lastBarAlignment = barAlignment;
            barAlignment = [self.fundamentalAPI barAlignmentForReport:r];
            
            if (barAlignment < 0) {
                break;
            }
            
            fundamentalAlignments[r] = (oldestValidBar - barAlignment + 1) * xFactor + xRaw;
            r++;
        } while (r <= oldestReport);
        
        if (barAlignment < 0) {
            fundamentalAlignments[r] = (oldestValidBar - lastBarAlignment + 1) * xFactor + xRaw; 
        }
        
        self.fundamentalAPI.oldestReportInView = r;
    }
    
    // TO DO: move this to updateHighLow    
    NSDecimalNumber *range = [self.maxHigh decimalNumberBySubtracting:self.scaledLow];
    
    if ([range isEqualToNumber:[NSDecimalNumber zero]] == NO) {
        
        yFactor = [[self.chartBase decimalNumberByDividingBy:range] doubleValue];
    } else {
       // DLog(@"%@ range is %@ so would be a divide by zero, skipping computeChart", series.symbol, range);
        ready = YES;    // prevent unending scroll wheel
        return;
    }
        
    yFloor = yFactor * [self.maxHigh doubleValue] + sparklineHeight;

    volumeFactor = maxVolume/volumeHeight;

    // If we lack older data, estimate lastClose using oldest open
    [self.monthLabels removeAllObjects];
    
    NSString *label;
    
    lastMonth = barData[oldestValidBar].month;

    for (NSInteger a = oldestValidBar; a >= newestBarShown; a--) {
        
        barCenter = [self pxAlign:xRaw alignTo:0.5]; // pixel context
        
        if (barData[a].month != lastMonth) {
            label = [self monthName:barData[a].month];
            if (barData[a].month == 1) {
                if (bars < dailyBars || xFactor < 4) { // not enough room
                    label = [[NSString stringWithFormat:@"%ld", (long)barData[a].year] substringFromIndex:2];
                } else {
                    label = [label stringByAppendingString:[[NSString stringWithFormat:@"%ld", (long)barData[a].year] substringFromIndex:2]];
                }
                
            } else if (barUnit > 5) {   // only year markets
                label = @"";
            } else if (bars < dailyBars || xFactor < 2) { // shorten months
                label = [label substringToIndex:1];
            }

            if (label.length > 0) {
                [self.monthLabels addObject:label];
                monthLines[monthCount++] = CGPointMake(barCenter - 2, sparklineHeight);
                monthLines[monthCount++] = CGPointMake(barCenter - 2, volumeBase);
            }
            
        }
        lastMonth = barData[a].month;
        
        if (self.series->chartType < 2) {      //OHLC or HLC
            
            if (oldestClose > barData[a].close) { // green bar
                if (self.series->chartType == 0) { // include open
                    redPoints[redPointCount++] = CGPointMake(barCenter - xFactor/2, yFloor - yFactor * barData[a].open);
                    redPoints[redPointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].open);
                }
                
                redPoints[redPointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].high);
                redPoints[redPointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].low);
                
                redPoints[redPointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].close);
                redPoints[redPointCount++] = CGPointMake(barCenter + xFactor/2, yFloor - yFactor * barData[a].close);
                
            } else {    // red bar
                if (self.series->chartType == 0) { // include open
                    points[pointCount++] = CGPointMake(barCenter - xFactor/2, yFloor - yFactor * barData[a].open);
                    points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].open);
                }
                
                points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].high);
                points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].low);
                
                points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].close);
                points[pointCount++] = CGPointMake(barCenter + xFactor/2, yFloor - yFactor * barData[a].close);
            }
            
        } else if (self.series->chartType == 2 ) { // candlestick
            
            barHeight = yFactor * (barData[a].open - barData[a].close);
            
            if (fabs(barHeight) < 1) {
                barHeight = barHeight > 0 ? 1 : -1;
            }
            
            // Filled up closes or hollow down closes are rare, so draw those points directly to avoid an extra array
            
            if (barData[a].open >= barData[a].close) {  // filled bar (StockCharts colors closes higher > lastClose && close < open as filled black bars)
                
                if (oldestClose < barData[a].close) { // filled green bar
                    
                    filledGreenBars[filledGreenCount++] = CGRectMake(barCenter - xFactor * 0.4, yFloor - yFactor * barData[a].open, 0.8 * xFactor, barHeight);
                    
                    points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].high);
                    points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].low);
                    
                } else {
                    redPoints[redPointCount++] =  CGPointMake(barCenter, yFloor - yFactor * barData[a].high);
                    redPoints[redPointCount++] =  CGPointMake(barCenter, yFloor - yFactor * barData[a].low);
                    redBars[redBarCount++] = CGRectMake(barCenter - xFactor * 0.4, yFloor - yFactor * barData[a].open, 0.8 * xFactor, barHeight);
                }
                
            } else {
                
                if (oldestClose > barData[a].close) { // red hollow bar
                    
                    redPoints[redPointCount++] =  CGPointMake(barCenter, yFloor - yFactor * barData[a].high);
                    redPoints[redPointCount++] =  CGPointMake(barCenter, yFloor - yFactor * barData[a].close);
                    
                    hollowRedBars[hollowRedCount++] = CGRectMake(barCenter - xFactor * 0.4, yFloor - yFactor * barData[a].open, 0.8 * xFactor, barHeight);
                    
                    redPoints[redPointCount++] =  CGPointMake(barCenter, yFloor - yFactor * barData[a].open);
                    redPoints[redPointCount++] =  CGPointMake(barCenter, yFloor - yFactor * barData[a].low);
                    
                } else {
                    
                    greenBars[whiteBarCount++] = CGRectMake(barCenter - xFactor * 0.4, yFloor - yFactor * barData[a].open, 0.8 * xFactor, barHeight);
                    
                    points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].high);
                    points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].close);
                    
                    points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].open);
                    points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].low);
                }
            }
            
        } else if (self.series->chartType == 3 ) { // Close
            points[pointCount++] = CGPointMake(barCenter, yFloor - yFactor * barData[a].close); 
        }

        // It may seem inefficient to check the BOOL and the CGFloat value, but this is optimal
        // the indicator counts are based on the number of points in view, not the number calculated
        // that's why the counts must be reset after each redraw instead of when recalculating the indicators
        NSInteger offset = a - newestBarShown;
        
        if (sma50 && barData[a].movingAvg1 > 0.) {
            movingAvg1Count++;
            movingAvg1[offset] = CGPointMake(barCenter, yFloor - yFactor * barData[a].movingAvg1);
        }
        
        if (sma200 && barData[a].movingAvg2 > 0.) {
            movingAvg2Count++;
            movingAvg2[offset] = CGPointMake(barCenter, yFloor - yFactor * barData[a].movingAvg2);
        }
        
        if (bb20 && barData[a].mbb > 0.) {
            bbCount++;
            ubb[offset] = CGPointMake(barCenter, yFloor - yFactor * (barData[a].mbb + 2*barData[a].stdev));
            mbb[offset] = CGPointMake(barCenter, yFloor - yFactor * barData[a].mbb);
            lbb[offset] = CGPointMake(barCenter, yFloor - yFactor * (barData[a].mbb - 2*barData[a].stdev));
        }
        
        if (barData[a].volume <= 0) {
     //       DLog(@"volume shouldn't be zero but is for a=%ld", a);
        } else {
            if (oldestClose > barData[a].close) {
                    redVolume[redCount++] = CGRectMake(barCenter - xFactor/2, volumeBase, xFactor, -barData[a].volume/volumeFactor);
                    
            } else { 
                    blackVolume[blackCount++] = CGRectMake(barCenter - xFactor/2, volumeBase, xFactor, -barData[a].volume/volumeFactor);
            }
        }
    
        oldestClose = barData[a].close;
        xRaw += xFactor;            // keep track of the unaligned value or the chart will end too soon
    }
    ready = YES;
}

@end
