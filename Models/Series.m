#import "Series.h"
#include <CoreGraphics/CGColor.h>
#import "CIAppDelegate.h"
#import "sqlite3.h"

@implementation Series

- (void) setColor:(CGColorRef)c {
    color = c;
    colorHalfAlpha = CGColorCreateCopyWithAlpha(c, .5);
}

- (void) setUpColor:(CGColorRef)uc {
    upColor = uc;
    upColorHalfAlpha = CGColorCreateCopyWithAlpha(uc, .5);
    
    CGFloat *components = malloc(sizeof(CGFloat) * 4);
    CGFloat *darkComponents = malloc(sizeof(CGFloat) * 4);
    
    memcpy(components, CGColorGetComponents(upColor), sizeof(CGFloat) * 4);
    
    for (NSInteger i = 0; i < 3; i++) {

  //     // DLog(@"component was %f so inverse %f", components[i], MAX(.0, 1. - components[i]));
        darkComponents[i] = components[i] / 2 + 0.25;
       // DLog(@"component was %f so darkComponent %f", components[i], darkComponents[i]);
        
        components[i] = MAX(.0, 1. - components[i]);
    }
    
    CGColorSpaceRef deviceRGB = CGColorSpaceCreateDeviceRGB();
    
    colorInverse = CGColorCreate(deviceRGB, components);

    darkComponents[3] = 0.5;
    upColorDarkHalfAlpha = CGColorCreate(deviceRGB, darkComponents);
    
    colorInverseHalfAlpha = CGColorCreateCopyWithAlpha(colorInverse, .75);
    CGColorSpaceRelease(deviceRGB);
}

- (void) setColorWithHexString:(NSString *) stringToConvert {

//    // DLog(@"%@ hex loaded %@", symbol, stringToConvert);
    
    NSScanner *scanner = [NSScanner scannerWithString:stringToConvert];
    unsigned hex;
    NSInteger r = 0, g = 0, b = 0;
    if ([scanner scanHexInt:&hex]) {        // returns black if no match
        r = (hex >> 16) & 0xFF;
        g = (hex >> 8) & 0xFF;
        b = (hex) & 0xFF;
    }
    CGFloat components[4] = {r / 255.0f, g / 255.0f, b / 255.0f, 1.0f};
    
    CGColorSpaceRef deviceRGB = CGColorSpaceCreateDeviceRGB();
    CGColorRef colorRef = CGColorCreate(deviceRGB, components);
    [self setColor:colorRef];
    [self setUpColor:colorRef];
    // don't release colorRef because it isn't a retainable object; only call CGColorRelease when series is dealloc'ed
    CGColorSpaceRelease(deviceRGB);
    
    if (chartType < 3) {
        if (r == 0 && b == 0) {
            [self setColor:[UIColor redColor].CGColor];
        }
    }
}

- (BOOL) matchesColor:(UIColor *)theirColor {
    
    NSString *currentColorHex = [self hexFromColor];
    NSString *theirColorHex = [self hexFromColor:theirColor.CGColor];
    
    return [currentColorHex isEqualToString: theirColorHex];
}

- (NSString *) hexFromColor {
    return [self hexFromColor:upColor];
}

- (NSString *) hexFromColor:(CGColorRef)color {
    
    const CGFloat *components = CGColorGetComponents(color);
    unsigned r, g, b;
    
    r = 255 * components[0];
    g = 255 * components[1];
    b = 255 * components[2];
    
    unsigned hex;
    
    hex = (r << 16) + (g << 8) + b;
    
   // DLog(@"hex is %06x", hex);
    
    return [NSString stringWithFormat:@"%06x", hex];
}

- (void) addToFundamentals:(NSString *)type {

    if ([self.fundamentalList rangeOfString:type].length > 0) {
       // DLog(@"%@ is already in %@", type, self.fundamentalList);
    } else {
//        // DLog(@"%@ is NOT in %@ so adding", type, self.fundamentalList);
        [self setFundamentalList:[self.fundamentalList stringByAppendingFormat:@"%@,", type]];
        
  //      // DLog(@"self.fundamentalList is now %@", self.fundamentalList);
    }
}

