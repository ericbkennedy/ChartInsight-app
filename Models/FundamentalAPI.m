#import "DataAPI.h"     // for date category parsing
#import "FundamentalAPI.h"
#import "Series.h"
#import "StockData.h"

@interface FundamentalAPI ()
@property (strong, nonatomic) NSString *responseString;
@property (strong, nonatomic) NSString *symbol;
@end

@implementation FundamentalAPI 

- (instancetype) init {
    self = [super init];
    self.reportTypes = 0;
    
    [self setColumns:[NSMutableDictionary new]];
    return self;
}

-(NSURL *) formatRequestWithKeys:(NSString *)keys {
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://www.chartinsight.com/api/iOSFundamentals/%@/%@", self.symbol, keys]];
}

// this is tricky because the CSV report is parsed by quarter, not type, but we store the values in arrays per type
// so we need to create an array per type, and store index those arrays with another array so we can add extra objects to the arrays instead of the dictionary itself
- (void) parseResponse {
    
    // DLog(@"parseResponse on %@", self.responseString);

    if (self.responseString.length < 13 || [[self.responseString substringToIndex:8] isEqualToString:@"y	m	d	q	"] == NO) {
        DLog(@"Fundamental API Header mismatch so failed");
        return;
    }
    
    int colCountYMDQ = 4;
    // Split up tab-delimited file with componentsSeparatedByString
    NSArray *lines = [self.responseString componentsSeparatedByString:@"\n"];
    
    NSMutableArray *listOfColumns = [NSMutableArray arrayWithCapacity:3];
    NSMutableArray *thisArray;
    
    for (NSInteger l = 0; l < lines.count; l++) {
        NSArray *parts = [[lines objectAtIndex:l] componentsSeparatedByString:@"\t"];
        if (parts.count >= colCountYMDQ) {
        
            if (l == 0) { // header
                for (NSInteger p = colCountYMDQ; p < parts.count; p++) {
                    thisArray = [NSMutableArray arrayWithCapacity:lines.count];
                    [listOfColumns addObject:thisArray];
                   //  DLog(@"created array with key %@", [parts objectAtIndex:p]);
                    [self.columns setObject:thisArray forKey:[parts objectAtIndex:p]];
                }

            } else {
                
                [self.year addObject:[NSNumber numberWithInt:(int)[[parts objectAtIndex:0] integerValue]]];
                [self.month addObject:[NSNumber numberWithInt:(int)[[parts objectAtIndex:1] integerValue]]];
                [self.day addObject:[NSNumber numberWithInt:(int)[[parts objectAtIndex:2] integerValue]]];
                [self.quarter addObject:[NSNumber numberWithInt:(int)[[parts objectAtIndex:3] integerValue]]];
                [self.barAlignments addObject:@-1];     // initialize it so we just need to update the value later
                
                for (NSInteger p = colCountYMDQ; p < parts.count; p++) {
                    thisArray = [listOfColumns objectAtIndex:(p - colCountYMDQ)];
                    // DLog(@"adding %@ to column %ld at index %ld", [parts objectAtIndex:p], (p-colCountYMDQ), l);
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
        [self.barAlignments replaceObjectAtIndex:r withObject:[NSNumber numberWithLong:b]];
    }
}

- (NSInteger) barAlignmentForReport:(NSInteger)r {
    if (r < [self.barAlignments count]) {
        return [[self.barAlignments objectAtIndex:r] integerValue];
    }
   // DLog(@"bar alignment is -1 at %d", r);
    return -1;
}

- (nullable NSDecimalNumber *) valueForReport:(NSInteger)r withKey:(NSString *)key {
    
    NSArray *array = [self.columns objectForKey:key];
    if (r < array.count) {
        return [array objectAtIndex:r];        
    }
    return nil;
}

- (void) getFundamentalsForSeries:(Series *)series withDelegate:(id)caller {
    
    self.symbol = series.symbol;
    self.delegate = caller;
    
    [self setYear:[NSMutableArray arrayWithCapacity:50]];
    [self setMonth:[NSMutableArray arrayWithCapacity:50]];
    [self setDay:[NSMutableArray arrayWithCapacity:50]];
    [self setQuarter:[NSMutableArray arrayWithCapacity:50]];
    [self setBarAlignments:[NSMutableArray arrayWithCapacity:50]];
        
    NSURL *URL = [self formatRequestWithKeys:series.fundamentalList];
    
    NSURLSessionTask *task = [[NSURLSession sharedSession] dataTaskWithURL:URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        if (error) {
            [self.delegate performSelector:@selector(APIFailed:) withObject:[error localizedDescription]];

        } else if (response && [response respondsToSelector:@selector(statusCode)]) {
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            if (statusCode == 404) {
                DLog(@"%@ error with %ld and %@", self.symbol, (long)statusCode, URL);
                
                [self.delegate performSelector:@selector(APIFailed:) withObject:@"404 response"];

            } else if (statusCode == 200 && data && data.length > 10) {
                NSString *csv = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                [self setResponseString:csv];
                [csv release];
                
                [self parseResponse];
            }
        }
    }];
    [task resume];
}


@end
