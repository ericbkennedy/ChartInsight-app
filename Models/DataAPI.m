#import "CIAppDelegate.h"
#import "DataAPI.h"
#import "sqlite3.h"

const char *API_KEY = "placeholderToken";

@interface DataAPI () {
@private
    NSInteger barsFromDB;
}

@property (nonatomic, copy) NSString *csvString;
@property (strong, nonatomic) NSURLSession *ephemeralSession;   // skip web cache since sqlite caches price data
@property (nonatomic, assign) BOOL loadingData;
@property (strong, nonatomic) NSDate *lastOfflineError;
@property (strong, nonatomic) NSDate *lastNoNewDataError;       // set when a 404 occurs on a request for newer data
@property (strong, nonatomic) NSDate *newestDateLoaded;         // rule out newer gaps by tracking the newest date loaded

-(void)fetch;
-(NSURL *) formatRequestURL;
-(void)historicalDataLoaded;
-(void)parseHistoricalCSV;

@end

@implementation DataAPI

- (NSInteger) maxBars {
    return 10000;    // Supports 50 years of price data (though API limits price data to 2009 start of XML fundamentals)
}

-(id) init {
    self = [super init];
    
    // NOTE: this should really be the max that we would request at any one time, since stockData.barData is separate memory
    cArray = (BarStruct *)malloc(sizeof(BarStruct)*[self maxBars]);
    
    self.ephemeralSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    
    [self setDateFormatter:[[NSDateFormatter alloc] init]];
    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]; // 1996-12-19T16:39:57-08:00
    [self.dateFormatter setLocale: locale];  // override user locale
    [self.dateFormatter setDateFormat:@"yyyyMMdd'T'HH':'mm':'ss'Z'"];  // Z means UTC time
    [self.dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        
    return self;
}

// Will invalidate the NSURLSession used to fetch price data and clear references to trigger dealloc
- (void)invalidateAndCancel {
    [self.ephemeralSession invalidateAndCancel];
    _delegate = nil;
}

-(void)dealloc {
    [_dateFormatter release];
    _delegate = nil;
    free(cArray);    
    _csvString = nil;    // don't release it because the setter manages release count
    _symbol = nil;
    _oldestDate = nil;
    _newestDateLoaded = nil;
    [super dealloc];
}

-(BarStruct *)getCBarData {
    return cArray;
}

-(void) setBarData:(BarStruct *)barData {
    cArray = barData;
}

- (NSDate *) dateFromBar:(BarStruct)bar {

    NSString *dateString = [NSString stringWithFormat:@"%ld%02ld%02ldT20:00:00Z", bar.year, bar.month, bar.day];// 4pm NYC close
        
    return [self.dateFormatter dateFromString:dateString];
}

// Called BEFORE creating a URLSessionTask if there was a recent offline error or it is too soon to try again
-(void)cancelDownload {
    if (self.loadingData) {
        self.loadingData = NO;
    }
    [self.delegate performSelector:@selector(APICanceled:) withObject:self];
}

- (NSInteger) getIntegerFormatForDate:(NSDate *)date {
    assert(date != nil);
    
    NSUInteger unitFlags = NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitYear;
    NSDateComponents *dateParts = [self.gregorian components:unitFlags fromDate:date];
    
    return ([dateParts year] * 10000 + ([dateParts month]*100) + [dateParts day]);
}

- (BOOL) isHolidayDate:(NSDate *)date {
    
    NSInteger dateInt = [self getIntegerFormatForDate:date];
    
    switch (dateInt) {  // https://www.nyse.com/markets/hours-calendars
        case 20230619:
        case 20230704:
        case 20230904:
        case 20231123:
        case 20231225:
        case 20240101:
        case 20240115:
        case 20240219:
        case 20240329:
        case 20240527:
        case 20240619:
        case 20240704:
        case 20240902:
        case 20241128:
        case 20241225:
        case 20250101:
        case 20250120:
        case 20250217:
        case 20250418:
        case 20250526:
        case 20250619:
        case 20250704:
        case 20250901:
        case 20251127:
        case 20251225:
            return YES;
    }
    return NO;
}

