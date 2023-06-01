#import "CIAppDelegate.h"
#import "Comparison.h"
#import "Series.h"
#import "sqlite3.h"

@implementation Comparison

- (instancetype) init {
    self = [super init];
    [self setSeriesList:[NSMutableArray arrayWithCapacity:4]];
    return self;
}

- (void) dealloc {
   // DLog(@"dealloc comparison %d", self.id);
    
    if (self.seriesList != nil) {
        
        for (Series *s in self.seriesList) {
            [s release];
        }
        // TODO: fix this, it keeps crashing for some reason
    //    [self.seriesList release];
    }
    [super dealloc];
}

+ (NSMutableArray *) listAll:(NSString *)myDbPath {
        
    typedef NS_ENUM(NSInteger, ListAllColumnIndex) {
        ListAllColumnComparisonId,
        ListAllColumnComparisonSeriesId,
        ListAllColumnSeriesId,
        ListAllColumnSymbol,
        ListAllColumnStartDate,
        ListAllColumnHasFundamentals,
        ListAllColumnChartType,
        ListAllColumnDaysAgo,
        ListAllColumnColor,
        ListAllColumnFundamentalList,
        ListAllColumnTechnicalList
    };
    sqlite3 *db;
    
    if (sqlite3_open_v2([myDbPath UTF8String], &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        return nil;
    }
        
	sqlite3_stmt *statement;
    
    if (sqlite3_prepare_v2(db, "SELECT K.rowid, CS.rowid, seriesId, symbol, startDate, hasFundamentals, chartType, daysAgo, color, fundamentals, technicals FROM comparison K JOIN comparisonSeries CS on K.rowid = CS.comparisonId JOIN series ON series.rowid = seriesId ORDER BY K.rowid, CS.rowId", -1, &statement, NULL) != SQLITE_OK)
    {
        DLog(@"new SQL failed");
    }
	
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:25];	
    Series *series;
    Comparison *comparison;
    NSInteger lastComparisonId = 0;
    NSString *title = @"";
    
    while(sqlite3_step(statement) == SQLITE_ROW) {
        
        if (lastComparisonId != sqlite3_column_int(statement, 0)) {
            comparison = [[self alloc] init];
            [comparison setId: sqlite3_column_int(statement, 0)];
           // DLog(@"allocating new comparison with id %d", [comparison id]);
            lastComparisonId = [comparison id];
            [list addObject:comparison];
            [comparison release];
            title = @"";
        } else {
           // DLog(@"allocating existing series id %d", lastComparisonId);
        }
        
        series = [[Series alloc] init];         
        series->comparisonSeriesId = sqlite3_column_int(statement, ListAllColumnComparisonSeriesId);
        series->id = sqlite3_column_int(statement, ListAllColumnSeriesId);
                              
        [series setSymbol:[NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, ListAllColumnSymbol)]];
        
       // DLog(@"symbol is %@", [series symbol]);
        
        title = [title stringByAppendingFormat:@"%@ ", series.symbol];

        series.startDateString = [NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, ListAllColumnStartDate)];
        // startDateString will be converted to NSDate by [StockData init] as price data is loaded
        
        series->hasFundamentals = sqlite3_column_int(statement, ListAllColumnHasFundamentals);
        
        series->chartType = sqlite3_column_int(statement, ListAllColumnChartType);
        series->daysAgo = sqlite3_column_int(statement, ListAllColumnDaysAgo);
        
        if (sqlite3_column_bytes(statement, ListAllColumnColor) > 2) {
            [series setColorWithHexString:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, ListAllColumnColor)]];
        } else {
            [series setColorWithHexString:@"009900"];   // green (and by convention, red)
        }
                
        if (sqlite3_column_bytes(statement, ListAllColumnFundamentalList) > 2) {
            const char *fundamentals = (const char *)sqlite3_column_text(statement, ListAllColumnFundamentalList);
            [series setFundamentalList:[NSString stringWithUTF8String:fundamentals]];
        }
        
        if (sqlite3_column_bytes(statement, ListAllColumnTechnicalList) > 2) {
            const char *technicals = (const char *)sqlite3_column_text(statement, ListAllColumnTechnicalList);
            [series setTechnicalList:[NSString stringWithUTF8String:technicals]];
        }
        
        [[comparison seriesList] addObject:series];
        [comparison setTitle:title];
        [series release];

    }
    sqlite3_finalize(statement);	
    sqlite3_close(db);
    
    return list;
}

