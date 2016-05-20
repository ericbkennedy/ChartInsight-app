
// This class holds fundamental metrics for a company as arrays of objects
//      date (in separate year, month, day) arrays
//      value (NSDecimalNumber)
//      fiscal quarter (to handle companies that shift fiscal years like GS or RIMM)
//      a dictionary of columns where the key is the metric id (e.g. ReturnOnInvestedCapital) and the value is an array of values over time

// Since the data comes from company reports, all of the data will align on the same dates and it makes sense to request all of the data available without a time frame.
// So unlike the DataAPI, the FundamentalAPI will be called just once until StockData is reloaded (e.g. new fundamental data points are added, or the way they are displayed changes).

// Adding or removing a fundamental type simply means adding a new key-value pair to the dictionary of columns.

// For cleaner code, the CBarStruct will have a pointer to an NSArray of NSDecimalNumbers.
// That allows arbitrarily many fundamental series and improves the speed of computeChart since only the BarData needs to be incremented.

@class Series; // forward declare to avoid circular header inclusion

@interface FundamentalAPI : NSObject
@property (nonatomic, assign) NSInteger reportTypes;                        // width of reportValues multidimensional array
@property (nonatomic, assign) NSInteger oldestReportInView;
@property (nonatomic, assign) NSInteger newestReportInView;
@property (nonatomic, assign) NSInteger seriesId;
@property (nonatomic, assign) id delegate;
@property (strong, nonatomic) NSMutableArray *year;
@property (strong, nonatomic) NSMutableArray *month;
@property (strong, nonatomic) NSMutableArray *day;
@property (strong, nonatomic) NSMutableArray *quarter;
@property (strong, nonatomic) NSMutableArray *barAlignments;
@property (strong, nonatomic) NSMutableDictionary *columns;

- (void) getFundamentalsForSeries:(Series *)series withDelegate:(id)caller;

/* Returns nil if no reports for this key */
- (NSDecimalNumber *) valueForReport:(NSInteger)r withKey:(NSString *)key;

- (void) setBarAlignment:(NSInteger)b forReport:(NSInteger)r;

- (NSInteger) barAlignmentForReport:(NSInteger)r;

@end
