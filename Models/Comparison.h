
@class Series; // forward declare to avoid circular header inclusion

@class Comparison;

@interface Comparison : NSObject
@property (nonatomic) NSInteger id;
@property (strong, nonatomic) NSMutableArray *seriesList;
@property (strong, nonatomic) NSString *title;
@property (strong, nonatomic) NSMutableDictionary *minForKey;   // contains NSDecimalNumbers
@property (strong, nonatomic) NSMutableDictionary *maxForKey;   // contains NSDecimalNumbers

+ (NSMutableArray *) listAll:(NSString *)myDbPath;

- (void) saveToDb;

- (void) deleteFromDb;      // deletes comparison row and all comparisonSeries rows

- (void) deleteSeries:(Series *)s;

- (void) deleteComparisonSeriesAtIndex:(NSInteger)index;

- (NSArray *)chartTypes; // array referenced from AppDelegate but this makes lookups cleaner

- (BOOL) showDialGrips;

// count of superset of all keys for all subcharts excluding book value per share, which is an overlay
- (NSArray *) sparklineKeys;

- (void) resetMinMax;

- (void) updateMinMaxForKey:(NSString *)key withValue:(NSDecimalNumber *)reportValue;

- (NSDecimalNumber *) rangeForKey:(NSString *)key;
- (NSDecimalNumber *) minForKey:(NSString *)key;
- (NSDecimalNumber *) maxForKey:(NSString *)key;


@end
