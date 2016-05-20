#include "BigNumberFormatter.h"

@interface BigNumberFormatter ()
@property (nonatomic, strong) NSDecimalNumber *billion;
@property (nonatomic, strong) NSDecimalNumber *million;
@property (nonatomic, strong) NSDecimalNumber *negativeOne;
@end

@implementation BigNumberFormatter

- (id) init {
    self = [super init];
    [self setBillion:[[NSDecimalNumber alloc] initWithMantissa:1 exponent:9 isNegative:NO]];
    [self setMillion:[[NSDecimalNumber alloc] initWithMantissa:1 exponent:6 isNegative:NO]];
    [self setNegativeOne:[[NSDecimalNumber alloc] initWithMantissa:1 exponent:0 isNegative:YES]];
    [self setZeroSymbol:@"0.00"];
    return self;
}

- (void) dealloc {
    [_billion release];
    [_million release];
    [_negativeOne release];
    [super dealloc];
}

- (NSString *)formatFinancial:(NSDecimalNumber*)number withXfactor:(CGFloat)xFactor {

    NSString *negative = @"";
    
    if ([number compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
        number = [number decimalNumberByMultiplyingBy:self.negativeOne];
        negative = @"-";
    }
    
    if ([number compare:self.million] == NSOrderedAscending) {
        [self setMaximumFractionDigits: 2];
        return [NSString stringWithFormat:@"%@%@", negative, [super stringFromNumber:number]];
    } else if ([number compare:self.billion] == NSOrderedAscending) {
        NSDecimalNumber *inMillions = [number decimalNumberByDividingBy:self.million];
        if (([inMillions doubleValue] > 10 && xFactor < 2) || [inMillions doubleValue] > 100) {
            [self setMaximumFractionDigits:0];
        } else {
            [self setMaximumFractionDigits:1];
        }
        return [NSString stringWithFormat:@"%@%@M", negative, [super stringFromNumber:inMillions]];
    }   
    NSDecimalNumber *inBillions = [number decimalNumberByDividingBy:self.billion];
    if ([inBillions doubleValue] > 100) {
        [self setMaximumFractionDigits:0];
    } else {
        [self setMaximumFractionDigits:1];
    }
    return [NSString stringWithFormat:@"%@%@B", negative, [super stringFromNumber:[number decimalNumberByDividingBy:self.billion]]];
}
@end