- (void) removeFromFundamentals:(NSString *)type {
    
    if ([self.fundamentalList rangeOfString:type].length > 0) {
    //    // DLog(@"removing %@ from %@", type, self.fundamentalList);
        [self setFundamentalList:[self.fundamentalList stringByReplacingOccurrencesOfString:type withString:@""]];
    }
    while ([self.fundamentalList rangeOfString:@",,"].length > 0) {
        [self setFundamentalList:[self.fundamentalList stringByReplacingOccurrencesOfString:@",," withString:@","]];
    }
   // DLog(@"self.fundamentalList is now %@", self.fundamentalList);
}

- (void) addToTechnicals:(NSString *)type {
    
    if ([self.technicalList rangeOfString:type].length > 0) {
       // DLog(@"%@ is already in %@", type, self.technicalList);
    } else {
       // DLog(@"%@ is NOT in %@ so adding", type, self.technicalList);
        [self setTechnicalList:[self.technicalList stringByAppendingFormat:@"%@,", type]];
       // DLog(@"self.technicalList is now %@", self.technicalList);
    }
}


- (void) removeFromTechnicals:(NSString *)type {
    
    if ([self.technicalList rangeOfString:type].length > 0) {
       // DLog(@"removing %@ from %@", type, self.technicalList);
        [self setTechnicalList:[self.technicalList stringByReplacingOccurrencesOfString:type withString:@""]];
    }
    while ([self.technicalList rangeOfString:@",,"].length > 0) {
        [self setTechnicalList:[self.technicalList stringByReplacingOccurrencesOfString:@",," withString:@","]];
    }
 //   DLog(@"technicalList is now %@", self.technicalList);
}

- (Series *) init {
    self = [super init];
    self->id = 0;
    self->comparisonSeriesId = 0;
    self->hasFundamentals = 0;
    self->daysAgo = 0;
    self->chartType = 2; // Candle
    [self setFundamentalList:@""];
    [self setTechnicalList:@""];
    return self;
}

- (void) convertDateStringToDateWithFormatter:(NSDateFormatter *)formatter {
    
   NSDate *dateFromString = [formatter dateFromString:[self.startDateString stringByAppendingString:@"T20:00:00Z"]];
       
   [self setStartDate:[dateFromString laterDate:[NSDate dateWithTimeIntervalSinceReferenceDate:23328000]]];
}

