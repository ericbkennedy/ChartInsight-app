#import "CIAppDelegate.h"
#import "Comparison.h"
#import "Stock.h"
#import "sqlite3.h"

@implementation Comparison

- (instancetype) init {
    self = [super init];
    [self setStockList:[NSMutableArray arrayWithCapacity:4]];
    return self;
}

+ (NSMutableArray *) listAll:(NSString *)myDbPath {
        
    typedef NS_ENUM(NSInteger, ListAllColumnIndex) {
        ListAllColumnComparisonId,
        ListAllColumnComparisonStockId,
        ListAllColumnStockId,
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
        return [NSMutableArray array];  // To avoid optionals, return an empty array instead of nil
    }
        
	sqlite3_stmt *statement;
    
    if (sqlite3_prepare_v2(db, "SELECT K.rowid, CS.rowid, stockId, symbol, startDate, hasFundamentals, chartType, daysAgo, color, fundamentals, technicals FROM comparison K JOIN comparisonStock CS on K.rowid = CS.comparisonId JOIN stock ON stock.rowid = stockId ORDER BY K.rowid, CS.rowId", -1, &statement, NULL) != SQLITE_OK)
    {
        DLog(@"new SQL failed");
    }
	
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:25];	
    Stock *stock;
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
        
        stock = [[Stock alloc] init];
        stock.comparisonStockId = sqlite3_column_int(statement, ListAllColumnComparisonStockId);
        stock.id = sqlite3_column_int(statement, ListAllColumnStockId);
                              
        [stock setSymbol:[NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, ListAllColumnSymbol)]];
        
       // DLog(@"symbol is %@", [stock symbol]);
        
        title = [title stringByAppendingFormat:@"%@ ", stock.symbol];

        stock.startDateString = [NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, ListAllColumnStartDate)];
        // startDateString will be converted to NSDate by [StockData init] as price data is loaded
        
        stock.hasFundamentals = sqlite3_column_int(statement, ListAllColumnHasFundamentals);
        
        stock.chartType = sqlite3_column_int(statement, ListAllColumnChartType);
        stock.daysAgo = sqlite3_column_int(statement, ListAllColumnDaysAgo);
        
        if (sqlite3_column_bytes(statement, ListAllColumnColor) > 2) {
            [stock setColorWithHexString:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, ListAllColumnColor)]];
        } else {
            [stock setColorWithHexString:@"009900"];   // green (and by convention, red)
        }
                
        if (sqlite3_column_bytes(statement, ListAllColumnFundamentalList) > 2) {
            const char *fundamentals = (const char *)sqlite3_column_text(statement, ListAllColumnFundamentalList);
            [stock setFundamentalList:[NSString stringWithUTF8String:fundamentals]];
        }
        
        if (sqlite3_column_bytes(statement, ListAllColumnTechnicalList) > 2) {
            const char *technicals = (const char *)sqlite3_column_text(statement, ListAllColumnTechnicalList);
            [stock setTechnicalList:[NSString stringWithUTF8String:technicals]];
        }
        
        [comparison.stockList addObject:stock];
        [comparison setTitle:title];
        [stock release];

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
       // DLog(@"comparisonId is %d so insertSQL to get an id for each comparisonStock", id);
        sqlite3_prepare_v2(db, "INSERT INTO comparison (sort) VALUES (0)", -1, &statement, NULL);
        sqlite3_step(statement);
        sqlite3_finalize(statement);
        NSInteger insertedRowid = (NSInteger) sqlite3_last_insert_rowid(db);    // cast to NSInteger since we don't support billions of comparisons...
        [self setId:insertedRowid];
    }
        
    for (NSInteger i = 0; i < self.stockList.count; i++) {
        Stock *stock = [self.stockList objectAtIndex:i];

        if (stock.comparisonStockId > 0) {
            sqlite3_prepare(db, "UPDATE comparisonStock SET daysAgo = ?, chartType = ?, color = ?, fundamentals = ?, technicals = ? WHERE rowid = ?", -1, &statement, NULL);
   
            sqlite3_bind_int64(statement, 1, stock.daysAgo);
            sqlite3_bind_int64(statement, 2, stock.chartType);
            sqlite3_bind_text(statement, 3, [[stock hexFromColor] UTF8String], 6, SQLITE_STATIC); // STATIC = don't free space
            sqlite3_bind_text(statement, 4, [[stock fundamentalList] UTF8String], (int)[stock fundamentalList].length, SQLITE_STATIC);
            sqlite3_bind_text(statement, 5, [[stock technicalList] UTF8String], (int)[stock technicalList].length, SQLITE_STATIC);
            sqlite3_bind_int64(statement, 6, stock.comparisonStockId);

            if(sqlite3_step(statement)==SQLITE_DONE){
          //      // DLog(@"updated %d to DB for comparison id %d", stock.comparisonStockId, [self id]);
            } else {
          //      // DLog(@"DB ERROR '%s'.", sqlite3_errmsg(db));
            }
            sqlite3_finalize(statement);
        } else if (stock.comparisonStockId == 0) {
            
            sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO comparisonStock (comparisonId, stockId, daysAgo, chartType, color, fundamentals, technicals) VALUES (?, ?, ?, ?, ?, ?, ?)", -1, &statement, NULL);
            
            sqlite3_bind_int64(statement, 1, [self id]);
            sqlite3_bind_int64(statement, 2, stock.id);
            sqlite3_bind_int64(statement, 3, stock.daysAgo);
            sqlite3_bind_int64(statement, 4, stock.chartType);
            sqlite3_bind_text(statement, 5, [[stock hexFromColor] UTF8String], 6, SQLITE_STATIC); // STATIC = don't free space
            sqlite3_bind_text(statement, 6, [[stock fundamentalList] UTF8String], (int)[stock fundamentalList].length, SQLITE_STATIC);
            sqlite3_bind_text(statement, 7, [[stock technicalList] UTF8String], (int)[stock technicalList].length, SQLITE_STATIC);

            if(sqlite3_step(statement)==SQLITE_DONE){
                stock.comparisonStockId = (NSInteger) sqlite3_last_insert_rowid(db);

             //   DLog(@"inserted into DB as CSID %d for comparison id %d", stock.comparisonStockId, [self id]);
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
    
    if (sqlite3_prepare_v2(db, "DELETE FROM comparisonStock WHERE comparisonId =  ?", -1, &statement, NULL) == SQLITE_OK) {
        
        sqlite3_bind_int64(statement, 1, self.id);
        if(sqlite3_step(statement) != SQLITE_DONE){;
            DLog(@"Delete comparisonStock DB ERROR '%s'.", sqlite3_errmsg(db));
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


//- (void) deleteComparisonStockAtIndex:(NSInteger)index {
//
//    if (index >= [self.stockList count]) { // index out of bounds
//        return;
//    }
//
//    Stock *s = [self.stockList objectAtIndex:index];
//
//    [self deleteStock:s];
//}

- (void) deleteStock:(Stock *)s {
    
    sqlite3 *db;
    if (sqlite3_open_v2([[NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) != SQLITE_OK) {
        return;
    }
    
    sqlite3_stmt *statement;
    
    if (sqlite3_prepare_v2(db, "DELETE FROM comparisonStock WHERE stockId=?", -1, &statement, NULL) == SQLITE_OK) {
        
        sqlite3_bind_int64(statement, 1, s.id);    // for comparisonStock table
        
        if(sqlite3_step(statement) == SQLITE_DONE){;
            [self.stockList removeObject:s];
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

// Count of superset of all keys for all subcharts excluding book value per share, which is an overlay
- (NSArray *) sparklineKeys {

    NSString *keyStrings = @"";
    
    for (Stock *stock in self.stockList) {
        keyStrings = [keyStrings stringByAppendingString:stock.fundamentalList];
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

- (void) updateMinMaxForKey:(nullable NSString *)key withValue:(nullable NSDecimalNumber *)reportValue {
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

- (nonnull NSDecimalNumber *) rangeForKey:(nullable NSString *)key {
    if ([self.minForKey objectForKey:key] == nil) {
        return [NSDecimalNumber notANumber];
    }
    return [[self.maxForKey objectForKey:key] decimalNumberBySubtracting:[self.minForKey objectForKey:key]];
}
    
- (nullable NSDecimalNumber *) minForKey:(nullable NSString *)key {
    return [self.minForKey objectForKey:key];
}

- (nullable NSDecimalNumber *) maxForKey:(nullable NSString *)key {
    return [self.maxForKey objectForKey:key];
}



@end