- (NSDate *) getNextTradingDateAfterDate:(NSDate *)date {
    NSDate *nextTradingDate = [date copy];
    NSDateComponents *days = [[NSDateComponents alloc] init];
    [days setDay:1];
    
    do {
        nextTradingDate = [self.gregorian dateByAddingComponents:days toDate:nextTradingDate options:0]; // add another day
        
    } while ([self isHolidayDate:nextTradingDate]
             || 1 == [[self.gregorian components:NSCalendarUnitWeekday fromDate:nextTradingDate] weekday]   // Sunday
             || 7 == [[self.gregorian components:NSCalendarUnitWeekday fromDate:nextTradingDate] weekday]); // Saturday
    
    [days release];
    return nextTradingDate;
}

// tracking nextClose handles holidays, weekends, and when a user resumes using the app after inactivity
// but should only apply for NEWER dates, not when they scroll to the past

- (void) fetchNewerThanDate:(NSDate *)currentNewest screenBarWidth:(NSInteger)screenBarWidth {
     
    [self setRequestOldestDate:[self getNextTradingDateAfterDate:currentNewest]];
    
    // sets earlier of today or 1 year after oldest date
    [self setRequestNewestDate:[[NSDate date] earlierDate:[self.requestOldestDate dateByAddingTimeInterval:MAX(365, screenBarWidth)*86400]]];
     
   // DLog(@"requesting from %@ to %@", requestOldestDate, requestNewestDate);

    [self fetch];
}

- (void) fetchOlderDataFrom:(NSDate *)requestStart untilDate:(NSDate *)currentOldest {
    countBars = 0;
    
    [self setRequestNewestDate:[currentOldest dateByAddingTimeInterval:-86400]];   // avoid overlap
    
    [self setRequestOldestDate:requestStart]; 
    
   // DLog(@"%@ getOlderDates from %@ to %@", symbol, requestOldestDate, requestNewestDate);
    
    [self fetch];   
}

- (void) fetchInitialData {

    // prefetch by a year for older requests
    [self setRequestNewestDate:[[NSDate date] earlierDate:[self.requestNewestDate dateByAddingTimeInterval:365*86400]]];

    // avoid comparing NULL dates
    [self setOldestDate:[NSDate distantPast]];
    [self setNewestDate:[NSDate distantPast]];
    [self setNewestDateLoaded:[NSDate distantPast]];
    [self setLastOfflineError:[NSDate distantPast]];
    [self setLastNoNewDataError:[NSDate distantPast]];
    [self setNextClose:[NSDate distantPast]];
    
    countBars = 0;

    [self fetch];
}

