#import "CIAppDelegate.h"
#import "DataAPI.h"
#import "sqlite3.h"

#define REQUEST_BARS 260    // Shanghai index in 2005

// saveHistory is used twice so leave this here
const char *saveHistory = "INSERT OR IGNORE INTO history (series, date, open, high, low, close, adjClose, volume, oldest) values (?, ?, ?, ?, ?, ?, ?, ?, ?)";

@implementation NSDate (DataAPI)

- (NSInteger) formatDate:(NSCalendar *)calendar {
    assert(self != nil);
    
    NSUInteger unitFlags = NSMonthCalendarUnit | NSDayCalendarUnit | NSYearCalendarUnit;
    NSDateComponents *dateParts = [calendar components:unitFlags fromDate:self];
    
    return ([dateParts year] * 10000 + ([dateParts month]*100) + [dateParts day]);
}

- (BOOL) isHoliday:(NSCalendar *)calendar {
    
    NSInteger dateInt = [self formatDate:calendar];
    
    switch (dateInt) {  // https://www.nyse.com/markets/hours-calendars
        case 20160215:
        case 20160325:
        case 20160530:
        case 20160704:
        case 20160905:
        case 20161124:
        case 20161226:
        case 20170102:
        case 20170116:
        case 20170220:
        case 20170414:
        case 20170529:
        case 20170704:
        case 20170904:
        case 20171123:
        case 20171225:
           // DLog(@" cur date %d is a holiday", dateInt);
            return YES;
    }
    return NO;
}

- (NSDate *) nextTradingDate:(NSCalendar *)calendar {
    
    NSDate *nextTradingDate = [self copy];    
    NSDateComponents *days = [[NSDateComponents alloc] init];
    
    [days setDay:1];
    
    do {
        nextTradingDate = [calendar dateByAddingComponents:days toDate:nextTradingDate options:0]; // add another day
        //     // DLog(@"new date is %@", nextTradingDate);
        
    } while ([nextTradingDate isHoliday:calendar]
             || 1 == [[calendar components:NSWeekdayCalendarUnit fromDate:nextTradingDate] weekday]           // Sunday
             || 7 == [[calendar components:NSWeekdayCalendarUnit fromDate:nextTradingDate] weekday]);    // Saturday
             
   // DLog(@"next trading date is %@ from %@", nextTradingDate, self);
    [days release];

    return nextTradingDate;    
}

- (BOOL) isTodayIntraday {
    CGFloat secondsSinceNow = [self timeIntervalSinceNow];
    
//    // DLog(@"secondsSinceNow %f for %@", secondsSinceNow, self);
    
    if (secondsSinceNow < 27000. && secondsSinceNow > -22500.) { // date is today after 6:30am and before 6pm 
        return YES;
    }
    return NO;
}

- (BOOL) nextTradingDateIsToday:(NSCalendar *)calendar {
    CGFloat secondsBeforeNextTradingDate = [[self nextTradingDate:calendar] timeIntervalSinceDate:[NSDate date]];
   // DLog(@"secondsBeforeNextTradingDate =%f", secondsBeforeNextTradingDate);
    
    if (secondsBeforeNextTradingDate > -86401.0f) {
       // DLog(@"next trading date is at least a day ago");
        if (secondsBeforeNextTradingDate < 16000.0f)
            return YES;
    }
    return NO;
}
@end

@interface DataAPI () {
@private
    NSInteger barsFromDB;
    NSInteger oldestDateInSeq;        // lets us resubmit shorter request if internet is down
}

@property (nonatomic, copy) NSString *csvString;
@property (strong, nonatomic) NSMutableData *receivedData;
@property (strong, nonatomic) NSURLConnection *connection;
@property (nonatomic, assign) BOOL loadingData;
@property (strong, nonatomic) NSDate *lastOfflineError;
@property (strong, nonatomic) NSDate *lastNoNewDataError;       // set when a 404 occurs on a request for newer data
@property (strong, nonatomic) NSDate *newestDateLoaded;         // rule out newer gaps by tracking the newest date loaded

