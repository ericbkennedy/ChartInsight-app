
// This class holds fundamental metrics for a company as arrays of objects
//      date (in separate year, month, day) arrays
//      value (NSDecimalNumber)
//      fiscal quarter (to handle companies that shift fiscal years like GS or RIMM)
//      a dictionary of columns where the key is the metric id (e.g. ReturnOnInvestedCapital) and the value is an array of values over time

// Since the data comes from company reports, all of the data will align on the same dates and it makes sense to request all of the data available without a time frame.
// So unlike the DataAPI, the FundamentalAPI will be called just once until StockData is reloaded (e.g. new fundamental data points are added, or the way they are displayed changes).

// Adding or removing a fundamental type simply means adding a new key-value pair to the dictionary of columns.

@class Stock; // forward declare to avoid circular header inclusion

@interface FundamentalAPI : NSObject
NS_ASSUME_NONNULL_BEGIN
@property (nonatomic, assign) NSInteger reportTypes;                        // width of reportValues multidimensional array
@property (nonatomic, assign) NSInteger oldestReportInView;
@property (nonatomic, assign) NSInteger newestReportInView;
@property (nonatomic, assign) NSInteger stockId;
@property (nonatomic, assign, nullable) id delegate;
@property (strong, nonatomic) NSMutableArray<NSNumber *> *year;
@property (strong, nonatomic) NSMutableArray<NSNumber *> *month;
@property (strong, nonatomic) NSMutableArray<NSNumber *> *day;
@property (strong, nonatomic) NSMutableArray<NSNumber *> *quarter;
@property (strong, nonatomic) NSMutableArray<NSNumber *> *barAlignments;
@property (strong, nonatomic) NSMutableDictionary<NSString *, NSArray *> *columns;

- (void) getFundamentalsForStock:(Stock *)stock withDelegate:(id)caller;

/* Returns nil if no reports for this key */
- (nullable NSDecimalNumber *) valueForReport:(NSInteger)r withKey:(NSString *)key;

/// Sets the mapping between the bars on the stock chart and the quarterly report bars above it
- (void) setBarAlignment:(NSInteger)b forReport:(NSInteger)r;

- (NSInteger) barAlignmentForReport:(NSInteger)r;

NS_ASSUME_NONNULL_END
@end
