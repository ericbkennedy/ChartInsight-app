#import "CIAppDelegate.h"
#import "DataAPI.h"
#import "sqlite3.h"

const char *API_KEY = "placeholderToken";

@interface DataAPI ()
@property (nonatomic, strong) NSMutableArray<BarData *> *fetchedData;
@property (nonatomic) NSInteger barsFromDB;
@property (nonatomic, copy) NSString *csvString;
@property (strong, nonatomic) NSURLSession *ephemeralSession;   // skip web cache since sqlite caches price data
@property (nonatomic, assign) BOOL loadingData;
@property (strong, nonatomic) NSDate *lastIntradayFetch;
@property (strong, nonatomic) NSDate *lastOfflineError;
@property (strong, nonatomic) NSDate *lastNoNewDataError;       // set when a 404 occurs on a request for newer data
@property (strong, nonatomic) NSDate *newestDateLoaded;         // rule out newer gaps by tracking the newest date loaded
@end

@implementation DataAPI

- (instancetype)init {
    self = [super init];
    
    self.fetchedData = [NSMutableArray array];
    self.intradayBar = [[BarData alloc] init];
    self.lastIntradayFetch = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
    
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
    _csvString = nil;    // don't release it because the setter manages release count
    _symbol = nil;
    _oldestDate = nil;
    _newestDateLoaded = nil;
    [super dealloc];
}