-(void)fetch;
-(NSURL *) formatRequestURL;
-(void)historicalDataLoadedWithIntraday:(BOOL)includesIntraday;
-(void)parseHistoricalCSV;

@end

@implementation DataAPI

- (NSInteger) maxBars {
    return 16000;    // SPX back to 1950, which is the oldest now that the DJIA isn't available through Yahoo.  I have 9 months before it exceeds this (15809 in 10/28)
}

-(id) init {
    self = [super init];
    
    // NOTE: this should really be the max that we would request at any one time, since stockData.barData is separate memory
    cArray = (BarStruct *)malloc(sizeof(BarStruct)*[self maxBars]);
    
    return self;
}

-(void)dealloc {
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

    NSString *dateString = [NSString stringWithFormat:@"%d%02d%02dT20:00:00Z", bar.year, bar.month, bar.day];// 10am NYC first quote
        
    return [[(CIAppDelegate *)[[UIApplication sharedApplication] delegate] dateFormatter] dateFromString:dateString];  
}

-(void)cancelDownload {
    if (self.loadingData) {
        [self.connection cancel];
        self.loadingData = NO;
        
        self.receivedData = nil;
        self.connection = nil;
    }
    [self.delegate performSelector:@selector(APICanceled:) withObject:self];
}

// tracking nextClose handles holidays, weekends, and when a user resumes using the app after inactivity
// but should only apply for NEWER dates, not when they scroll to the past

- (void) getNewerThanDate:(NSDate *)currentNewest screenBarWidth:(NSInteger)screenBarWidth {
     
    [self setRequestOldestDate:[currentNewest nextTradingDate:self.gregorian]];
    
    // sets earlier of today or 1 year after oldest date
    [self setRequestNewestDate:[[NSDate date] earlierDate:[self.requestOldestDate dateByAddingTimeInterval:MAX(365, screenBarWidth)*86400]]];
     
   // DLog(@"requesting from %@ to %@", requestOldestDate, requestNewestDate);

    [self fetch];
}

- (void) getOlderDataFrom:(NSDate *)requestStart untilDate:(NSDate *)currentOldest {
    countBars = 0;
    
    [self setRequestNewestDate:[currentOldest dateByAddingTimeInterval:-86400]];   // avoid overlap
    
    [self setRequestOldestDate:requestStart]; 
    
   // DLog(@"%@ getOlderDates from %@ to %@", symbol, requestOldestDate, requestNewestDate);
    
    [self fetch];   
}

- (void) getInitialData {

    // prefetch by a year for older requests
    [self setRequestNewestDate:[[NSDate date] earlierDate:[self.requestNewestDate dateByAddingTimeInterval:365*86400]]];

   // DLog(@"getDAta from %@ to %@", self.requestOldestDate, self.requestNewestDate);

    // avoid comparing NULL dates
    [self setOldestDate:[NSDate distantPast]];
    [self setNewestDate:[NSDate distantPast]];
    [self setNewestDateLoaded:[NSDate distantPast]];
    [self setLastOfflineError:[NSDate distantPast]];
    [self setLastNoNewDataError:[NSDate distantPast]];
    [self setNextClose:[NSDate distantPast]];
    
    intraday = NO;
    countBars = 0;

    [self fetch];
}

// URL encode a string -- see http://forums.macrumors.com/showthread.php?t=689884 and http://simonwoodside.com/weblog/2009/4/22/how_to_really_url_encode/
- (NSString *)URLEncode:(NSString *)string {
    NSString *result = (NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)string, NULL, CFSTR("% '\"?=&+<>;:-"), kCFStringEncodingUTF8);
    
    return [result autorelease];
}

