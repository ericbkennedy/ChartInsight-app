
@class Stock;

@interface Stock : NSObject

@property (nonatomic) NSInteger id;
@property (nonatomic) NSInteger chartType;
@property (nonatomic) NSInteger comparisonStockId;
@property (nonatomic) NSInteger hasFundamentals;
@property (nonatomic) CGColorRef color;
@property (nonatomic) CGColorRef colorHalfAlpha;
@property (nonatomic) CGColorRef colorInverse;
@property (nonatomic) CGColorRef colorInverseHalfAlpha;
@property (nonatomic) CGColorRef upColor;
@property (nonatomic) CGColorRef upColorHalfAlpha;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fundamentalList;
@property (nonatomic, copy) NSString *technicalList;
@property (nonatomic, copy) NSString *startDateString; // searches return a string to convert to date later
@property (nonatomic, copy) NSDate *startDate;


+ (NSArray<Stock *> *) findStock:(NSString *)search;

- (void) addToFundamentals:(NSString *)type;
- (void) addToTechnicals:(NSString *)type;
- (void) removeFromFundamentals:(NSString *)type;
- (void) removeFromTechnicals:(NSString *)type;

- (void) convertDateStringToDateWithFormatter:(NSDateFormatter *)formatter;

- (void) setColorWithHexString:(NSString *) stringToConvert;

- (void) setColor:(CGColorRef)c;
- (void) setUpColor:(CGColorRef)uc;

- (NSString *) hexFromColor;

- (BOOL) matchesColor:(UIColor *)theirColor;

@end