// URL encode a string -- see http://forums.macrumors.com/showthread.php?t=689884 and http://simonwoodside.com/weblog/2009/4/22/how_to_really_url_encode/
- (NSString *)URLEncode:(NSString *)input {
    NSString *result = [input stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    return [result autorelease];
}

- (BOOL) shouldFetchIntradayQuote {
    
    CGFloat secondsSinceNow = [self.nextClose timeIntervalSinceNow];
        
    if (secondsSinceNow < 23000. && secondsSinceNow > -3600) {
        // current time in NYC is between 9:30am and 5pm of nextClose so only intraday data is available
        return YES;
    }
    return NO;
}

- (void) fetchIntradayQuote {

    if (self.loadingData) {
        return;
    } else if (self.lastOfflineError != NULL && [[NSDate date] timeIntervalSinceDate:self.lastOfflineError] < 60) {
        DLog(@"last offline error %@ was too recent to try again %f", self.lastOfflineError, [[NSDate date] timeIntervalSinceDate:self.lastOfflineError]);
        [self cancelDownload];
        return;
    }

    self.loadingData = YES;
    NSString *urlString = [NSString stringWithFormat:@"https://chartinsight.com/api/intraday/%@?token=%s",
                           [self URLEncode:self.symbol], API_KEY];
    
    NSURLSessionTask *task = [self.ephemeralSession
                              dataTaskWithURL:[NSURL URLWithString:urlString]
                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
    {
        if (error) {
            [self handleClientError:error];
        } else if (response && [response respondsToSelector:@selector(statusCode)]) {
            self.loadingData = NO;
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            if (statusCode == 404) {
                DLog(@"%@ error with %ld and %@", self.symbol, (long)statusCode, urlString);
                NSError *error = [NSError errorWithDomain:@"No new data" code:statusCode userInfo:nil];
                [self handleClientError:error];
                
            } else if (statusCode == 200 && data && data.length > 5) {
                NSError *jsonError = nil;
                NSDictionary *intradayQuote = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
                if (jsonError) {
                    [self handleClientError:jsonError];

                } else if (intradayQuote && [intradayQuote isKindOfClass:NSDictionary.class] && intradayQuote.count > 7) {
                    intradayBar.year = [intradayQuote[@"lastSaleYear"] integerValue];
                    intradayBar.month = [intradayQuote[@"lastSaleMonth"] integerValue];
                    intradayBar.day = [intradayQuote[@"lastSaleDay"] integerValue];
                    intradayBar.open = [intradayQuote[@"open"] doubleValue];
                    intradayBar.high = [intradayQuote[@"high"] doubleValue];
                    intradayBar.low = [intradayQuote[@"low"] doubleValue];
                    intradayBar.close = [intradayQuote[@"last"] doubleValue]; // Note last instead of close
                    intradayBar.volume = [intradayQuote[@"volume"] doubleValue];
                    intradayBar.adjClose = intradayBar.close;   // Only provided by historical API
                    intradayBar.splitRatio = 1.;
                    intradayBar.movingAvg1  = -1.;
                    intradayBar.movingAvg2  = -1.;
                    intradayBar.mbb         = -1.;
                    intradayBar.stdev       = -1.;
                    
                    double previousClose = [intradayQuote[@"prevClose"] doubleValue];

                    DLog(@" %ld %ld %ld %f %f %f %f", intradayBar.year, intradayBar.month, intradayBar.day, intradayBar.open, intradayBar.high, intradayBar.low, intradayBar.close);

                    NSDate *lastSaleDate = [self dateFromBar:intradayBar];
                    
                    if ([lastSaleDate compare:self.newestDateLoaded] == NSOrderedDescending) {
                        NSLog(@"lastSaleDate %@ > %@ newestDateLoaded", lastSaleDate, self.newestDateLoaded);
                        [self.delegate performSelector:@selector(APILoadedIntraday:) withObject:self];
                    } else if (fabs(cArray[0].close - previousClose) > 0.02) {
                        NSString *message = [NSString stringWithFormat:@"%@ previous close %f doesn't match %f", self.symbol, previousClose, cArray[0].close];
                        [self.delegate performSelector:@selector(APIFailed:) withObject:message];
                        // Intraday API uses IEX data and may not have newer
                    }
                }
            }
        }
    }];
    [task resume];
}

-(NSURL *) formatRequestURL {
    
    NSUInteger unitFlags = NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitYear;
    
 //   DLog(@"data api oldestDate %@ and requestNewestDate %@", requestOldestDate, requestNewestDate);
    
    if ([self.requestNewestDate timeIntervalSinceDate:self.requestOldestDate] < 0) {
        DLog(@"Invalid newest date %@ vs %@", self.requestNewestDate, self.requestOldestDate);
    }
    
    NSDateComponents *compsStart = [self.gregorian components:unitFlags fromDate:self.requestOldestDate];
    NSDateComponents *compsEnd = [self.gregorian components:unitFlags fromDate:self.requestNewestDate];

    NSString *url = [NSString stringWithFormat:@"https://chartinsight.com/api/ohlcv/%@", [self symbol]];
    
    url = [url stringByAppendingFormat:@"?startDate=%ld", [compsStart year]];
    url = [url stringByAppendingFormat:@"-%ld", [compsStart month]];
    url = [url stringByAppendingFormat:@"-%ld", [compsStart day]];

    url = [url stringByAppendingFormat:@"&endDate=%ld", [compsEnd year]];
    url = [url stringByAppendingFormat:@"-%ld", [compsEnd month]];
    url = [url stringByAppendingFormat:@"-%ld", [compsEnd day]];
    
    DLog(@"%@", url);
    url = [url stringByAppendingFormat:@"&token=%s", API_KEY];

    return [NSURL URLWithString:url];
}

-(void) historicalDataLoaded {
    if (countBars == 0) { // Server doesn't have newer data due to delayed fetch from source API
        [self.delegate performSelector:@selector(APILoadedHistoricalData:) withObject:self];
    }
    [self setOldestDate:[self dateFromBar:cArray[MAX(0,countBars-1)]]];
    
    [self setNewestDate:[self dateFromBar:cArray[0]]];

    if (self.oldestDate == NULL) {
        DLog(@"oldestdate is null after %ld bars added to %ld existing", barsFromDB, countBars);
        for (NSInteger i = 0; i < countBars; i++) {
           // DLog(@" datefromBar %d is %@", i, [self dateFromBar:cArray[i]]);
        }
    }
    
    if ([self.newestDate compare:self.newestDateLoaded] == NSOrderedDescending) {
        
        [self setNewestDateLoaded:self.newestDate];
        DLog(@"%@ newest date loaded is now %@", self.symbol, self.newestDateLoaded);
        
        [self setNextClose:[self getNextTradingDateAfterDate:self.newestDate]];
        if ([self shouldFetchIntradayQuote]) {
            [self fetchIntradayQuote];
        }
    }
    [self.delegate performSelector:@selector(APILoadedHistoricalData:) withObject:self];
}

- (NSInteger) dateIntFromBar:(BarStruct)bar {
    NSInteger result = bar.year * 10000;
    
    result += (bar.month * 100);
    result += bar.day;
        
 //  // DLog(@"dateIntFromBar is %d", result);
    return result;
}

/*
 The best and simplest algorithm for caching past data and then checking for gaps is to put a marker on the oldestbar row of each sequence.  Since we're using INSERT OR IGNORE, if the first row is within a larger sequence, it will be ignored (the real oldest of the sequence is older).
 
 Then, we can also run an update statement to clear out the 'first' bit on any existing rows in the sequence.
 
 We don't need an 'end' bit because each gap will have a first bit, and we can find the end of the sequence using a MAX prior to that value.
 
 This approach is that it allows the most multi-threading support.
 
 */
- (NSInteger) loadSavedRows {
    
    NSInteger i, newestDateInDB, iOldestRequested, iNewestRequested, retVal = 0, barsInDB = 0;
    NSInteger oldestDateInSeq = 0;        // will be oldest date cached in local db

    iNewestRequested = [self getIntegerFormatForDate:self.requestNewestDate];
    iOldestRequested = [self getIntegerFormatForDate:self.requestOldestDate];
    
    NSString *sqlOldest = [NSString stringWithFormat:@"SELECT MAX(CASE WHEN oldest = 1 THEN date ELSE 0 END), MAX(date), count(*) from history WHERE series = %ld AND date >= %ld AND date <= %ld", self.seriesId, iOldestRequested, iNewestRequested];

    sqlite3 *db;
    if (sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        return 0;
    }
    
    // sqlite can't tell us the number of rows in the query, so we have to run 2 queries
    
    sqlite3_stmt *statement;

    sqlite3_prepare_v2(db, [sqlOldest UTF8String], -1, &statement, NULL);
    sqlite3_step(statement);
                
    oldestDateInSeq = sqlite3_column_int(statement, 0);
    newestDateInDB = sqlite3_column_int(statement, 1);
    barsInDB = sqlite3_column_int(statement, 2);
    
    sqlite3_finalize(statement);
    
//    // DLog(@"oldestDateInSeq %d vs oldestRequested %d, newest date in DB = %d with bars %d", oldestDateInSeq, iOldestRequested, newestDateInDB, barsInDB);
        
    if (barsInDB == 0) {  // no bars found in DB
        sqlite3_close(db);
        return 0;          
    } else if (oldestDateInSeq > iOldestRequested) {   // missing older bars, so send new request to fill the gap
      //  DLog(@"oldestDateInSeq %d > oldestRequested %d", oldestDateInSeq, iOldestRequested);
        sqlite3_close(db);
        return 0;
    }
    // some or all of the reqest is available in sqlite
    
 //   DLog(@"barsInDB %d for request from %d to %d", barsInDB, iOldestRequested, iNewestRequested);
             
    retVal = sqlite3_prepare_v2(db, "SELECT SUBSTR(date,1,4), SUBSTR(date,5,2), SUBSTR(date,7,2), open, high, low, close, adjClose, volume from history where series = ? and date >= ? AND date <= ? ORDER BY date DESC", -1, &statement, NULL);
    
    if (retVal == SQLITE_OK) {
        sqlite3_bind_int64(statement, 1, self.seriesId);
        
        sqlite3_bind_int64(statement, 2, iOldestRequested);
        sqlite3_bind_int64(statement, 3, iNewestRequested);
        
        i = 0;
        
        while(sqlite3_step(statement) == SQLITE_ROW) {
            
            cArray[i].year = sqlite3_column_int(statement, 0);
            cArray[i].month = sqlite3_column_int(statement, 1);
            cArray[i].day = sqlite3_column_int(statement, 2);
            cArray[i].open = sqlite3_column_double(statement, 3);
            cArray[i].high = sqlite3_column_double(statement, 4);             
            cArray[i].low = sqlite3_column_double(statement, 5);
            cArray[i].close = sqlite3_column_double(statement, 6);
            cArray[i].adjClose = sqlite3_column_double(statement, 7);            
            cArray[i].volume = sqlite3_column_int64(statement, 8);
            cArray[i].movingAvg1 = -1.;
            cArray[i].movingAvg2 = -1.;
            cArray[i].mbb        = -1.;
            cArray[i].stdev      = -1.;
            
      //     // DLog(@"got row at %d %d-%d-%d %f %f %f %f %f",i, cArray[i].year, cArray[i].month,cArray[i].day, cArray[i].open, cArray[i].high, cArray[i].low, cArray[i].close, cArray[i].volume);
            
            i++;
        }
    } else {
       // DLog(@"DB error %s", sqlite3_errmsg(db));
    }
    
    sqlite3_finalize(statement);
    sqlite3_close(db);
    
   // DLog(@"after running checkSavedData, barsFromDB %d", barsInDB);
    
    if (barsInDB > 0) {
        return barsInDB;
    } 
    return 0;
}

-(void)fetch {
    if ( self.loadingData ) return;
    
    self->barsFromDB = 0;
    self->countBars = 0;
    
    __block NSInteger barsFound = 0;
  
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{
        barsFound = [self loadSavedRows];
    });
    
    DLog(@"%@ bars in db %ld", self.symbol, barsFound);
    
    self->barsFromDB = barsFound;
    
    if ( barsFromDB > 0 ) {     // no gap before, but maybe a gap afterwards
        
        countBars = barsFromDB;
            
        NSDate *newestDateSaved = [self dateFromBar:cArray[0]];
        NSDate *nextTradingDate = [self getNextTradingDateAfterDate:newestDateSaved];
        [self setNextClose:nextTradingDate];
        
        // DLog(@"next trading date after newest date saved is %@ vs newest date requested %@", nextTradingDate, self.requestNewestDate);
       
        if ([self.requestNewestDate timeIntervalSinceDate:nextTradingDate] >= 0.         // missing past trading date
            && [self.lastNoNewDataError timeIntervalSinceNow] < -60.
            && [nextTradingDate timeIntervalSinceDate:self.newestDateLoaded] > 0.) {     // after newest date loaded

            DLog(@"Missing bar %@ %f seconds after %@", nextTradingDate, [self.requestNewestDate timeIntervalSinceDate:newestDateSaved], newestDateSaved);
                        
            [self setRequestOldestDate:nextTradingDate];    // skip dates loaded from DB
        
        } else if ([self.lastOfflineError timeIntervalSinceNow] < -60.) {
            
            // DLog(@"%@ is close enough to %@", newestDateSaved, self.requestNewestDate);
            
            [self setOldestDate:[self dateFromBar:cArray[ barsFromDB - 1] ]];
            
            [self historicalDataLoaded];
            return;
        }
    }
    
    if (self.lastOfflineError != NULL && [[NSDate date] timeIntervalSinceDate:self.lastOfflineError] < 60) {
        DLog(@"last offline error %@ was too recent to try again %f", self.lastOfflineError, [[NSDate date] timeIntervalSinceDate:self.lastOfflineError]);
        [self cancelDownload];
        return;
    }
        
    self.loadingData = YES;
        
    NSURL *URL = [self formatRequestURL];
    NSURLSessionTask *task = [self.ephemeralSession dataTaskWithURL:URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
    {
        if (error) {
            [self handleClientError:error];
        } else if (response && [response respondsToSelector:@selector(statusCode)]) {
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            if (statusCode == 404) {
                DLog(@"%@ error with %ld and %@", self.symbol, (long)statusCode, URL);
                NSError *error = [NSError errorWithDomain:@"No new data" code:statusCode userInfo:nil];
                [self handleClientError:error];
                
            } else if (statusCode == 200 && data && data.length > 10) {
                self.loadingData = NO;
                
                NSString *csv = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                [self setCsvString:csv];
                [csv release];
                [self parseHistoricalCSV];
            }
        }
    }];
    [task resume];
}