- (void)getIntradayQuote {
  
    if (self.loadingData) {
        return;
    }
    self.loadingData = YES;
    intraday = YES;
    
    // http://www.gummy-stuff.org/Yahoo-data.htm
    
    NSString *urlString = [NSString stringWithFormat:@"http://download.finance.yahoo.com/d/quotes.csv?s=%@&f=spd1t1ohgl1v", [self URLEncode:self.symbol]];
    
    NSURL *url = [NSURL URLWithString:urlString];
    // DLog(@"intraday url encoded is %@", url);
    NSURLRequest *theRequest=[NSURLRequest requestWithURL:url
                                              cachePolicy:NSURLRequestReloadIgnoringCacheData
                                          timeoutInterval:60.0];
    
    // create the connection with the request
    // and start loading the data
    self.connection = [NSURLConnection connectionWithRequest:theRequest delegate:self];
    if (self.connection) {
        self.receivedData = [[NSMutableData alloc] init];       // initialize it
    } 
    else {
        // DLog(@"connection couldn't be started");
        //TODO: Inform the user that the download could not be started
        self.loadingData = NO;
    }
}


-(NSURL *) formatRequestURL {
    
    NSUInteger unitFlags = NSMonthCalendarUnit | NSDayCalendarUnit | NSYearCalendarUnit;
    
 //   DLog(@"data api oldestDate %@ and requestNewestDate %@", requestOldestDate, requestNewestDate);
    
    if ([self.requestNewestDate timeIntervalSinceDate:self.requestOldestDate] < 0) {
     //   DLog(@"Invalid newest date %@ vs %@", requestNewestDate, requestOldestDate);
    }
    
    NSDateComponents *compsStart = [self.gregorian components:unitFlags fromDate:self.requestOldestDate];
    NSDateComponents *compsEnd = [self.gregorian components:unitFlags fromDate:self.requestNewestDate];
    
   // DLog(@"comps year is %d and %d", [compsStart year], [compsEnd year]);
    
    NSString *url = [NSString stringWithFormat:@"http://ichart.finance.yahoo.com/table.csv?s=%@&", [self symbol]];
    url = [url stringByAppendingFormat:@"a=%ld&", [compsStart month]-1];
    url = [url stringByAppendingFormat:@"b=%ld&", [compsStart day]];
    url = [url stringByAppendingFormat:@"c=%ld&", [compsStart year]];
    
    url = [url stringByAppendingFormat:@"d=%ld&", [compsEnd month]-1];
    url = [url stringByAppendingFormat:@"e=%ld&", [compsEnd day]];
    url = [url stringByAppendingFormat:@"f=%ld&", [compsEnd year]];
    url = [url stringByAppendingString:@"g=d&"];
    
    url = [url stringByAppendingString:@"ignore=.csv"];
    
    return [NSURL URLWithString:url];
}

