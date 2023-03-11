
@class Series;

@interface Series : NSObject {
    @public
    NSInteger id;
    NSInteger chartType;
    NSInteger daysAgo;
    NSInteger comparisonSeriesId;
    NSInteger hasFundamentals;
    CGColorRef color;
    CGColorRef colorHalfAlpha;
    CGColorRef colorInverse;
    CGColorRef colorInverseHalfAlpha;
    CGColorRef upColor;
    CGColorRef upColorDarkHalfAlpha;
    CGColorRef upColorHalfAlpha;
}
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fundamentalList;
@property (nonatomic, copy) NSString *technicalList;
@property (nonatomic, copy) NSString *startDateString; // searches return a string to convert to date later
@property (nonatomic, copy) NSDate *startDate;


 + (NSMutableArray *) findSeries:(NSString *)search;

- (void) addToFundamentals:(NSString *)type;
- (void) addToTechnicals:(NSString *)type;
- (void) removeFromFundamentals:(NSString *)type;
- (void) removeFromTechnicals:(NSString *)type;

- (void) convertDateStringToDate;

- (void) setColorWithHexString:(NSString *) stringToConvert;

- (void) setColor:(CGColorRef)c;
- (void) setUpColor:(CGColorRef)uc;

- (NSString *) hexFromColor;

- (BOOL) matchesColor:(UIColor *)theirColor;

@end