- (NSDate *) dateFromBar:(BarData *)bar {

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

// StockData will call this with the currentNewest date if self.nextClose is today or in the past.
// tracking nextClose handles holidays, weekends, and when a user resumes using the app after inactivity
- (void) fetchNewerThanDate:(NSDate *)currentNewest {
     
    [self setRequestOldestDate:[self getNextTradingDateAfterDate:currentNewest]];
    
    [self setRequestNewestDate:[NSDate date]];
     
    DLog(@"requesting from %@ to %@", self.requestOldestDate, self.requestNewestDate);

    [self fetch];
}

- (void) fetchInitialData {

    [self setRequestNewestDate:[NSDate date]];

    // avoid comparing NULL dates
    [self setOldestDate:[NSDate distantPast]];
    [self setNewestDate:[NSDate distantPast]];
    [self setNewestDateLoaded:[NSDate distantPast]];
    [self setLastOfflineError:[NSDate distantPast]];
    [self setLastNoNewDataError:[NSDate distantPast]];
    [self setNextClose:[NSDate distantPast]];
    
    self.countBars = 0;

    [self fetch];
}

- (BOOL) shouldFetchIntradayQuote {
    
    CGFloat secondsSinceNow = [self.nextClose timeIntervalSinceNow];    
    CGFloat secondsSinceLastFetch = [self.lastIntradayFetch timeIntervalSinceNow];

    if (secondsSinceLastFetch < -60 && secondsSinceNow < 23000. && secondsSinceNow > -3600) {
        // current time in NYC is between 9:30am and 5pm of nextClose so only intraday data is available
        DLog(@"temporarily returning NO");
        return NO;
        
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
                           self.symbol, API_KEY];
    
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
                    _intradayBar.year = [intradayQuote[@"lastSaleYear"] integerValue];
                    _intradayBar.month = [intradayQuote[@"lastSaleMonth"] integerValue];
                    _intradayBar.day = [intradayQuote[@"lastSaleDay"] integerValue];
                    _intradayBar.open = [intradayQuote[@"open"] doubleValue];
                    _intradayBar.high = [intradayQuote[@"high"] doubleValue];
                    _intradayBar.low = [intradayQuote[@"low"] doubleValue];
                    _intradayBar.close = [intradayQuote[@"last"] doubleValue]; // Note last instead of close
                    _intradayBar.volume = [intradayQuote[@"volume"] doubleValue];
                    _intradayBar.adjClose = _intradayBar.close;   // Only provided by historical API
                    _intradayBar.splitRatio = 1.;
                    _intradayBar.movingAvg1  = -1.;
                    _intradayBar.movingAvg2  = -1.;
                    _intradayBar.mbb         = -1.;
                    _intradayBar.stdev       = -1.;
                    
                    double previousClose = [intradayQuote[@"prevClose"] doubleValue];

                    DLog(@" %ld %ld %ld %f %f %f %f", _intradayBar.year, _intradayBar.month, _intradayBar.day, _intradayBar.open, _intradayBar.high, _intradayBar.low, _intradayBar.close);

                    NSDate *lastSaleDate = [self dateFromBar:_intradayBar];
                    
                    if ([lastSaleDate compare:self.newestDateLoaded] == NSOrderedDescending) {
                        NSLog(@"lastSaleDate %@ > %@ newestDateLoaded", lastSaleDate, self.newestDateLoaded);
                        [self.delegate performSelector:@selector(APILoadedIntradayBar:) withObject:_intradayBar];
                        self.lastIntradayFetch = [NSDate date];
                    } else if (fabs(self.fetchedData[0].close - previousClose) > 0.02) {
                        NSString *message = [NSString stringWithFormat:@"%@ previous close %f doesn't match %f", self.symbol, previousClose, self.fetchedData[0].close];
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

-(void) historicalDataLoaded:(nullable NSArray<BarData *> *)barData {
    
    if (barData == nil || barData.count == 0) { // Server doesn't have newer data due to delayed fetch from source API
        
        [self.delegate performSelector:@selector(APILoadedHistoricalData:) withObject:barData];
    }
    [self setOldestDate:[self dateFromBar:self.fetchedData[MAX(0, self.countBars-1)]]];
    
    [self setNewestDate:[self dateFromBar:self.fetchedData[0]]];

    if (self.oldestDate == NULL) {
        DLog(@"oldestdate is null after %ld bars added to %ld existing", self.barsFromDB, self.countBars);
        for (NSInteger i = 0; i < self.countBars; i++) {
            DLog(@" datefromBar %ld is %@", i, [self dateFromBar:self.fetchedData[i]]);
        }
    }
    
    if ([self.newestDate compare:self.newestDateLoaded] == NSOrderedDescending) {
        
        [self setNewestDateLoaded:self.newestDate];
        DLog(@"%@ newestDateLoaded= %ld, oldestDate= %ld", self.symbol,
                                                        [self getIntegerFormatForDate:self.newestDateLoaded],
                                                         [self getIntegerFormatForDate:self.oldestDate]);
        
        [self setNextClose:[self getNextTradingDateAfterDate:self.newestDate]];
        if ([self shouldFetchIntradayQuote]) {
            [self fetchIntradayQuote];
        }
    }
    [self.delegate performSelector:@selector(APILoadedHistoricalData:) withObject:self.fetchedData];
}

- (NSInteger) loadSavedRows {
    
    DLog(@"oldestDateRequested = %@", self.requestOldestDate);
    
    NSInteger retVal = 0, barsInDB = 0;

    sqlite3 *db;
    if (sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        return 0;
    }
    
    sqlite3_stmt *statement;
    retVal = sqlite3_prepare_v2(db, "SELECT SUBSTR(date,1,4), SUBSTR(date,5,2), SUBSTR(date,7,2), open, high, low, close, adjClose, volume from history WHERE stockId=? and date >= ? ORDER BY date DESC",
                                -1, &statement, NULL);
    
    if (retVal == SQLITE_OK) {
        sqlite3_bind_int64(statement, 1, self.stockId);
        sqlite3_bind_int64(statement, 2, [self getIntegerFormatForDate:self.requestOldestDate]);
        
        while(sqlite3_step(statement) == SQLITE_ROW) {
            BarData *newBar = [[BarData alloc] init];
            newBar.year = sqlite3_column_int(statement, 0);
            newBar.month = sqlite3_column_int(statement, 1);
            newBar.day = sqlite3_column_int(statement, 2);
            newBar.open = sqlite3_column_double(statement, 3);
            newBar.high = sqlite3_column_double(statement, 4);
            newBar.low = sqlite3_column_double(statement, 5);
            newBar.close = sqlite3_column_double(statement, 6);
            newBar.adjClose = sqlite3_column_double(statement, 7);
            newBar.volume = sqlite3_column_int64(statement, 8);
            newBar.movingAvg1 = -1.;
            newBar.movingAvg2 = -1.;
            newBar.mbb        = -1.;
            newBar.stdev      = -1.;
            [self.fetchedData addObject:newBar]; // DB load is date DESC for easier array appending
            barsInDB += 1;
        }
    } else {
       // DLog(@"DB error %s", sqlite3_errmsg(db));
    }
    
    sqlite3_finalize(statement);
    sqlite3_close(db);
    
   // DLog(@"after running checkSavedData, barsFromDB %d", self.barsFromDB);
    
    if (barsInDB > 0) {
        return barsInDB;
    } 
    return 0;
}

-(void)fetch {
    if ( self.loadingData ) return;
    
    self.barsFromDB = 0;
    self.countBars = 0;
    [self.fetchedData removeAllObjects];
    
    __block NSInteger barsFound = 0;
  
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{
        barsFound = [self loadSavedRows];
    });
    
    DLog(@"%@ bars in db %ld", self.symbol, barsFound);
    
    self.barsFromDB = barsFound;
    
    if (self.barsFromDB > 0 ) {     // no gap before, but maybe a gap afterwards
        
        self.countBars = self.barsFromDB;
            
        NSDate *newestDateSaved = [self dateFromBar:self.fetchedData[0]];
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
            
            [self setOldestDate:[self dateFromBar:self.fetchedData[ self.barsFromDB - 1] ]];
            
            [self historicalDataLoaded:nil];
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
    
    if (self.barsFromDB > 0) {   // use what we have
        
        DLog(@"%@ didFailWithError for request from %@ to %@", self.symbol, self.requestOldestDate, self.requestNewestDate);
         
        self.countBars = self.barsFromDB;

        [self cancelDownload];
    }
    // [(StockData *)self.delegate APIFailed] calls performSelectorOnMainThread
    [self.delegate performSelector:@selector(APIFailed:) withObject:[error localizedDescription]];
}

// Parse stock data API and save it to the DB for faster access
-(void)parseHistoricalCSV {
    
    // https://chartinsight.com/api/ohlcv/AAPL?startDate=2010-01-01&endDate=2023-06-13
    // date,open,high,low,close,volume
    // 2023-06-13,182.8000,184.1500,182.4400,183.3100,54648141
    // 2023-06-12,181.2700,183.8900,180.9700,183.7900,53563704
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)-(\\d+)-(\\d+),([^,]+),([^,]+),([^,]+),([^,]+),(\\d+)"
                                                                           options:NSRegularExpressionAnchorsMatchLines error:nil];
    __block NSUInteger barsFromWeb = [regex numberOfMatchesInString:self.csvString options:0 range:NSMakeRange(0, [self.csvString length])];
    
    //DLog(@"EOD response is %@", self.csvString);
    //DLog(@"barsFromWeb is %d vs %d barsFromDB", barsFromWeb, barsFromDB);
    
    if (barsFromWeb == 0) {         
        DLog(@"%@ empty response from API but barsFromDB=%ld %@ ", self.symbol, self.barsFromDB, self.csvString);
        self.loadingData = NO;
        if (self.barsFromDB > 0) {
            [self historicalDataLoaded:self.fetchedData];   // send bars from DB
        } else {
            [self cancelDownload]; // nothing new fetched this time
        }
        return;
    }

    sqlite3 *db;
    if (sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL)) {
        return;
    }
    
    sqlite3_exec(db, "BEGIN", 0, 0, 0);
    
    sqlite3_stmt *statement;
    
    char *saveHistory = "INSERT OR IGNORE INTO history (stockId, date, open, high, low, close, adjClose, volume) values (?, ?, ?, ?, ?, ?, ?, ?)";
    sqlite3_prepare_v2(db, saveHistory, -1, &statement, NULL);
   
    // Split CSV using regex (which won't match header "date,open,high,low,close,volume"
    NSArray *matches = [regex matchesInString:self.csvString  options:0 range:NSMakeRange(0, self.csvString.length)];

    for (NSTextCheckingResult *match in matches) {
        BarData *newBar = [[BarData alloc] init];
        if (match && match.range.length < 7) {
            break;
        } else {
            newBar.year = [[self.csvString substringWithRange:[match rangeAtIndex:1]] integerValue];
            newBar.month = [[self.csvString substringWithRange:[match rangeAtIndex:2]] integerValue];
            newBar.day = [[self.csvString substringWithRange:[match rangeAtIndex:3]] integerValue];
            newBar.open = [[self.csvString substringWithRange:[match rangeAtIndex:4]] doubleValue];
            newBar.high = [[self.csvString substringWithRange:[match rangeAtIndex:5]] doubleValue];
            newBar.low = [[self.csvString substringWithRange:[match rangeAtIndex:6]] doubleValue];
            newBar.adjClose = [[self.csvString substringWithRange:[match rangeAtIndex:7]] doubleValue];
            newBar.close = [[self.csvString substringWithRange:[match rangeAtIndex:7]] doubleValue];
            newBar.volume = [[self.csvString substringWithRange:[match rangeAtIndex:8]] doubleValue];
            newBar.splitRatio = 1.;
            newBar.movingAvg1 = .0f;
            newBar.movingAvg2 = .0f;
            [self.fetchedData addObject:newBar];
        }
        
        // DLog(@"%@ csv %ld %ld %ld %f", self.symbol, newBar.year, newBar.month, newBar.day, newBar.close);
        
        // Save data to DB for offline access
            sqlite3_bind_int64(statement, 1, self.stockId);
            sqlite3_bind_int64(statement, 2, newBar.dateIntFromBar);
            sqlite3_bind_text(statement, 3, [[self.csvString substringWithRange:[match rangeAtIndex:4]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 4, [[self.csvString substringWithRange:[match rangeAtIndex:5]] UTF8String], -1, SQLITE_TRANSIENT);            
            sqlite3_bind_text(statement, 5, [[self.csvString substringWithRange:[match rangeAtIndex:6]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 6, [[self.csvString substringWithRange:[match rangeAtIndex:7]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 7, [[self.csvString substringWithRange:[match rangeAtIndex:7]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(statement, 8, [[self.csvString substringWithRange:[match rangeAtIndex:8]] longLongValue]);
            
            if(sqlite3_step(statement) != SQLITE_DONE){;
                DLog(@"Save to DB ERROR '%s'.", sqlite3_errmsg(db));
            }
            sqlite3_reset(statement);
    }
    
    sqlite3_finalize(statement);
    sqlite3_exec(db, "COMMIT", 0, 0, 0);
    
    NSInteger sqlnewestDate;
    
    if ([self.newestDateLoaded compare:[NSDate distantPast]] == NSOrderedDescending) {
        sqlnewestDate = [self getIntegerFormatForDate:self.newestDateLoaded];
    } else {
        sqlnewestDate = self.fetchedData[0].dateIntFromBar;
    }
    
    sqlite3_close(db);
    
    self.countBars = self.barsFromDB + barsFromWeb;
    
    [self historicalDataLoaded:self.fetchedData];
}

// called after 1000 bars are deleted
- (void) adjustNewestDateLoadedTo:(NSDate *)adjustedDate {
    [self setNewestDateLoaded:adjustedDate];
    [self setNextClose:[self getNextTradingDateAfterDate:self.newestDateLoaded]];
}


@end