-(void) historicalDataLoadedWithIntraday:(BOOL)includesIntraday {
    
    [self setOldestDate:[self dateFromBar:cArray[MAX(0,countBars-1)]]];
    
    [self setNewestDate:[self dateFromBar:cArray[0]]];
    
   // DLog(@"notify pulled data has oldestDate = %@ at %d", oldestDate, countBars - 1);

    if (self.oldestDate == NULL) {
        DLog(@"oldestdate is null after %ld bars added to %ld existing", barsFromDB, countBars);
        for (NSInteger i = 0; i < countBars; i++) {
           // DLog(@" datefromBar %d is %@", i, [self dateFromBar:cArray[i]]);
        }
    }
    
    if ([self.newestDate compare:self.newestDateLoaded] == NSOrderedDescending) {
        
        [self setNewestDateLoaded:self.newestDate];
        DLog(@"%@ newest date loaded is now %@", self.symbol, self.newestDateLoaded);
        
        if (includesIntraday) {
            [self setNextClose:self.newestDate];
           // DLog(@"because historical response includes intraday, nextClose is %@", nextClose);
        } else {
            [self setNextClose:[self.newestDate nextTradingDate:self.gregorian]];
            if ([self.nextClose isTodayIntraday]) {
               // DLog(@"still need intraday data");
                [self getIntradayQuote];
            }
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
    oldestDateInSeq = 0;

    iNewestRequested = [self.requestNewestDate formatDate:self.gregorian];
    iOldestRequested = [self.requestOldestDate formatDate:self.gregorian];
    
    NSString *sqlOldest = [NSString stringWithFormat:@"SELECT MAX(CASE WHEN oldest = 1 THEN date ELSE 0 END), MAX(date), count(*) from history WHERE series = %ld AND date >= %ld AND date <= %ld", self.seriesId, iOldestRequested, iNewestRequested];
 
   // DLog(@"sql is %@", sqlOldest);
    
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
            cArray[i].splitRatio = 1.;
            cArray[i].movingAvg1 = -1.;
            cArray[i].movingAvg2 = -1.;
            cArray[i].rsi        = -1.;
            cArray[i].mbb        = -1.;
            cArray[i].stdev        = -1.;
            
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
    
 //   DLog(@"bars in db %d", barsFound);
    
    self->barsFromDB = barsFound;
    
    if ( barsFromDB > 0 ) {     // no gap before, but maybe a gap afterwards
        
        countBars = barsFromDB;  
            
        NSDate *newestDateSaved = [self dateFromBar:cArray[0]];
        NSDate *nextTradingDate = [newestDateSaved nextTradingDate:self.gregorian];
        
        DLog(@"next trading date after newest date saved is %@ vs newest date requested %@", nextTradingDate,           self.requestNewestDate);
            
        // only contact Yahoo if the nextTradingDate is in the past (so historical bars are available) AND is newer than the newestDateLoaded
        // nextTrading date must be earlier than newestRequested loaded and also now
       
        if ([nextTradingDate isTodayIntraday] == NO
            && [self.requestNewestDate timeIntervalSinceDate:nextTradingDate] >= 0.         // missing past trading date
            && [self.lastNoNewDataError timeIntervalSinceNow] < -60.
            && [nextTradingDate timeIntervalSinceDate:self.newestDateLoaded] > 0.) {     // after newest date loaded

             DLog(@"Missing bar %@ %f seconds after %@", nextTradingDate, [self.requestNewestDate timeIntervalSinceDate:newestDateSaved], newestDateSaved);
                        
            [self setRequestOldestDate:nextTradingDate];    // skip dates loaded from DB
        
        } else if ([self.lastOfflineError timeIntervalSinceNow] < -60.) {
            
            DLog(@"%@ is close enough to %@", newestDateSaved, self.requestNewestDate);
            
            [self setOldestDate:[self dateFromBar:cArray[ barsFromDB - 1] ]];
            DLog(@"oldestDate is %@ ", self.oldestDate);
            
            [self historicalDataLoadedWithIntraday:NO];
            return;
        }
    }
    
    if (self.lastOfflineError != NULL && [[NSDate date] timeIntervalSinceDate:self.lastOfflineError] < 60) {
         DLog(@"last offline error %@ was too recent to try again %f", self.lastOfflineError, [[NSDate date] timeIntervalSinceDate:self.lastOfflineError]);
        [self cancelDownload];
        return;
    }
        
    self.loadingData = YES;
    NSURLRequest *request = [NSURLRequest requestWithURL:[self formatRequestURL]
                                                  cachePolicy:NSURLRequestReloadIgnoringCacheData
                                              timeoutInterval:60.0];
        
    self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
    if (self.connection) {
        self.receivedData = [[NSMutableData alloc] init];       // initialize it
    } else {
        //TODO: Inform the user that the download could not be started
        self.loadingData = NO;
    }
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    // append the new data to the receivedData
  // // DLog(@"%@ did receive data", symbol);
    [self.receivedData appendData:data];
}

-(void)connection:(NSURLConnection *)failedConnection didFailWithError:(NSError *)error {
    
    DLog(@"%@ err = %@ for connection %@", self.symbol, [error localizedDescription], [failedConnection description]);

    self.loadingData = NO;
    [self.connection cancel];
    self.receivedData = nil;
    self.connection = nil;
    
    if ([error code] == 404) {      // the connection is working but the requested quote data isn't available for some reason
        [self setLastNoNewDataError:[NSDate date]];
    } else {
        [self setLastOfflineError:[NSDate date]];
    }
    
    if (!intraday && barsFromDB > 0) {   // use what we have
        
        // DLog(@"%@ didFailWithError for request from %@ to %@", self.symbol, self.requestOldestDate, self.requestNewestDate);
         
        countBars = barsFromDB;

        [self historicalDataLoadedWithIntraday:NO];
        
    } else {
        
        if (!intraday && oldestDateInSeq > 0) {  // DB has some dates, so resubmit shorter request and use those
        
            NSDate *oldestDateInDB = [[(CIAppDelegate *)[[UIApplication sharedApplication] delegate] dateFormatter] 
                                        dateFromString:[NSString stringWithFormat:@"%dT20:00:00Z", oldestDateInSeq]];
            
           // DLog(@"%@ after internet failure, oldest is %@ from NSInteger %d", symbol, oldestDateInDB, oldestDateInSeq);
            
            if ([oldestDateInDB compare:self.requestNewestDate] == NSOrderedAscending) {
                [self setRequestOldestDate:oldestDateInDB];
    
                if ((barsFromDB = [self loadSavedRows]) > 0) {
                    countBars = barsFromDB;
                    [self historicalDataLoadedWithIntraday:NO];
                    return;
                }
            }
        }
    }
    [self.delegate performSelector:@selector(APIFailed:) withObject:[error localizedDescription]];
}

// disable caching since sqlite does our caching
- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    return nil;
}

-(void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)response {
    // this method is called when the server has determined that it
    // has enough information to create the NSURLResponse
    // it can be called multiple times, for example in the case of a
    // redirect, so each time we reset the data.
      DLog(@"%@ did receive response", self.symbol);
    
    if ([response respondsToSelector:@selector(statusCode)])  {
        NSInteger statusCode = [((NSHTTPURLResponse *)response) statusCode];
        if (statusCode == 404) {
            
             DLog(@"%@ error with %ld and %@", self.symbol, (long)statusCode, c.originalRequest.URL);
            [c cancel];  // stop connecting; no more delegate messages
            [self connection:c didFailWithError:[NSError errorWithDomain:@"No new data" code:statusCode userInfo:nil]];
        }
    }
    [self.receivedData setLength:0];
}


-(void)parseIntradayCSV {
    
// s = symbol, d1 = trade date, t1 = trade time, o = open, h = high, g = low, l1 = last price, v = volume, p = prev close
//    wget -qO- http://download.finance.yahoo.com/d/quotes.csv?s=AAPL&f=spd1t1ohgl1v
    // "AAPL",556.97,"5/23/2012","4:00pm",557.33,572.80,553.23,570.56,20884292

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^\"([^\"]+)\",([^,]+),\"(\\d+)/(\\d+)/(\\d+)\",\"(\\d+):(\\d+)(\\w+)\",([^,]+),([^,]+),([^,]+),([^,]+),(\\d+)" options:NSRegularExpressionAnchorsMatchLines error:nil];	
    NSInteger lastTradeHour, lastTradeMinutes;
    BOOL closeSavedToDB = NO;
    
    NSString *pm = @"pm";
    
   // DLog(@"%@ = intraday value", csvString);
    
    NSTextCheckingResult *match = [regex firstMatchInString:self.csvString options:0 range:NSMakeRange(0, [self.csvString length])];
    
     double previousClose = 0.0;
    
    if (match && [[self.csvString substringWithRange:[match rangeAtIndex:9]] doubleValue] > 0) {
        // skip rows with "N/A" in the open value
                           
        // verify the response is for this symbol and not a previous, delayed request
        if ([self.symbol isEqualToString:[self.csvString substringWithRange:[match rangeAtIndex:1]]]) {
        
            previousClose = [[self.csvString substringWithRange:[match rangeAtIndex:2]] doubleValue];
            
            intradayBar.month = [[self.csvString substringWithRange:[match rangeAtIndex:3]] integerValue];
            intradayBar.day = [[self.csvString substringWithRange:[match rangeAtIndex:4]] integerValue];
            intradayBar.year = [[self.csvString substringWithRange:[match rangeAtIndex:5]] integerValue];
            
            lastTradeHour = [[self.csvString substringWithRange:[match rangeAtIndex:6]] integerValue];
            lastTradeMinutes = [[self.csvString substringWithRange:[match rangeAtIndex:7]] integerValue];
            
            intradayBar.open = [[self.csvString substringWithRange:[match rangeAtIndex:9]] doubleValue];
            intradayBar.high = [[self.csvString substringWithRange:[match rangeAtIndex:10]] doubleValue];
            intradayBar.low = [[self.csvString substringWithRange:[match rangeAtIndex:11]] doubleValue];
            intradayBar.close = [[self.csvString substringWithRange:[match rangeAtIndex:12]] doubleValue];
            intradayBar.volume = [[self.csvString substringWithRange:[match rangeAtIndex:13]] doubleValue];
            intradayBar.adjClose = intradayBar.close;   // not available intraday
            intradayBar.splitRatio = 1.;
            intradayBar.movingAvg1  = -1.;
            intradayBar.movingAvg2  = -1.;
            intradayBar.rsi         = -1.;
            intradayBar.mbb         = -1.;
            intradayBar.stdev       = -1.;
            
           // DLog(@" %d %d %d %f %f %f %f", intradayBar.year, intradayBar.month, intradayBar.day, intradayBar.open, intradayBar.high, intradayBar.low, intradayBar.close);
            
            if (fabs(cArray[0].close - previousClose) > 0.02) {
               // DLog(@"%@ previous close %f doesn't match %f", symbol, previousClose, cArray[0].close);

            } else if (lastTradeHour == 4 && [pm isEqualToString:[self.csvString substringWithRange:[match rangeAtIndex:8]]]) {
               // DLog(@"%@ %d/%d 4:%d pm", symbol, intradayBar.month, intradayBar.day, lastTradeMinutes);
                
                sqlite3 *db;
                sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL);
                sqlite3_stmt *statement;
                sqlite3_prepare_v2(db, saveHistory, -1, &statement, NULL);

                // (series, date, open, high, low, close, adjClose, volume, oldest)
                
                sqlite3_bind_int64(statement, 1, self.seriesId);
                sqlite3_bind_int64(statement, 2, [self dateIntFromBar:intradayBar]);        
                sqlite3_bind_text(statement, 3, [[self.csvString substringWithRange:[match rangeAtIndex:9]] UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(statement, 4, [[self.csvString substringWithRange:[match rangeAtIndex:10]] UTF8String], -1, SQLITE_TRANSIENT);            
                sqlite3_bind_text(statement, 5, [[self.csvString substringWithRange:[match rangeAtIndex:11]] UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(statement, 6, [[self.csvString substringWithRange:[match rangeAtIndex:12]] UTF8String], -1, SQLITE_TRANSIENT);
                // set adjClose = close
                sqlite3_bind_text(statement, 7, [[self.csvString substringWithRange:[match rangeAtIndex:12]] UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_int64(statement, 8, [[self.csvString substringWithRange:[match rangeAtIndex:13]] longLongValue]);
                sqlite3_bind_int64(statement, 9, 0);   // intraday isn't the last bar
                
                if(sqlite3_step(statement)==SQLITE_DONE){;
                   // DLog(@"%@ intraday bar saved to db %d-%d-%d", symbol, intradayBar.year, intradayBar.month, intradayBar.day);
                    [self setNextClose:[[self dateFromBar:intradayBar] nextTradingDate:self.gregorian]];

                    cArray[0].close = intradayBar.close;    // quick hack so two post-close intraday requests will be saved to DB
                    closeSavedToDB = YES;
                } else {
                   // DLog(@"%@ intraday Save to DB ERROR '%s'.", symbol, sqlite3_errmsg(db));
                }
                sqlite3_finalize(statement);                
                sqlite3_close(db);

            }
            
            if (NO == closeSavedToDB) {                
               // DLog(@"%@ last trade time is %d so don't save volume %f", symbol, lastTradeMinutes, intradayBar.volume);
                // don't change next close date
            }

            [self.delegate performSelector:@selector(APILoadedIntraday:) withObject:self];

        } else {
           // DLog(@"%@ reponse does not match symbol %@", symbol, csvString);  
        }
        
    } else if ([self.csvString hasPrefix:@"Missing Symbols List"]) {
        // symbol doesn't have intraday data (e.g. ^DJI)
        // canceling the download causes problems, so just let this historicalDataLoaded with countBars = 0

        [self.delegate performSelector:@selector(APICanceled:) withObject:self];
    }
    intraday = NO; 
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection {
    self.loadingData = NO;
	self.connection = nil;
    
	NSString *csv = [[NSString alloc] initWithData:self.receivedData encoding:NSUTF8StringEncoding];
    [self setCsvString:csv];
    [csv release];
    [_receivedData release];
	
    self.receivedData = nil;
    if (intraday) {
        [self parseIntradayCSV];
    } else {
        [self parseHistoricalCSV];
    }
}

// Date,Open,High,Low,Close,Volume,Adj Close
// 2009-06-08,143.82,144.23,139.43,143.85,33255400,143.85
//
// note, countBars already includes any bars cached in the DB
-(void)parseHistoricalCSV {
        
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d+)-(\\d+)-(\\d+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^\n]+)" options:NSRegularExpressionAnchorsMatchLines error:nil];	
    
    __block BOOL zeroIndexIsIntraday = NO;
    __block NSUInteger i = 0;
    __block NSUInteger barsFromWeb = [regex numberOfMatchesInString:self.csvString options:0 range:NSMakeRange(0, [self.csvString length])];
    
   // DLog(@"result is %@", csvString);
   // DLog(@"barsFromWeb is %d vs %d barsFromDB", barsFromWeb, barsFromDB);
    
    if (barsFromWeb == 0) {         
       // DLog(@"%@ empty response from API: %@", symbol, csvString);
                
        countBars = 0;
        return [self historicalDataLoadedWithIntraday:NO];        // canceling download causes problems, so call historicalDataLoaded with countBars = 0
    }
    
    NSInteger lastBar = barsFromDB + barsFromWeb - 1;

    BarStruct *webBars = cArray;

    if (barsFromDB > 0) {   // parse into separate memory in case of duplicate bars
        webBars = (BarStruct *)malloc(sizeof(BarStruct)*[self maxBars]);
    }
    
    sqlite3 *db;
    if (sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL)) {
        return;
    }
    
    sqlite3_exec(db, "BEGIN", 0, 0, 0);
    
    sqlite3_stmt *statement;
    
    sqlite3_prepare_v2(db, saveHistory, -1, &statement, NULL);
    
    [regex enumerateMatchesInString:self.csvString options:0 range:NSMakeRange(0, [self.csvString length]) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop){
   
        webBars[i].year = [[self.csvString substringWithRange:[match rangeAtIndex:1]] integerValue];
        webBars[i].month = [[self.csvString substringWithRange:[match rangeAtIndex:2]] integerValue];
        webBars[i].day = [[self.csvString substringWithRange:[match rangeAtIndex:3]] integerValue];
        webBars[i].open = [[self.csvString substringWithRange:[match rangeAtIndex:4]] doubleValue];
        webBars[i].high = [[self.csvString substringWithRange:[match rangeAtIndex:5]] doubleValue];              
        webBars[i].low = [[self.csvString substringWithRange:[match rangeAtIndex:6]] doubleValue];
        webBars[i].close = [[self.csvString substringWithRange:[match rangeAtIndex:7]] doubleValue];
        webBars[i].adjClose = [[self.csvString substringWithRange:[match rangeAtIndex:9]] doubleValue];
        
        if (i == 1 && webBars[1].day == webBars[0].day && webBars[1].month == webBars[0].month && webBars[1].year == webBars[0].year) {
            /* Sometimes Yahoo will duplicate a bar, as happened for this request on July 2nd at 22:40:42 
             url is http://ichart.finance.yahoo.com/table.csv?s=AAPL&a=5&b=29&c=2012&d=6&e=2&f=2012&g=d&ignore=.csv
             
             Date,Open,High,Low,Close,Volume,Adj Close
             2012-07-02,584.73,593.47,583.64,592.53,13769700,592.52
             2012-07-02,584.73,593.47,583.60,592.52,14269800,592.52
             2012-06-29,578.00,584.00,574.25,584.00,15033500,584.00     
             */
           // DLog(@" %@ YAHOO DUPLICATE BAR IN %@, resetting __i to 0", symbol, csvString);
            i = 0;
            barsFromWeb--;
        } else if (i == 0) {
            if ([[self dateFromBar:webBars[0]] isTodayIntraday]) {
                zeroIndexIsIntraday = YES;
                webBars[0].adjClose = webBars[0].close;   // avoid incorrect split calculation
            }
        }

        webBars[i].splitRatio = 1.;
        
        if ([[self.csvString substringWithRange:[match rangeAtIndex:8]] isEqualToString:@"4294967200"]) {
            webBars[i].volume = 0;     // no data
        } else {
            webBars[i].volume = [[self.csvString substringWithRange:[match rangeAtIndex:8]] doubleValue];
        }
        webBars[i].movingAvg1 = .0f;
        webBars[i].movingAvg2 = .0f;
        
       // DLog(@"%@ %d %d %d %d %f %f %f %f %f %f", symbol, __i, webBars[__i].year, webBars[__i].month, webBars[__i].day, webBars[__i].open, webBars[__i].high, webBars[__i].low, webBars[__i].close, webBars[__i].adjClose, webBars[__i].volume);
        
        if (i > 0 || zeroIndexIsIntraday == NO) {
            sqlite3_bind_int64(statement, 1, self.seriesId);
            sqlite3_bind_int64(statement, 2, [self dateIntFromBar:webBars[i]]);        
            sqlite3_bind_text(statement, 3, [[self.csvString substringWithRange:[match rangeAtIndex:4]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 4, [[self.csvString substringWithRange:[match rangeAtIndex:5]] UTF8String], -1, SQLITE_TRANSIENT);            
            sqlite3_bind_text(statement, 5, [[self.csvString substringWithRange:[match rangeAtIndex:6]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 6, [[self.csvString substringWithRange:[match rangeAtIndex:7]] UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(statement, 7, [[self.csvString substringWithRange:[match rangeAtIndex:9]] UTF8String], -1, SQLITE_TRANSIENT);
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
    }];
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
        sqlnewestDate = [self.newestDateLoaded formatDate:self.gregorian];
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
    
    [self historicalDataLoadedWithIntraday:zeroIndexIsIntraday];
}

// called after 1000 bars are deleted
- (void) adjustNewestDateLoadedTo:(NSDate *)adjustedDate {
    [self setNewestDateLoaded:adjustedDate];
    [self setNextClose:[self.newestDateLoaded nextTradingDate:self.gregorian]];
}


@end
