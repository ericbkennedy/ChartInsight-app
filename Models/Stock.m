#import "Stock.h"
#include <CoreGraphics/CGColor.h>

@implementation Stock

- (void) setColor:(CGColorRef)c {
    _color = c;
    _colorHalfAlpha = CGColorCreateCopyWithAlpha(c, .5);
}

- (void) setUpColor:(CGColorRef)uc {
    _upColor = uc;
    _upColorHalfAlpha = CGColorCreateCopyWithAlpha(uc, .5);
    
    const CGFloat *components = CGColorGetComponents(_upColor);

    _colorInverse = [[UIColor alloc] initWithRed:(1.0 - components[0])
                                               green:(1.0 - components[1])
                                                blue:(1.0 - components[2])
                                               alpha:components[3]].CGColor;
    
    _colorInverseHalfAlpha = CGColorCreateCopyWithAlpha(_colorInverse, .75);
}

- (void) setColorWithHexString:(NSString *) stringToConvert {

//    // DLog(@"%@ hex loaded %@", symbol, stringToConvert);
    
    NSScanner *scanner = [NSScanner scannerWithString:stringToConvert];
    unsigned hex;
    NSInteger r = 0, g = 0, b = 0;
    if ([scanner scanHexInt:&hex]) {        // returns black if no match
        r = (hex >> 16) & 0xFF;
        g = (hex >> 8) & 0xFF;
        b = (hex) & 0xFF;
    }
    CGFloat components[4] = {r / 255.0f, g / 255.0f, b / 255.0f, 1.0f};
    
    CGColorSpaceRef deviceRGB = CGColorSpaceCreateDeviceRGB();
    CGColorRef colorRef = CGColorCreate(deviceRGB, components);
    [self setColor:colorRef];
    [self setUpColor:colorRef];
    CGColorSpaceRelease(deviceRGB);
    
    if (self.chartType < 3) {
        if (r == 0 && b == 0) {
            [self setColor:[UIColor redColor].CGColor];
        }
    }
}

- (BOOL) matchesColor:(UIColor *)theirColor {
    
    NSString *currentColorHex = [self hexFromColor];
    NSString *theirColorHex = [self hexFromColor:theirColor.CGColor];
    
    return [currentColorHex isEqualToString: theirColorHex];
}

- (NSString *) hexFromColor {
    return [self hexFromColor:self.upColor];
}

- (NSString *) hexFromColor:(CGColorRef)color {
    
    const CGFloat *components = CGColorGetComponents(color);
    unsigned r, g, b;
    
    r = 255 * components[0];
    g = 255 * components[1];
    b = 255 * components[2];
    
    unsigned hex;
    
    hex = (r << 16) + (g << 8) + b;
    
   // DLog(@"hex is %06x", hex);
    
    return [NSString stringWithFormat:@"%06x", hex];
}

- (void) addToFundamentals:(NSString *)type {

    if ([self.fundamentalList rangeOfString:type].length > 0) {
       // DLog(@"%@ is already in %@", type, self.fundamentalList);
    } else {
//        // DLog(@"%@ is NOT in %@ so adding", type, self.fundamentalList);
        [self setFundamentalList:[self.fundamentalList stringByAppendingFormat:@"%@,", type]];
    }
}

- (void) removeFromFundamentals:(NSString *)type {
    
    if ([self.fundamentalList rangeOfString:type].length > 0) {
    //    // DLog(@"removing %@ from %@", type, self.fundamentalList);
        [self setFundamentalList:[self.fundamentalList stringByReplacingOccurrencesOfString:type withString:@""]];
    }
    while ([self.fundamentalList rangeOfString:@",,"].length > 0) {
        [self setFundamentalList:[self.fundamentalList stringByReplacingOccurrencesOfString:@",," withString:@","]];
    }
}

- (void) addToTechnicals:(NSString *)type {
    
    if ([self.technicalList rangeOfString:type].length > 0) {
       // DLog(@"%@ is already in %@", type, self.technicalList);
    } else {
       // DLog(@"%@ is NOT in %@ so adding", type, self.technicalList);
        [self setTechnicalList:[self.technicalList stringByAppendingFormat:@"%@,", type]];
    }
}


- (void) removeFromTechnicals:(NSString *)type {
    
    if ([self.technicalList rangeOfString:type].length > 0) {
        [self setTechnicalList:[self.technicalList stringByReplacingOccurrencesOfString:type withString:@""]];
    }
    while ([self.technicalList rangeOfString:@",,"].length > 0) {
        [self setTechnicalList:[self.technicalList stringByReplacingOccurrencesOfString:@",," withString:@","]];
    }
}

- (Stock *) init {
    self = [super init];
    self.id = 0;
    self.comparisonStockId = 0;
    self.hasFundamentals = 0;
    self.chartType = 2; // Candle
    
    if ([[NSUserDefaults standardUserDefaults] valueForKey:@"chartTypeDefault"]) {
        if ([[NSUserDefaults standardUserDefaults] integerForKey:@"chartTypeDefault"] != self.chartType) {
            self.chartType = [[NSUserDefaults standardUserDefaults] integerForKey:@"chartTypeDefault"];
        }
    }
    
    NSString *technicalDefaults, *fundamentalDefaults = @"";
    if ([[[NSUserDefaults standardUserDefaults] valueForKey:@"technicalDefaults"] length] > 1) {
        technicalDefaults = [[NSUserDefaults standardUserDefaults] valueForKey:@"technicalDefaults"];
    } else {
        technicalDefaults = @"sma200,bb20,";
    }

    if ([[[NSUserDefaults standardUserDefaults] valueForKey:@"fundamentalDefaults"] length] > 1) {
        fundamentalDefaults = [[NSUserDefaults standardUserDefaults] valueForKey:@"fundamentalDefaults"];
    }
    
    [self setFundamentalList:fundamentalDefaults];
    [self setTechnicalList:technicalDefaults];
    return self;
}

@end