- (void) saveToDb {
    
    sqlite3 *db;
    sqlite3_stmt *statement;
    
    if (sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        return;
    }
    
    if (self.id == 0) {
       // DLog(@"comparisonId is %d so insertSQL to get an id for each comparisonSeries", id);
        sqlite3_prepare_v2(db, "INSERT INTO comparison (sort) VALUES (0)", -1, &statement, NULL);
        sqlite3_step(statement);
        sqlite3_finalize(statement);
        NSInteger insertedRowid = (NSInteger) sqlite3_last_insert_rowid(db);    // cast to NSInteger since we don't support billions of comparisons...
        [self setId:insertedRowid];
    }
        
    for (NSInteger i = 0; i < self.seriesList.count; i++) {
        Series *series = [self.seriesList objectAtIndex:i];

        if (series->comparisonSeriesId > 0) {
            sqlite3_prepare(db, "UPDATE comparisonSeries SET daysAgo = ?, chartType = ?, color = ?, fundamentals = ?, technicals = ? WHERE rowid = ?", -1, &statement, NULL);
   
            sqlite3_bind_int64(statement, 1, series->daysAgo);
            sqlite3_bind_int64(statement, 2, series->chartType);
            sqlite3_bind_text(statement, 3, [[series hexFromColor] UTF8String], 6, SQLITE_STATIC); // STATIC = don't free space
            sqlite3_bind_text(statement, 4, [[series fundamentalList] UTF8String], (int)[series fundamentalList].length, SQLITE_STATIC);
            sqlite3_bind_text(statement, 5, [[series technicalList] UTF8String], (int)[series technicalList].length, SQLITE_STATIC);
            sqlite3_bind_int64(statement, 6, series->comparisonSeriesId);

            if(sqlite3_step(statement)==SQLITE_DONE){
          //      // DLog(@"updated %d to DB for comparison id %d", series->comparisonSeriesId, [self id]);
            } else {
          //      // DLog(@"DB ERROR '%s'.", sqlite3_errmsg(db));
            }
            sqlite3_finalize(statement);
        } else if (series->comparisonSeriesId == 0) {
            
            sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO comparisonSeries (comparisonId, seriesId, daysAgo, chartType, color, fundamentals, technicals) VALUES (?, ?, ?, ?, ?, ?, ?)", -1, &statement, NULL);
            
            sqlite3_bind_int64(statement, 1, [self id]);
            sqlite3_bind_int64(statement, 2, series->id);
            sqlite3_bind_int64(statement, 3, series->daysAgo);
            sqlite3_bind_int64(statement, 4, series->chartType);
            sqlite3_bind_text(statement, 5, [[series hexFromColor] UTF8String], 6, SQLITE_STATIC); // STATIC = don't free space
            sqlite3_bind_text(statement, 6, [[series fundamentalList] UTF8String], (int)[series fundamentalList].length, SQLITE_STATIC);
            sqlite3_bind_text(statement, 7, [[series technicalList] UTF8String], (int)[series technicalList].length, SQLITE_STATIC);

            if(sqlite3_step(statement)==SQLITE_DONE){
                series->comparisonSeriesId = (NSInteger) sqlite3_last_insert_rowid(db);

             //   DLog(@"inserted into DB as CSID %d for comparison id %d", series->comparisonSeriesId, [self id]);
            } else {
              //  DLog(@"DB ERROR '%s'.", sqlite3_errmsg(db));
            }
            sqlite3_finalize(statement);
        }
    }

    sqlite3_close(db);
}


- (void) deleteFromDb {
    
    sqlite3 *db;
    
    if (sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        return;
    }
    sqlite3_stmt *statement;
    
    if (sqlite3_prepare_v2(db, "DELETE FROM comparisonSeries WHERE comparisonId =  ?", -1, &statement, NULL) == SQLITE_OK) {
        
        sqlite3_bind_int64(statement, 1, self.id);
        if(sqlite3_step(statement) != SQLITE_DONE){;
            DLog(@"Delete ComparisonSeries DB ERROR '%s'.", sqlite3_errmsg(db));
        }
    }
    
    sqlite3_finalize(statement);
    
    if (sqlite3_prepare_v2(db, "DELETE FROM comparison WHERE rowid =  ?", -1, &statement, NULL) == SQLITE_OK) {
        
        sqlite3_bind_int64(statement, 1, self.id);
        if(sqlite3_step(statement) != SQLITE_DONE){;
            DLog(@"Delete Comparison DB ERROR '%s'.", sqlite3_errmsg(db));
        }
    }
    sqlite3_finalize(statement);
    sqlite3_close(db);
}


