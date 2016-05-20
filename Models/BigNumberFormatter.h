
@interface BigNumberFormatter : NSNumberFormatter

-(NSString *)formatFinancial:(NSDecimalNumber*)number withXfactor:(CGFloat)xFactor;

@end

