NS_ASSUME_NONNULL_BEGIN

@class Stock; // forward declare to avoid circular header inclusion

@class Comparison;

@interface Comparison : NSObject
@property (nonatomic) NSInteger id;
@property (strong, nonatomic) NSMutableArray<Stock *> *stockList;
@property (strong, nonatomic) NSString *title;
@property (strong, nonatomic) NSMutableDictionary<NSString *, NSDecimalNumber *> *minForKey;
@property (strong, nonatomic) NSMutableDictionary<NSString *, NSDecimalNumber *> *maxForKey;

+ (NSMutableArray *) listAll:(NSString *)myDbPath;

- (void) saveToDb;

- (void) deleteFromDb;      // deletes comparison row and all comparisonStock rows

- (void) deleteStock:(Stock *)s;

// EK: unused? - (void) deleteComparisonStockAtIndex:(NSInteger)index;

- (NSArray *) chartTypes; // array referenced from CIAppDelegate but this makes lookups cleaner

// count of superset of all keys for all subcharts excluding book value per share, which is an overlay
- (NSArray *) sparklineKeys;

- (void) resetMinMax;

- (void) updateMinMaxForKey:(nullable NSString *)key withValue:(nullable NSDecimalNumber *)reportValue;

// returns [NSDecimalNumber notANumber] if key == nil
- (NSDecimalNumber *) rangeForKey:(nullable NSString *)key;
- (nullable NSDecimalNumber *) minForKey:(nullable NSString *)key;
- (nullable NSDecimalNumber *) maxForKey:(nullable NSString *)key;

NS_ASSUME_NONNULL_END
@end