-(void)handleClientError:(NSError *)error {
    
    DLog(@"%@ err = %@", self.symbol, [error localizedDescription]);

    self.loadingData = NO;
    
    if ([error code] == 404) {      // the connection is working but the requested quote data isn't available for some reason
        [self setLastNoNewDataError:[NSDate date]];
    } else {
        [self setLastOfflineError:[NSDate date]];
    }
    
    if (barsFromDB > 0) {   // use what we have
        
        DLog(@"%@ didFailWithError for request from %@ to %@", self.symbol, self.requestOldestDate, self.requestNewestDate);
         
        countBars = barsFromDB;

        [self historicalDataLoaded];
    }
    // [(StockData *)self.delegate APIFailed] calls performSelectorOnMainThread
    [self.delegate performSelector:@selector(APIFailed:) withObject:[error localizedDescription]];
}

// Parse stock data API and save it to the DB for faster access
-(void)parseHistoricalCSV {
    
    // https://chartinsight.com/api/ohlcv/AAPL
    // date,open,high,low,close,volume
    // 2009-01-02,2.6069,2.7635,2.5850,2.7547,746015946
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)-(\\d+)-(\\d+),([^,]+),([^,]+),([^,]+),([^,]+),(\\d+)"
                                                                           options:NSRegularExpressionAnchorsMatchLines error:nil];
    __block NSUInteger i = 0;
    __block NSUInteger barsFromWeb = [regex numberOfMatchesInString:self.csvString options:0 range:NSMakeRange(0, [self.csvString length])];
    
    //DLog(@"EOD response is %@", self.csvString);
    //DLog(@"barsFromWeb is %d vs %d barsFromDB", barsFromWeb, barsFromDB);
    
    if (barsFromWeb == 0) {         
        DLog(@"%@ empty response from API: %@", self.symbol, self.csvString);
        self.loadingData = NO;
        return [self historicalDataLoaded];  // countBars = zero indicates no new data available
    }
    
    NSInteger lastBar = barsFromDB + barsFromWeb - 1;

    BarStruct *webBars = cArray;

    if (barsFromDB > 0) {   // parse into separate memory in case of duplicate bars
        webBars = (BarStruct *)malloc(sizeof(BarStruct)*[self maxBars]);
    }
    
    // DLog(@"DB is now in %@", [NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()]);
    
    sqlite3 *db;
    if (sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL)) {
        return;
    }
    
    sqlite3_exec(db, "BEGIN", 0, 0, 0);
    
    sqlite3_stmt *statement;
    
    char *saveHistory = "INSERT OR IGNORE INTO history (series, date, open, high, low, close, adjClose, volume, oldest) values (?, ?, ?, ?, ?, ?, ?, ?, ?)";
    sqlite3_prepare_v2(db, saveHistory, -1, &statement, NULL);
   
    // Split CSV using regex (which won't match header "date,open,high,low,close,volume"
    NSArray *matches = [regex matchesInString:self.csvString  options:0 range:NSMakeRange(0, self.csvString.length)];

    for (NSTextCheckingResult *match in matches) {

        if (match && match.range.length < 7) {
            break;
        } else {
            webBars[i].year = [[self.csvString substringWithRange:[match rangeAtIndex:1]] integerValue];
            webBars[i].month = [[self.csvString substringWithRange:[match rangeAtIndex:2]] integerValue];
            webBars[i].day = [[self.csvString substringWithRange:[match rangeAtIndex:3]] integerValue];
            webBars[i].open = [[self.csvString substringWithRange:[match rangeAtIndex:4]] doubleValue];
            webBars[i].high = [[self.csvString substringWithRange:[match rangeAtIndex:5]] doubleValue];
            webBars[i].low = [[self.csvString substringWithRange:[match rangeAtIndex:6]] doubleValue];
            webBars[i].adjClose = [[self.csvString substringWithRange:[match rangeAtIndex:7]] doubleValue];
            webBars[i].close = [[self.csvString substringWithRange:[match rangeAtIndex:7]] doubleValue];
            webBars[i].volume = [[self.csvString substringWithRange:[match rangeAtIndex:8]] doubleValue];
            webBars[i].splitRatio = 1.;
            webBars[i].movingAvg1 = .0f;
            webBars[i].movingAvg2 = .0f;
        }
        
        //DLog(@"%@ %ld %ld %ld %ld %f %f %f %f %f %f", self.symbol, i, webBars[i].year, webBars[i].month, webBars[i].day, webBars[i].open, webBars[i].high, webBars[i].low, webBars[i].close, webBars[i].adjClose, webBars[i].volume);
        
        // Save data to DB for offline access
        if (i >= 0) { // often only the first bar with index = 0 needs to be saved to the DB
            sqlite3_bind_int64(statement, 1, self.seriesId);
            sqlite3_bind_int64(statement, 2, [self dateIntFromBar:webBars[i]]);        
            sqlite3_bind_text(statement, 3, [[self.csvString substringWithRange:[match rangeAtIndex:4]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 4, [[self.csvString substringWithRange:[match rangeAtIndex:5]] UTF8String], -1, SQLITE_TRANSIENT);            
            sqlite3_bind_text(statement, 5, [[self.csvString substringWithRange:[match rangeAtIndex:6]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 6, [[self.csvString substringWithRange:[match rangeAtIndex:7]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 7, [[self.csvString substringWithRange:[match rangeAtIndex:7]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(statement, 8, [[self.csvString substringWithRange:[match rangeAtIndex:8]] longLongValue]);
            
            if (i < lastBar) {
                sqlite3_bind_int64(statement, 9, 0);      // 0 = not oldest in sequence
            } else {
               // DLog(@"%@ lastBar %d start is %d-%d-%d", symbol, lastBar, webBars[__i].year, webBars[__i].month, webBars[__i].day);
                sqlite3_bind_int64(statement, 9, 1);      // 1 = oldest in sequence
            }
            
            if(sqlite3_step(statement) != SQLITE_DONE){;
               // DLog(@"Save to DB ERROR '%s'.", sqlite3_errmsg(db));
            }
            sqlite3_reset(statement);
        }

        i++;  
    }
    
    sqlite3_finalize(statement);
    sqlite3_exec(db, "COMMIT", 0, 0, 0);
    
    if (barsFromDB > 0) {
       // DLog(@"%@ copying %d older barsFromDB to end of %d barsFromWeb", symbol, barsFromDB, barsFromWeb);
        
        memcpy(&webBars[barsFromWeb], cArray, barsFromDB * sizeof(BarStruct));
        free(cArray);
        cArray = webBars;
    }

    NSInteger sqlnewestDate;
    
    if ([self.newestDateLoaded compare:[NSDate distantPast]] == NSOrderedDescending) {
        sqlnewestDate = [self getIntegerFormatForDate:self.newestDateLoaded];
    } else {
        sqlnewestDate = [self dateIntFromBar:cArray[0]];
    }
    
    NSInteger sqloldestDate = [self dateIntFromBar:cArray[lastBar]];
        
    // now update any existing bars beween 0 and blockOffset-1 that have start = 1
    if (sqlite3_prepare_v2(db, "UPDATE history SET oldest = 0 WHERE series = ? AND date > ? AND date <= ?", -1, &statement, NULL) == SQLITE_OK) {
        
        sqlite3_bind_int64(statement, 1, self.seriesId);
        sqlite3_bind_int64(statement, 2, sqloldestDate);
        sqlite3_bind_int64(statement, 3, sqlnewestDate);
    
        if(sqlite3_step(statement)==SQLITE_DONE){;
           // DLog(@"cleared oldest from dates > %d and <= %d", sqloldestDate, sqlnewestDate);
        } else {
           // DLog(@"%@ DB ERROR '%s'.", symbol, sqlite3_errmsg(db));
        }
        sqlite3_reset(statement);
        
    }
    sqlite3_finalize(statement);
    sqlite3_close(db);
    
    countBars = barsFromDB + barsFromWeb;
    
    [self historicalDataLoaded];
}

// called after 1000 bars are deleted
- (void) adjustNewestDateLoadedTo:(NSDate *)adjustedDate {
    [self setNewestDateLoaded:adjustedDate];
    [self setNextClose:[self getNextTradingDateAfterDate:self.newestDateLoaded]];
}


@end