// returns an NSMutableArray of NSMutableArrays containing 1 stock each
+ (NSMutableArray *) findSymbol:(NSString *)search inDB:(sqlite3 *)db {
    
   // DLog(@"running findSymbol %@", search);
    
    NSInteger chartTypeDefault = 2; // Candle
    
    if ([[NSUserDefaults standardUserDefaults] valueForKey:@"chartTypeDefault"]) {
        
        if ([[NSUserDefaults standardUserDefaults] integerForKey:@"chartTypeDefault"] != chartTypeDefault) {
            chartTypeDefault = [[NSUserDefaults standardUserDefaults] integerForKey:@"chartTypeDefault"];
        }
    }
    
    NSString *technicalDefaults, *fundamentalDefaults = @"";
    if ([[[NSUserDefaults standardUserDefaults] valueForKey:@"technicalDefaults"] length] > 1) {
        technicalDefaults = [[NSUserDefaults standardUserDefaults] valueForKey:@"technicalDefaults"];
    } else {
        technicalDefaults = @"sma200,bb20,";
    }    

    if ([[[NSUserDefaults standardUserDefaults] valueForKey:@"fundamentalDefaults"] length] > 1) {
        fundamentalDefaults = [[NSUserDefaults standardUserDefaults] valueForKey:@"fundamentalDefaults"];
    }
    
    sqlite3_stmt *statement;
    
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:10];	
    
    NSInteger retVal = sqlite3_prepare_v2(db, "SELECT rowid,symbol,name,startDate,hasFundamentals,offsets(series) FROM series WHERE series MATCH ? ORDER BY offsets(series) ASC LIMIT 50", -1, &statement, NULL);
	
    if (retVal == SQLITE_OK) {
            
        sqlite3_bind_text(statement, 1, [[NSString stringWithFormat:@"%@*", search] UTF8String], -1, SQLITE_TRANSIENT);
            
        while(sqlite3_step(statement) == SQLITE_ROW) {
                
            Series *newSeries = [[self alloc] init];
            
            newSeries->id = sqlite3_column_int(statement, 0);
            [newSeries setSymbol:[NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, 1)]];
            [newSeries setName:[NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, 2)]];
            
            // DLog(@"%@ has matchinfo %@", newSeries.symbol,[NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, 5)] );
            
            // Faster search results UI if string to date conversion happens after user selects the stock
            [newSeries setStartDateString:[NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, 3)]];
            newSeries->chartType = chartTypeDefault;
            newSeries->hasFundamentals = sqlite3_column_int(statement, 4);
            
            if (newSeries->hasFundamentals == 2) {
                    [newSeries setFundamentalList:fundamentalDefaults];
            } else if (newSeries->hasFundamentals == 1) {
                    // Bank fundamentals (loans, etc.) are not supported by chartinsight.com
            }
            
            [newSeries setTechnicalList:technicalDefaults];
                
            [list addObject:[NSMutableArray arrayWithObject:newSeries]];
            [newSeries release];
        }            

    } else {
     //   DLog(@"DB findSeries error %s", sqlite3_errmsg(db));
    }
    sqlite3_finalize(statement);
    return list;
}

+ (NSMutableArray *) findSeries:(NSString *)str {
    
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:50];
    NSMutableArray *exactMatches = [NSMutableArray arrayWithCapacity:3];
    
    sqlite3 *db;
    sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
    
    [list addObjectsFromArray:[Series findSymbol:str inDB:db]];
    
    if (list.count == 0) {  // split into separate searches
        for (NSString *term in [str componentsSeparatedByString:@" "]) {
        
            if (term.length == 0) continue;
         
            BOOL middleTerm = NO;
            if ([str rangeOfString:[term stringByAppendingString:@" "]].length > 0) {
               // DLog(@"term %@ ends with space so add a space", term);
                term = [term stringByAppendingString:@" "];
                middleTerm = YES;
            }
            
            NSMutableArray *found = [NSMutableArray arrayWithArray:[Series findSymbol:term inDB:db]];
            
            [list removeAllObjects];
            [list addObjectsFromArray:found];
            
            if (found.count > 0) {
                Series *s = [[found objectAtIndex:0] objectAtIndex:0]; 
                
                if (found.count == 1 || middleTerm) {    // save this exact match for the next term                

                   // DLog(@"adding best match %@ to array", s.name);
                    [exactMatches addObject:s];                        
                } 
                if (exactMatches.count > 0) {
                    for (NSMutableArray *array in list) {
                        for (NSInteger i = 0; i < exactMatches.count; i++) {
                            Series *match = [exactMatches objectAtIndex:i];
                            if (match->id != s->id) {
                                [array insertObject:match atIndex:i];      // insert best matches at front
                            }
                        }                       
                    }
                }
            }  else if (exactMatches.count > 0) {
               // DLog(@"list is empty after search for %@ but exact matches is not", term);
                [list addObject:exactMatches];
            }
        }
    }    
    sqlite3_close(db);
      
    if (list.count == 0) {            
        Series *newSeries = [[self alloc] init];
        [newSeries setSymbol:@""];
        [newSeries setName:@"No matches with supported fundamentals"];
        [list addObject:[NSMutableArray arrayWithObject:newSeries]];
        [newSeries release]; 
    }
    return list;
}

@end
