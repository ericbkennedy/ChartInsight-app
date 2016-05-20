#import "MoveDB.h"
#import "sqlite3.h"
#import "Comparison.h"

#define CURRENT_DB_VERSION 5

@interface MoveDB ()
@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, nonatomic) NSMutableData *receivedData;
@property (strong, nonatomic) NSString *responseString;
@end
@implementation MoveDB

- (NSString *) dbPath {
    return [NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()];		
}

- (void) checkExistingDB {
     
    sqlite3 *db;
 	sqlite3_stmt *statement;   
    
    assert(sqlite3_open_v2([[self dbPath] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) == SQLITE_OK);
 
    NSInteger dbVersion = 0;
    NSInteger retVal = sqlite3_prepare_v2(db, "SELECT value FROM config WHERE key='version'", -1, &statement, NULL);
    
    if (retVal == SQLITE_OK && sqlite3_step(statement)==SQLITE_ROW) {
    
        dbVersion = sqlite3_column_int(statement, 0);
        
        sqlite3_finalize(statement);
        sqlite3_close(db);
    }
       
    if (dbVersion == CURRENT_DB_VERSION) {
        return;

    } else {
     
        NSMutableArray *migrations = [NSMutableArray arrayWithCapacity:5];         
        
        [migrations addObject:@"CREATE TABLE comparisonSeries (comparisonId INTEGER, seriesId INTEGER, daysAgo INTEGER, chartType INTEGER, color TEXT, fundamentals TEXT, technicals TEXT)"];
        
        if (dbVersion < 1) {  
            [migrations addObject:@"insert into comparisonSeries (comparisonId, seriesId, daysAgo, chartType, color) SELECT K.rowid, aId, aDaysAgo, 2, '00ff00' FROM comparison K JOIN series S on S.rowid = aId where aId > 0"];
            [migrations addObject:@"insert into comparisonSeries (comparisonId, seriesId, daysAgo, chartType, color) SELECT K.rowid, bId, bDaysAgo, 0, 'ffffff' FROM comparison K JOIN series S on S.rowid = bId where bId > 0"];

        } else if (dbVersion == 1) {
            [migrations addObject:@"insert into comparisonSeries (comparisonId, seriesId, daysAgo, chartType, color) SELECT rowid, aId, aDaysAgo, aChartType, aColor FROM comparison where aId > 0"];
            [migrations addObject:@"insert into comparisonSeries (comparisonId, seriesId, daysAgo, chartType, color) SELECT rowid, bId, bDaysAgo, bChartType, bColor FROM comparison where bId > 0"];
            [migrations addObject:@"insert into comparisonSeries (comparisonId, seriesId, daysAgo, chartType, color) SELECT rowid, cId, cDaysAgo, cChartType, cColor FROM comparison where cId > 0"];

        } else if (dbVersion == 2) {    // has incomplete intraday data saved to DB
            [migrations addObject:@"DELETE from history where date > 20120701"];
        } else if (dbVersion < 5) {
            [migrations addObject:@"UPDATE comparisonSeries set color='009900' where color = '00ff00'"];    // darker green
            [migrations addObject:@"UPDATE comparisonSeries set color='009900' where color = '00b200'"];    // darker green
            [migrations addObject:@"UPDATE comparisonSeries set color='0099ff' where color = '00b2ff'"];    // light blue
            [migrations addObject:@"UPDATE comparisonSeries set color='ffcc00' where color = 'ffff00'"];    // darker yellow
            [migrations addObject:@"UPDATE comparisonSeries set color='999999' where color = 'ffffff'"];    // gray instead of white
            [migrations addObject:@"UPDATE comparisonSeries set color='999999' where color = '7f7f7f'"];    // gray instead of white            
        }
        
        assert(sqlite3_open_v2([[self dbPath] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) == SQLITE_OK);

        for (NSString *query in migrations) {
            
            if(sqlite3_prepare_v2(db, [query UTF8String], -1, &statement, NULL) == SQLITE_OK) {
                
                if(sqlite3_step(statement)==SQLITE_DONE){
                    DLog(@"Completed DB migration %@", query);
                } else {
                    NSLog(@"DB ERROR '%s'.", sqlite3_errmsg(db));
                }
            }
        }
        sqlite3_finalize(statement);
        sqlite3_close(db);
        
        if (dbVersion < 2) {    // need to copy comparisons from old DB before overwriting

            NSMutableArray *oldComparisonList = [NSMutableArray arrayWithCapacity:10];
            
            // use two separate try/catch blocks so if listAll has an exception for bad user data, 
            // we still copy a fresh database as required
            
            @try {
                oldComparisonList = [[Comparison listAll:[self dbPath]] retain];
            }
            @catch (NSException *e) {
           //   DLog(@"Exception: %@", e);  
            }
            
            @try {
                NSFileManager *fileManager = [[NSFileManager alloc] init];
                [fileManager removeItemAtPath:[self dbPath] error:NULL];
                [fileManager copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"charts.db" ofType:nil] toPath:[self dbPath] error:NULL];            
                [fileManager release];
            }
            @catch (NSException *e) {
                NSLog(@"Exception: %@", e);
            }
            
           // DLog(@"old comparison list has %d count", oldComparisonList.count);
            
            for (NSInteger i = 0; i < [oldComparisonList count]; i++) {
                
                Comparison *oldComparison = [oldComparisonList objectAtIndex:i];
                [oldComparison setId:0]; // forces it to use insert
                [oldComparison saveToDb];
            }
        }
        
        assert(sqlite3_open_v2([[self dbPath] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) == SQLITE_OK);
        sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO config (key,value) VALUES ('version',?)", -1, &statement, NULL);
        sqlite3_bind_int64(statement, 1, CURRENT_DB_VERSION);
        sqlite3_step(statement);
        sqlite3_finalize(statement);
        sqlite3_close(db);
    } 
}

/* Check the last update date, request changes since then, and update the DB with those values 
 
 The trick is that the feedback date isn't something the iPhone can calculate because I only download
 new lists of symbols once a month
 
 So the request values should be
 
 1. empty string
 2. max updated date as returned by server
 3. old max updated date as returned by server
 
 Also note that it must be stored in the database so we know not to download any updates that are already in the current DB
 
 */
- (void) syncSeriesChanges {

    sqlite3 *db;
 	sqlite3_stmt *statement;
    sqlite3_open_v2([[self dbPath] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL);
    
//    NSString *lastModified =@"2012-06-13";
//    sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO config (key,value) VALUES ('seriesSync',?)", -1, &statement, NULL);
//    sqlite3_bind_text(statement, 1, lastModified.UTF8String, lastModified.length, SQLITE_STATIC); // don't free space
//    sqlite3_step(statement);
//    sqlite3_finalize(statement);
    
    NSInteger retVal = sqlite3_prepare_v2(db, "SELECT value FROM config WHERE key='seriesSync'", -1, &statement, NULL);       //   e.g.  '2012-10-16'
    
    NSString *syncURL = @"http://chartinsight.com/getSeriesChanges.php?modified=";
    
    if (retVal == SQLITE_OK && sqlite3_step(statement)==SQLITE_ROW) {
        
        if (sqlite3_column_bytes(statement, 0) > 2) {
           syncURL = [syncURL stringByAppendingString:[NSString stringWithUTF8String:(const char *) sqlite3_column_text(statement, 0)]];
        }
    }
    sqlite3_finalize(statement);
    sqlite3_close(db);
    
    // DLog(@"syncURL is %@", syncURL);
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:syncURL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60.0];
    
    self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
    if (self.connection) {
        [self setReceivedData:[NSMutableData data]];       // initialize it
    } else {
        // DLog(@"download couldn't be started");
    }
}

- (void) parseResponse {
    
    NSLog(@"response is %@", self.responseString);
    
    
    if (self.responseString.length < 10) {
          DLog(@"no need to update");
        return;
    } else if ([[self.responseString substringToIndex:56] isEqualToString:@"id	status	symbol	startDate	modified	hasFundamentals	name"] == NO) {
         DLog(@"mismatch so failed");
        return;
    }
    sqlite3 *db;
 	sqlite3_stmt *statement;
    sqlite3_open_v2([[self dbPath] UTF8String], &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL);
  
    NSArray *lines = [self.responseString componentsSeparatedByString:@"\n"];
    NSInteger seriesId, status, startDate, hasFundamentals;
    NSString *symbol, *name, *lastModified = @"";
    
    for (NSInteger l = 1; l < lines.count; l++) {
        NSArray *parts = [[lines objectAtIndex:l] componentsSeparatedByString:@"\t"];
        if (parts.count >= 6) {
            seriesId = [[parts objectAtIndex:0] integerValue];
            status = [[parts objectAtIndex:1] integerValue];
            symbol = [parts objectAtIndex:2];
            startDate = [[parts objectAtIndex:3] integerValue];
            lastModified = [parts objectAtIndex:4];
            hasFundamentals = [[parts objectAtIndex:5] integerValue];
            name = [parts objectAtIndex:6];
            
            if (status == 0) {
                 // DLog(@"delete from database %d %@", seriesId, symbol);
                sqlite3_prepare(db, "DELETE FROM series WHERE rowid =?", -1, &statement, NULL);
                sqlite3_bind_int64(statement, 1, seriesId);
                sqlite3_step(statement);
                sqlite3_finalize(statement);
                
                sqlite3_prepare(db, "DELETE FROM comparisonSeries WHERE seriesId =?", -1, &statement, NULL);
                sqlite3_bind_int64(statement, 1, seriesId);
                
            } else if (status == 2) {
                // DLog(@"update id %d to %@ %d %@", seriesId, symbol, startDate, name);
                sqlite3_prepare(db, "UPDATE series SET symbol=?,startDate=?,hasFundamentals=?,name=? WHERE rowid =?", -1, &statement, NULL);
                sqlite3_bind_text(statement, 1, symbol.UTF8String, (int)symbol.length, SQLITE_STATIC); // STATIC = don't free space
                sqlite3_bind_int64(statement, 2, startDate);
                sqlite3_bind_int64(statement, 3, hasFundamentals);
                sqlite3_bind_text(statement, 4, name.UTF8String, (int)name.length, SQLITE_STATIC); // STATIC = don't free space
                sqlite3_bind_int64(statement, 5, seriesId);
                
            } else if (status == 1) {    // new stocks
                // DLog(@"insert id %d to %@ %d %@", seriesId, symbol, startDate, name);
                
                sqlite3_prepare(db, "INSERT OR IGNORE INTO series (rowid,symbol,startDate,hasFundamentals,name) VALUES (?, ?, ?, ?, ?)", -1, &statement, NULL);
                sqlite3_bind_int64(statement, 1, seriesId);
                sqlite3_bind_text(statement, 2, symbol.UTF8String, (int)symbol.length, SQLITE_STATIC); // STATIC = don't free space
                sqlite3_bind_int64(statement, 3, startDate);
                sqlite3_bind_int64(statement, 4, hasFundamentals);
                sqlite3_bind_text(statement, 5, name.UTF8String, (int)name.length, SQLITE_STATIC); // STATIC = don't free space
            } else if (status == 3) {
                DLog(@"delete HISTORY from database %ld %@", (long)seriesId, symbol);
                sqlite3_prepare(db, "DELETE FROM history WHERE series =?", -1, &statement, NULL);
                sqlite3_bind_int64(statement, 1, seriesId);
                
            } else {        // don't cause old version to crash if a newer status is added
                continue;
            }
            
            if(sqlite3_step(statement)==SQLITE_DONE) {
                // DLog(@"updated %d in DB", seriesId);
            } else {
                // DLog(@"DB ERROR '%s'.", sqlite3_errmsg(db));
            }
            sqlite3_finalize(statement);
        }
    }
    // DLog(@"finished sync with lastModified value %@", lastModified);
    
    sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO config (key,value) VALUES ('seriesSync',?)", -1, &statement, NULL);
    sqlite3_bind_text(statement, 1, lastModified.UTF8String, (int)lastModified.length, SQLITE_STATIC); // don't free space
    sqlite3_step(statement);
    sqlite3_finalize(statement);
    sqlite3_close(db);
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.receivedData appendData:data];
}

-(void)connection:(NSURLConnection *)failedConnection didFailWithError:(NSError *)error {
    // DLog(@"syncSeries failed with error %@ %@", [error localizedDescription], [failedConnection description]);
    [self.connection cancel];
    self.receivedData = nil;
    self.connection = nil;
}

-(void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)response {
    // this can be called multiple times (in the case of a redirect), so each time we reset the data.
    
    if ([response respondsToSelector:@selector(statusCode)])  {
        NSInteger statusCode = [((NSHTTPURLResponse *)response) statusCode];
        if (statusCode == 404) {
            [c cancel];  // stop connecting; no more delegate messages
            [self connection:c didFailWithError:nil];
             // DLog(@"syncSeries error with %d", statusCode);
        }
    }
    [self.receivedData setLength:0];
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection {
	self.connection = nil;
    
	NSString *csv = [[NSString alloc] initWithData:self.receivedData encoding:NSUTF8StringEncoding];
    
    [self setResponseString:csv];
    [csv release];
	
    self.receivedData = nil;    // don't release receivedData because iOS manages retain counts
    [self parseResponse];
}

- (void) moveDBforDelegate:(id)delegate {
	
	@try {
		NSString *docPath = [self dbPath];
        
       // DLog(@"Moving DB to %@", docPath);
		
		// Check the existence of database 
		NSFileManager *mngr = [[NSFileManager alloc] init];
		
		// If the database doesn't exist in our Document folder we copy it to Documents (this will be executed only the first time we launch the app)
		if (![mngr fileExistsAtPath:docPath]){
			[mngr copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"charts.db" ofType:nil] toPath:docPath error:NULL];
		} else{
            [self checkExistingDB];
            [self syncSeriesChanges];
        }
		[mngr release];
        
		[delegate performSelectorOnMainThread:@selector(dbMoved:) withObject:docPath waitUntilDone:YES];

    } @catch (NSException * e) {
       // DLog(@"Exception: %@", e);
    }
}


@end
