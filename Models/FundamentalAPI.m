#import "DataAPI.h"     // for date category parsing
#import "FundamentalAPI.h"
#import "Series.h"
#import "StockData.h"

@interface FundamentalAPI ()
@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, nonatomic) NSMutableData *receivedData;
@property (strong, nonatomic) NSString *responseString;
@end

@implementation FundamentalAPI 

- (id) init {
    self = [super init];
    self.reportTypes = 0;
    
    [self setColumns:[NSMutableDictionary new]];
    return self;
}

-(NSURL *) formatRequestWithKeys:(NSString *)keys {
    
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://chartinsight.com/fundamentals17.php?id=%d&metrics=%@", self.seriesId, keys]];
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.receivedData appendData:data];
}

-(void)connection:(NSURLConnection *)failedConnection didFailWithError:(NSError *)error {
    
    DLog(@"%d err = %@ for connection %@", self.seriesId, [error localizedDescription], [failedConnection description]);

    [self.connection cancel];
    self.receivedData = nil;
    self.connection = nil;
    [self.delegate performSelector:@selector(APIFailed:) withObject:[error localizedDescription]];
}

-(void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)response {
    // this can be called multiple times (in the case of a redirect), so each time we reset the data.
    
    if ([response respondsToSelector:@selector(statusCode)])  {
        NSInteger statusCode = [((NSHTTPURLResponse *)response) statusCode];
        if (statusCode == 404) {
            [c cancel];  // stop connecting; no more delegate messages
            [self connection:c didFailWithError:nil];
           // DLog(@"%d error with %d", seriesId, statusCode);
        }
    }
    [self.receivedData setLength:0];
        
}


// this is tricky because the CSV report is parsed by quarter, not type, but we store the values in arrays per type
// so we need to create an array per type, and store index those arrays with another array so we can add extra objects to the arrays instead of the dictionary itself

- (void) parseResponse {
    
    // DLog(@"parseResponse on %@", self.responseString);

    if (self.responseString.length < 13 || [[self.responseString substringToIndex:12] isEqualToString:@"sym	y	m	d	q	"] == NO) {
        // DLog(@"mismatch so failed");
        return;
    }
    
    // Split up tab-delimited file with componentsSeparatedByString
    NSArray *lines = [self.responseString componentsSeparatedByString:@"\n"];
    
    NSMutableArray *listOfColumns = [NSMutableArray arrayWithCapacity:3];
    NSMutableArray *thisArray;
    
    for (NSInteger l = 0; l < lines.count; l++) {
        NSArray *parts = [[lines objectAtIndex:l] componentsSeparatedByString:@"\t"];
        
        if (parts.count >= 5) {
        
            if (l == 0) { // header
                for (NSInteger p = 5; p < parts.count; p++) {
                    thisArray = [NSMutableArray arrayWithCapacity:lines.count];
                    [listOfColumns addObject:thisArray];
                    // DLog(@"created array with key %@", [parts objectAtIndex:p]);
                    [self.columns setObject:thisArray forKey:[parts objectAtIndex:p]];
                }

            } else {
                
                [self.year addObject:[NSNumber numberWithInt:[[parts objectAtIndex:1] integerValue]]];
                [self.month addObject:[NSNumber numberWithInt:[[parts objectAtIndex:2] integerValue]]];
                [self.day addObject:[NSNumber numberWithInt:[[parts objectAtIndex:3] integerValue]]];
                [self.quarter addObject:[NSNumber numberWithInt:[[parts objectAtIndex:4] integerValue]]];
                [self.barAlignments addObject:@-1];     // initialize it so we just need to update the value later
                
                for (NSInteger p = 5; p < parts.count; p++) {
                    thisArray = [listOfColumns objectAtIndex:(p - 5)];
                    // DLog(@"adding %@ to column %d at index %d", [parts objectAtIndex:p], (p-5), l);
                    if ([[parts objectAtIndex:p] length] > 0) {
                        [thisArray addObject:[[[NSDecimalNumber alloc] initWithString:[parts objectAtIndex:p]] autorelease]];
                    } else {
                        [thisArray addObject:[NSDecimalNumber notANumber]];
                    }
                }
            }
        }
    }  
    [self.delegate performSelector:@selector(APILoadedFundamentalData:) withObject:self];
}

- (void) setBarAlignment:(NSInteger)b forReport:(NSInteger)r {
    if (r < [self.barAlignments count]) {
        [self.barAlignments replaceObjectAtIndex:r withObject:[NSNumber numberWithInt:b]];
    }
}

- (NSInteger) barAlignmentForReport:(NSInteger)r {
    if (r < [self.barAlignments count]) {
        return [[self.barAlignments objectAtIndex:r] integerValue];
    }
   // DLog(@"bar alignment is -1 at %d", r);
    return -1;
}


- (void) connectionDidFinishLoading:(NSURLConnection *)connection {
	self.connection = nil;
    
	NSString *csv = [[NSString alloc] initWithData:self.receivedData encoding:NSUTF8StringEncoding];
    
    [self setResponseString:csv];    
    [csv release];
	
    self.receivedData = nil;    // don't release receivedData because iOS manages retain counts
    [self parseResponse];
}

- (NSDecimalNumber *) valueForReport:(NSInteger)r withKey:(NSString *)key {
    
    NSMutableArray *array = [self.columns objectForKey:key];
    if (r < array.count) {
        return [array objectAtIndex:r];        
    }
    return nil;
}


- (void) dealloc {
    self.delegate = nil;
    self.receivedData = nil;    // don't release receivedData because iOS manages retain counts
    [super dealloc];
}


- (void) getFundamentalsForSeries:(Series *)series withDelegate:(id)caller {
    
    self.seriesId = series->id;
    self.delegate = caller;
    
    [self setYear:[NSMutableArray arrayWithCapacity:50]];
    [self setMonth:[NSMutableArray arrayWithCapacity:50]];
    [self setDay:[NSMutableArray arrayWithCapacity:50]];
    [self setQuarter:[NSMutableArray arrayWithCapacity:50]];
    [self setBarAlignments:[NSMutableArray arrayWithCapacity:50]];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[self formatRequestWithKeys:series.fundamentalList] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60.0];
    
   // DLog(@"request is %@", request.URL);
    
    self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
    if (self.connection) {      
        [self setReceivedData:[NSMutableData data]];       // initialize it
    } else {
        //TODO: Inform the user that the download could not be started
    }
}


@end