- (void) deleteComparisonSeriesAtIndex:(NSInteger)index {
    
    if (index >= [self.seriesList count]) { // index out of bounds
        return;
    }
    
    Series *s = [self.seriesList objectAtIndex:index];
    
    [self deleteSeries:s]; 
}

- (void) deleteSeries:(Series *)s {
    
    sqlite3 *db;
    if (sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        return;
    }
    
    sqlite3_stmt *statement;
    
    if (sqlite3_prepare_v2(db, "DELETE FROM comparisonSeries WHERE rowid=?", -1, &statement, NULL) == SQLITE_OK) {
        
        sqlite3_bind_int64(statement, 1, s->comparisonSeriesId);    // for comparisonSeries table
        
        if(sqlite3_step(statement) == SQLITE_DONE){;
            [self.seriesList removeObject:s];
        } else {
            DLog(@"DB ERROR '%s'.", sqlite3_errmsg(db));
        }
    }
    
    sqlite3_finalize(statement);
    sqlite3_close(db);
}

- (NSArray *)chartTypes {
    return [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] chartTypes];
}

- (NSArray *)metrics {
    return [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] metrics];
}

- (BOOL) showDialGrips {
    NSInteger daysAgo = 0;
    if (self.seriesList.count > 1) {
        for (Series *series in self.seriesList) {
            if (series->daysAgo > 0 || series->daysAgo != daysAgo) {
                return YES;
            } else {
                daysAgo = series->daysAgo;
            }
        }
    }
    return NO;
}

// Count of superset of all keys for all subcharts excluding book value per share, which is an overlay
- (NSArray *) sparklineKeys {

    NSString *keyStrings = @"";
    
    for (Series *series in self.seriesList) {
        keyStrings = [keyStrings stringByAppendingString:series.fundamentalList];
    }
 
    keyStrings = [keyStrings stringByReplacingOccurrencesOfString:@"BookValuePerShare," withString:@""];
        
    NSMutableArray *sortedMetrics = [NSMutableArray new];
    
    for (NSArray *category in [self metrics]) {
        for (NSArray *metric in category) {
            NSString *key = [metric objectAtIndex:0];
            if ([keyStrings rangeOfString:key].length > 0) {
                [sortedMetrics addObject:key];
            }
        }
    }
    return sortedMetrics;
}

- (void) resetMinMax {
    [self setMinForKey:[NSMutableDictionary new]];
    [self setMaxForKey:[NSMutableDictionary new]];
}

- (void) updateMinMaxForKey:(NSString *)key withValue:(NSDecimalNumber *)reportValue {
    if (reportValue != nil && [reportValue isEqualToNumber:[NSDecimalNumber notANumber]] == NO) {
        if ([self.minForKey objectForKey:key] == nil || [[self.minForKey objectForKey:key] isEqualToNumber:[NSDecimalNumber notANumber]]) {            
            if ([reportValue compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
                [self.minForKey setObject:reportValue forKey:key];
            } else {
                [self.minForKey setObject:[NSDecimalNumber zero] forKey:key];
            }
           // DLog(@"initializing min to %@ for key %@", [self.minForKey objectForKey:key], key);
            [self.maxForKey setObject:reportValue forKey:key];
        } else {
            if ([reportValue compare:[self.minForKey objectForKey:key]] == NSOrderedAscending) {
              //  DLog(@"report value %@ < %@ self.minForKey", reportValue, [self.minForKey objectForKey:key]);
                [self.minForKey setObject:reportValue forKey:key];
            }
            if ([reportValue compare:[self.maxForKey objectForKey:key]] == NSOrderedDescending) {
             //   DLog(@"report value %@ > %@ maxForkey", reportValue, [maxForKey objectForKey:key]);
                [self.maxForKey setObject:reportValue forKey:key];
            }
        }
    }
}

- (NSDecimalNumber *) rangeForKey:(NSString *)key {
    if ([self.minForKey objectForKey:key] == nil) {
        return [NSDecimalNumber notANumber];
    }
    return [[self.maxForKey objectForKey:key] decimalNumberBySubtracting:[self.minForKey objectForKey:key]];
}
    
- (NSDecimalNumber *) minForKey:(NSString *)key {
    return [self.minForKey objectForKey:key];
}

- (NSDecimalNumber *) maxForKey:(NSString *)key {
    return [self.maxForKey objectForKey:key];
}



@end
