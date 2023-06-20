#import <CoreText/CoreText.h>
#import "ScrollChartView.h"
#import "ChartInsight-Swift.h" // for Stock and BigNumberFormatter
#import "CIAppDelegate.h"
#import "StockData.h"
#import "FundamentalAPI.h"

const CGFloat magnifierSize = 100.; // both width and height
const CGFloat dotPattern[2] = {1.0, 6.0};
const CGFloat dashPattern[2] = {1.0, 1.5};
const CGFloat dotGripColor[4] = {0.5, 0.5, 0.8, 1.0};
const CGFloat lightBlueColor[4] = {0.16, 0.34, 1.0, 1.0};
const CGFloat monthLineColor[4] = {.4, .4, .4, .5};
const CGFloat redMetric[4] = {1., .0, .0, .8};  // needs to be brighter than green

const CGFloat dashPatern[2] =  {1.0,  3.0};

@interface ScrollChartView () <CAAnimationDelegate> {
@private
    CGFloat      _maxWidth, _pxHeight, _scaleShift, _scaledWidth, _sparklineHeight, _svHeight;
    CGLayerRef   _layerRef;
    CGContextRef _layerContext;
    NSInteger    _pressedBarIndex;   // need to track the index so we can compare against the total number of bars
}
@property (strong, nonatomic) NSMutableArray<StockData *> *stocks;
@property (strong, nonatomic) NSDecimalNumber *chartPercentChange;
@property (strong, nonatomic) NSDecimalNumberHandler *roundDown;
@property (strong, nonatomic) BigNumberFormatter *numberFormatter;
@property (strong, nonatomic) NSArray<NSString *> *sparklineKeys;
@property (strong, nonatomic) NSDate *lastNetworkErrorShown;
@end

@implementation ScrollChartView

- (void) dealloc {
    
    for(StockData *stock in self.stocks) {
        [stock release];
    }
    [_stocks release];
    [_numberFormatter release];
    
    CGLayerRelease(_layerRef); 
    [super dealloc];
}

- (void) removeStockAtIndex:(NSInteger)i {

    if (i < self.stocks.count) {
        [self.stocks removeObjectAtIndex:i];
    }
}

- (void) resetDimensions {
    _svHeight = self.bounds.size.height;
    _maxWidth = self.bounds.size.width;
    _scaledWidth = _maxWidth;
    _svWidth = _maxWidth - 5. - self.layer.position.x - (30 * [[self.comparison stockList] count]);
    _pxWidth = self.layer.contentsScale * _svWidth;
    _pxHeight = self.layer.contentsScale * _svHeight;
}

- (NSInteger) maxBarOffset {
    return floor((_pxWidth)/(_xFactor * _barUnit));
}

- (void) createLayerContext {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(_maxWidth, _svHeight), YES, self.layer.contentsScale);
    _layerRef = CGLayerCreateWithContext(UIGraphicsGetCurrentContext(), CGSizeMake(self.layer.contentsScale * _maxWidth, _pxHeight), NULL);
    UIGraphicsEndImageContext();
    _layerContext = CGLayerGetContext(_layerRef);
}

- (instancetype) init {
    if (self = [super init]) {
        _scaleShift = 0.;
        _xFactor = 7.5;
        _barUnit = 1.; // daily
        
        [self.layer setContentsScale:UIScreen.mainScreen.scale];
        self.stocks = [[NSMutableArray alloc] init];
       
        [self setRoundDown:[NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundDown scale:0 raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO]];
        
        BigNumberFormatter *newNumberFormatter = [[BigNumberFormatter alloc] init];
        [self setNumberFormatter:newNumberFormatter];
        [newNumberFormatter release];

        [self setChartPercentChange:[NSDecimalNumber zero]];
        
        [self setLastNetworkErrorShown:[NSDate dateWithTimeIntervalSinceNow:-120.]];    // ensure the first error shows
    }
    return self;
}

- (void) clearChart {
    [self.progressIndicator reset];
    
    CAKeyframeAnimation* animation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    animation.duration = 2.0;
    animation.values = @[ @0.8, @0.5];
    animation.keyTimes = @[ @0.0, @1.0];
    animation.delegate = self;
      
    self.layer.opacity = 0.5;
    [self.layer addAnimation:animation forKey:@"opacity"];
    
    CGContextClearRect(_layerContext, CGRectMake(0, 0, self.layer.contentsScale * _maxWidth, _pxHeight));
    [self setNeedsDisplay];
    
    for (StockData *s in self.stocks) {
        [s invalidateAndCancel];    // ensures StockData, DataAPI and FundamentalAPI get deallocated
    }
    
    [self.stocks removeAllObjects];
}

-(void) redrawCharts {
    for (StockData *s in self.stocks) {
        [s updateLayer: self.chartPercentChange forceRecompute:YES];
    }
    [self renderCharts];
}


/* Called by StockData when saved rows are insuffient */
- (void) showProgressIndicator {
    [self.progressIndicator startAnimating];
}

/* Called by StockData when fundamental API returns before historical API */
- (void) stopProgressIndicator {
    [self.progressIndicator stopAnimating];
}

- (void) loadChart {

    [self setChartPercentChange:[NSDecimalNumber zero]];
    
    [self resetDimensions];     // this IS necessary for first load
    
    [self setSparklineKeys:[self.comparison sparklineKeys]];     // excludes BookValuePerShare
    
    _sparklineHeight = 100 * [self.sparklineKeys count];
    
    for (Stock *stock in self.comparison.stockList) {
        StockData *stockData = [[StockData alloc] init];
        [self.stocks addObject:stockData];
        stockData.stock = stock;
        
        stockData.oldestBarShown = [self maxBarOffset];
        // DLog(@"oldestBarShown %d", stockData.oldestBarShown);
        
        [stockData setDelegate:self];
        [stockData setGregorian:self.gregorian];

        stockData.barUnit = _barUnit;
        stockData.xFactor = _xFactor * _barUnit;
        [stockData setPxHeight:_pxHeight withSparklineHeight:_sparklineHeight];
        [stockData fetchStockData];
    }
}

- (void) renderCharts {

    CGContextClearRect(_layerContext, CGRectMake(0, 0, self.layer.contentsScale * _maxWidth, _pxHeight + 5));
    
    StockData *stockData;

    CGContextSetBlendMode(_layerContext, kCGBlendModeNormal);
    
    UIGraphicsPushContext(_layerContext); // sets the current graphics context in order to showString:atPoint:
    
    NSDecimalNumber *reportValue = [NSDecimalNumber notANumber];    // init for safety
    CGPoint p;
    NSString *label;
    
    NSInteger dateShift = -1;
    
    if (self.stocks.count > 0) {
        stockData = [self.stocks objectAtIndex:0];
        
        dateShift = stockData.oldestBarShown;
        
        CGContextSetStrokeColor(_layerContext, monthLineColor);        
        CGContextSetLineWidth(_layerContext, 1.0);   // in pixels not points
        CGContextStrokeLineSegments(_layerContext, stockData.monthLines, stockData.monthCount);
        
        CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
        
        NSInteger monthLabelIndex = 0;
        CGFloat offset = 10 *  self.layer.contentsScale;
         
        for (NSInteger m = 0; m < stockData.monthCount; m++) {
            m++; // 2nd point is chartbase
            
            p = (CGPoint) stockData.monthLines[m];
            
            monthLabelIndex = floorf(m/2);
            
            if (monthLabelIndex < [[stockData monthLabels] count]) {
                label = [[stockData monthLabels] objectAtIndex:monthLabelIndex];
                [self showString:label atPoint:CGPointMake(p.x, p.y + offset) withColor:stockData.stock.upColor];
            }
        }
    }
    
    // To determine the min and max values for each fundamental metric, first go through all of the stocks
    // and go through their fundamentals, comparing them by key type.
    // Then, if the sparklineCount > 0, go through it again to render the sparklines
    // using a dictionary is preferable because it makes checking for uniqueness and lookups easier
    [self.comparison resetMinMax];
    
    NSInteger stocksWithFundamentals = 0;
    
    for(NSInteger s = self.stocks.count - 1; s >= 0; s--) {    // go backwards so stock[0] draws on top
        
        stockData = [self.stocks objectAtIndex:s];
        
        if (stockData.oldestBarShown <= 0) {
            continue; // nothing to draw, so skip it
        }
        
        if ([stockData fundamentalAPI] != nil) {
            stocksWithFundamentals++;
            for (NSString *key in [[[stockData fundamentalAPI] columns] allKeys]) {
                NSInteger r = [stockData fundamentalAPI].newestReportInView;
                // DLog(@"checking key %@", key);
                if ([key isEqualToString:@"BookValuePerShare"]) { continue; }
                
                do {
                    reportValue = [[stockData fundamentalAPI] valueForReport:r withKey:key];
                    // DLog(@"report value is %@", reportValue);
                    [self.comparison updateMinMaxFor:key value:reportValue];  // handles notANumber

                } while (++r <= [stockData fundamentalAPI].oldestReportInView);
            }
        }
        
        CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
        CGContextSetLineWidth(_layerContext, 1.0);   // pIXELs
        
        if (s == 1 && dateShift != stockData.oldestBarShown) { // 3rd chart must use same dates as 2nd
    
            dateShift = stockData.oldestBarShown;
            
            CGContextSetStrokeColor(_layerContext, monthLineColor);
            CGContextStrokeLineSegments(_layerContext, stockData.monthLines, stockData.monthCount);
                        
            NSInteger monthLabelIndex = 0;
            CGFloat offset = 10 *  self.layer.contentsScale;
            
            for (NSInteger m = 0; m < stockData.monthCount; m++) {
                m++; // 2nd point is chartbase
                
                p = (CGPoint) stockData.monthLines[m];
                
                monthLabelIndex = floorf(m/2);
                
                if (monthLabelIndex < [[stockData monthLabels] count]) {
                    label = [[stockData monthLabels] objectAtIndex:monthLabelIndex];
                    [self showString:label atPoint:CGPointMake(p.x, p.y + offset * (s + 1)) withColor:stockData.stock.upColor];
                } else {
                   // DLog(@"Missing month label for index %d", monthLabelIndex);
                }
            }
        }
        
        if ([[stockData bookValue] isEqualToNumber:[NSDecimalNumber notANumber]] == NO) {
                    
            NSInteger r = [stockData fundamentalAPI].newestReportInView;
            CGContextSaveGState(_layerContext);
            CGContextBeginPath(_layerContext);
            
            CGFloat y = 0.;
            BOOL firstReport = YES;
            
            while ((reportValue = [[stockData fundamentalAPI] valueForReport:r withKey:@"BookValuePerShare"]) && r < [stockData fundamentalAPI].oldestReportInView) {
                
                if ([reportValue isEqualToNumber:[NSDecimalNumber notANumber]]) {
                    r++;
                    continue;
                }
                y = stockData.yFactor * [[stockData.maxHigh decimalNumberBySubtracting:reportValue] doubleValue];
                
                if (firstReport) {  // first report
                    CGContextMoveToPoint(_layerContext, stockData.fundamentalAlignments[r], y + _sparklineHeight);
                    firstReport = NO;
                } else {
                    CGContextAddLineToPoint(_layerContext, stockData.fundamentalAlignments[r], y + _sparklineHeight);
                }
                r++;
            }    
            CGContextSetLineWidth(_layerContext, 5.);
            CGContextSetShadowWithColor(_layerContext, CGSizeMake(0., 5.), 0.5, stockData.stock.upColorHalfAlpha.CGColor);
            CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColorHalfAlpha.CGColor);
            CGContextStrokePath(_layerContext);  
            CGContextRestoreGState(_layerContext);
        }
        
        if (stockData.movingAvg1Count > 2) {
            CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.colorInverseHalfAlpha.CGColor);
            CGContextBeginPath(_layerContext);
            CGContextAddLines(_layerContext, stockData.movingAvg1, stockData.movingAvg1Count);
            CGContextStrokePath(_layerContext);
        }
        
        if (stockData.movingAvg2Count > 2) {
            CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColorHalfAlpha.CGColor);
            CGContextBeginPath(_layerContext);
            CGContextAddLines(_layerContext, stockData.movingAvg2, stockData.movingAvg2Count);
            CGContextStrokePath(_layerContext);
        }

        if (stockData.bbCount > 2) {
            CGContextSetLineDash(_layerContext, 0., dashPattern, 2);
            CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
            CGContextBeginPath(_layerContext);
            CGContextAddLines(_layerContext, stockData.ubb, stockData.bbCount);
            CGContextStrokePath(_layerContext);

            CGContextBeginPath(_layerContext);
            CGContextAddLines(_layerContext, stockData.lbb, stockData.bbCount);
            CGContextStrokePath(_layerContext);
            
            CGContextBeginPath(_layerContext);
            CGContextAddLines(_layerContext, stockData.mbb, stockData.bbCount);
            CGContextStrokePath(_layerContext);
            CGContextSetLineDash(_layerContext, 0, NULL, 0);    // reset to solid
        }
        
        CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
        
        CGContextSetLineWidth(_layerContext, 1.0 * self.layer.contentsScale);   // pIXELs
        
        CGContextSetFillColorWithColor(_layerContext, stockData.stock.color.CGColor);
        CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.color.CGColor);
        
        if (stockData.redPointCount > 0) {
            CGContextStrokeLineSegments(_layerContext, stockData.redPoints, stockData.redPointCount);
        }
        
        if (stockData.redBarCount > 0) {
            
            for (NSInteger r = 0; r < stockData.hollowRedCount; r++) {
                CGContextStrokeRect(_layerContext, stockData.hollowRedBars[r]);
            }
            CGContextFillRects(_layerContext, stockData.redBars, stockData.redBarCount);
        }
        
        CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
        
        if (stockData.whiteBarCount > 0) {
            for (NSInteger r = 0; r < stockData.whiteBarCount; r++) {
                CGContextStrokeRect(_layerContext, stockData.greenBars[r]);
            }    
            
            CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
            CGContextFillRects(_layerContext, stockData.filledGreenBars, stockData.filledGreenCount);
        }
        
        CGContextSetFillColorWithColor(_layerContext, stockData.stock.colorHalfAlpha.CGColor);
        CGContextFillRects(_layerContext, stockData.redVolume, stockData.redCount);
        
        CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColorHalfAlpha.CGColor);
        CGContextFillRects(_layerContext, stockData.blackVolume, stockData.blackCount);

        
        switch (stockData.stock.chartType) {
            case 0:
            case 1:
                CGContextSetBlendMode(_layerContext, kCGBlendModeNormal);
                CGContextStrokeLineSegments(_layerContext, stockData.points, stockData.pointCount);
                break;
            
            case 2:
                CGContextStrokeLineSegments(_layerContext, stockData.points, stockData.pointCount);
                break;
            case 3:
                CGContextBeginPath(_layerContext);
                CGContextAddLines(_layerContext, stockData.points, stockData.pointCount);
                CGContextSetLineJoin(_layerContext, kCGLineJoinRound);
                CGContextStrokePath(_layerContext);
                break;
        }
            
        CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
        
        [self.numberFormatter setMaximumFractionDigits:0];
        
        CGFloat fontSize;
        
        if ([[stockData maxHigh] doubleValue] < 9999) {
            if ([[stockData maxHigh] doubleValue] < 100) {
                [self.numberFormatter setMaximumFractionDigits:2];
            }
            fontSize = 10 * self.layer.contentsScale;
        } else if ([[stockData maxHigh] doubleValue] < 99999) {
            fontSize = 8 * self.layer.contentsScale;
        } else {
            fontSize = 7 * self.layer.contentsScale;
        }
        
        CGFloat x = _pxWidth + (s + .15) * 30 * self.layer.contentsScale;
        
        /* Algorithm for displaying price increments: show actual high and low.  No need to show scaled low
         
         Ensure that there is enough space in between incements.  
         
         Show increments in rounded amounts (e.g., 550, 560, 570, etc.)
         
         To do this we need to use NSDecimalNumber for precision.
         
         Note that even the increment needs to be an NSDecimalNumber for penny stocks.
         */
        
        NSDecimalNumber *range = [[stockData maxHigh] decimalNumberBySubtracting:[stockData scaledLow]];
        
        NSDecimalNumber *increment, *avoidLabel, *nextLabel, *two;
        two = [[[NSDecimalNumber alloc] initWithInt:2] autorelease];

        if ([range doubleValue] > 1000) {
            increment = [[[NSDecimalNumber alloc] initWithInt:10000] autorelease];
            
            while ([[range decimalNumberByDividingBy:increment withBehavior:self.roundDown] doubleValue] < 4.) {   
                // too many labels
                increment = [increment decimalNumberByDividingBy:two];
            }
            
        } else if ([range doubleValue] > 20) {
            increment = [[[NSDecimalNumber alloc] initWithInt:5] autorelease];
            
            while ([[range decimalNumberByDividingBy:increment withBehavior:self.roundDown] doubleValue] > 10.) {   
                // too many labels
                increment = [increment decimalNumberByMultiplyingBy:two];
            }
            
        } else if ([range doubleValue] > 10) {
            increment = [[[NSDecimalNumber alloc] initWithInt:2] autorelease];
        } else if ([range doubleValue] > 5) {
            increment = [[[NSDecimalNumber alloc] initWithInt:1] autorelease];
        } else if ([range doubleValue] > 2.5) {
            increment = [[[NSDecimalNumber alloc] initWithDouble:0.5] autorelease];
        } else if ([range doubleValue] > 1) {
            increment = [[[NSDecimalNumber alloc] initWithDouble:0.25] autorelease];
        } else if ([range doubleValue] > 0.5) {
            increment = [[[NSDecimalNumber alloc] initWithDouble:0.1] autorelease];
        } else {
            increment = [[[NSDecimalNumber alloc] initWithDouble:0.05] autorelease];
        }
        
        avoidLabel = stockData.lastPrice;
        
//        // Optional: show book value on yAxis
//        if ([stock.bookValue isEqualToNumber:[NSDecimalNumber notANumber]] == NO) {
//            [self writeLabel:stock.bookValue forStock:stock atX:x showBox:YES];
//        }
        
        if (15 < fabs(stockData.yFactor * [[stockData.maxHigh decimalNumberBySubtracting:stockData.lastPrice] doubleValue])) {
            // lastPrice is lower than maxHigh
            [self writeLabel:stockData.maxHigh forStock:stockData atX:x showBox:NO];
            avoidLabel = stockData.maxHigh;
        }
        
        nextLabel = [[stockData.maxHigh decimalNumberByDividingBy:increment withBehavior:self.roundDown] decimalNumberByMultiplyingBy:increment];
        
        if ([stockData.maxHigh compare:stockData.lastPrice] == NSOrderedDescending) {
            [self writeLabel:stockData.lastPrice forStock:stockData atX:x showBox:YES];
            
            if (15 > fabs(stockData.yFactor * [[stockData.lastPrice decimalNumberBySubtracting:nextLabel] doubleValue])) {
                nextLabel = [nextLabel decimalNumberBySubtracting:increment];       // go to next label
            }
        }
                
        while ([nextLabel compare:stockData.minLow] == NSOrderedDescending) {
            
            if (15 < fabs(stockData.yFactor * [[avoidLabel decimalNumberBySubtracting:nextLabel] doubleValue])) {
                [self writeLabel:nextLabel forStock:stockData atX:x showBox:NO];
            }

            nextLabel = [nextLabel decimalNumberBySubtracting:increment];
            
            if (20 > fabs(stockData.yFactor * [[stockData.lastPrice decimalNumberBySubtracting:nextLabel] doubleValue])) {
                avoidLabel = stockData.lastPrice;
            } else {
                avoidLabel = stockData.minLow;
            }
        }
        
        // If last price is near the minLow, skip minLow (e.g. RIMM)
        if (15 < fabs(stockData.yFactor * [[stockData.minLow decimalNumberBySubtracting:stockData.lastPrice] doubleValue])) {
            [self writeLabel:stockData.minLow forStock:stockData atX:x showBox:NO];
        }
    }
    
    NSDecimalNumber *sparkHeight = [[[NSDecimalNumber alloc] initWithDouble:(90)] autorelease];
    double qWidth = _xFactor * 60;   // use xFactor to avoid having to divide by barUnit
  
    double h = 0., yNegativeAdjustment = 0., y = [sparkHeight doubleValue], yLabel = 20;
    
    for (NSString *key in self.sparklineKeys) { // go through keys in order in case one stock has the key turned off
        NSDecimalNumber *range = [self.comparison rangeFor:key];
        if ([range isEqualToNumber:[NSDecimalNumber notANumber]] || [range isEqualToNumber:[NSDecimalNumber zero]]) {
            continue; // skip it
        }
        
        NSDecimalNumber *sparklineYFactor;
        
        sparklineYFactor = [sparkHeight decimalNumberByDividingBy:range];

        if ([[self.comparison minFor:key] compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
            
            if ([[self.comparison maxFor:key] compare:[NSDecimalNumber zero]] == NSOrderedAscending) {

                yNegativeAdjustment = -1 * [sparkHeight doubleValue];
            } else {
                yNegativeAdjustment = [[[self.comparison minFor:key] decimalNumberByMultiplyingBy:sparklineYFactor] doubleValue];
            }
            
            y += yNegativeAdjustment;
        }
        NSString *title = nil, *label = nil;
        CGPoint labelPosition = CGPointZero;
        const CGFloat minBarHeightForLabel = 25; // if fundamental bar is shorter then this, put metric value above the bar
       
        for (StockData *stockData in self.stocks) {
            
            if ([stockData.stock.fundamentalList rangeOfString:key].length < 3) {
                continue;
            }
            
            if (stockData.oldestBarShown > 0 && [stockData fundamentalAPI] != nil) {
                CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColorHalfAlpha.CGColor);

                NSInteger r = [stockData fundamentalAPI].newestReportInView;
                if (title == nil) {
                    title = [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] titleForKey:key];
                    CGFloat x = MIN(_pxWidth + 5, stockData.fundamentalAlignments[r] + 10);
                    CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
                    UIColor *stockColor = [UIColor colorWithCGColor:stockData.stock.upColor.CGColor];
                    [self showString:title atPoint:CGPointMake(x, yLabel) withColor:stockColor];
                }
            
                for (/* r = newestReportInView  */; r < stockData.fundamentalAPI.oldestReportInView && stockData.fundamentalAlignments[r] > 0; r++) {
                    
                    reportValue = [[stockData fundamentalAPI] valueForReport:r withKey:key];
            
                    if ([reportValue isEqualToNumber:[NSDecimalNumber notANumber]]) {
                        continue;
                    }
                    qWidth = stockData.fundamentalAlignments[r] - stockData.fundamentalAlignments[r + 1] - 3;
                    
                    if (qWidth < 0 || stockData.fundamentalAlignments[r + 1] < 1.) {
                        qWidth = MIN(stockData.fundamentalAlignments[r], stockData.xFactor * 60/_barUnit) ;
                    }
                    h = [[reportValue decimalNumberByMultiplyingBy:sparklineYFactor] doubleValue];
                    
                    UIColor *metricColor = [UIColor blackColor];
                    
                    if ([reportValue compare:[NSDecimalNumber zero]] == NSOrderedAscending) {   // negative value
                        labelPosition.y = y;  // subtracting the height pushes it too far down
                        CGContextSetFillColor(_layerContext, redMetric);
                        metricColor = [UIColor redColor];
                    } else {
                        labelPosition.y = y + minBarHeightForLabel - h;
                        if (h < minBarHeightForLabel) {
                            labelPosition.y = y - minBarHeightForLabel; // show above the bar instead
                        }
                        metricColor = stockData.stock.upColorHalfAlpha;
                        CGContextSetFillColorWithColor(_layerContext, metricColor.CGColor);
                    }
                    
                    CGContextSetBlendMode(_layerContext, kCGBlendModeNormal);
                    CGContextFillRect(_layerContext, CGRectMake(stockData.fundamentalAlignments[r], y, -qWidth, -h));
                                        
                    if (_barUnit < 5. && stocksWithFundamentals == 1) {     // don't show labels for monthly or comparison charts
                        label = [self.numberFormatter stringFromNumber:reportValue maxDigits:2*_xFactor];
                        CGContextSetBlendMode(_layerContext, kCGBlendModePlusLighter);
                    
                        labelPosition.x = stockData.fundamentalAlignments[r] - 11.5 * label.length - 10;
                        [self showString:label atPoint:CGPointMake(labelPosition.x, labelPosition.y) withColor:metricColor];
                    }
                }                
            }
        }
        y += 10 + [sparkHeight doubleValue] - yNegativeAdjustment;
        yLabel += 10 + [sparkHeight doubleValue];
        yNegativeAdjustment = 0.;
    }
    
    UIGraphicsPopContext(); // remove layerContext
    
    [self setNeedsDisplay];
}

- (void) drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, UIColor.systemBackgroundColor.CGColor);
    
    CGContextFillRect(ctx, CGRectMake(0, 0, self.layer.contentsScale * _maxWidth, _pxHeight + 5));    // labels and moving averages extend outside _pxHeight and leave artifacts
    
    CGContextDrawLayerInRect(ctx, CGRectMake(5 + _scaleShift, 5, _scaledWidth, _svHeight), _layerRef);

    // Draw left-hand draggable line between tableview and chart area
    CGContextSetStrokeColor(ctx, dotGripColor);
    CGContextSetLineWidth(ctx, 1.0);   // pIXELs
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 0.5, 0);
    CGContextAddLineToPoint(ctx, 0.5, _svHeight);
    CGContextStrokePath(ctx);
}

/* Transforms chart during pinch/zoom gesture and to calculate scaleShift for final shiftRedraw */
- (void) resizeChartImage:(CGFloat)newScale withCenter:(CGFloat)touchMidpoint {
    
    CGFloat scaleFactor = _xFactor * newScale;
    
    if (scaleFactor <= .25) {
        scaleFactor = .25;
        newScale = .25/_xFactor;
        
    } else if (scaleFactor > 50) { // too zoomed in, so make no change
        scaleFactor = 50;
        newScale = 50/_xFactor;
    }
    
    if (scaleFactor == _xFactor) {
        return; // prevent strange pan when zoom hits max or mix
    }
  
    _scaleShift = touchMidpoint * (1 - newScale);        // shift image by scaled change to touch midpoint
    
    _scaledWidth = _maxWidth * newScale;                  // scale image
    
    [self setNeedsDisplay];
}

// Uses scaleShift set by resizeChartImage so the rendered chart matches the temporary transformation
- (void) resizeChart:(CGFloat)newScale {
    
    _scaledWidth = _maxWidth;     // reset buffer output width after temporary transformation
    
    CGFloat newXfactor = _xFactor * newScale;
        
    // Keep xFactor and barUnit separate and multiply them together for StockData.xFactor
    
    if (newXfactor < 1.) {
        _barUnit = 19.;              // switch to monthly
        
        if (newXfactor < .25) {
            newXfactor = .25;   // minimum size for monthly charting
        }
    } else if (newXfactor < 3) {
        _barUnit = 4.5;          // switch to weekly

    } else if (_barUnit == 19. && newXfactor  * _barUnit > 20.) {
        _barUnit = 4.5;              // switch to weekly
        
    } else if (_barUnit == 4.5 && newXfactor  * _barUnit > 10. ) {
        _barUnit = 1.;               // switch to daily

    }  else if (newXfactor > 50) { // too small, so make no change
        newXfactor = 50;
    }
    
    NSInteger shiftBars = floor(self.layer.contentsScale * _scaleShift /(_barUnit * newXfactor));
    _scaleShift = 0.;
    
    if (newXfactor == _xFactor) {
        return; // prevent strange pan when zoom hits max or mix
    }

    _xFactor = newXfactor;
    
    NSDecimalNumber *percentChange;
    
    [self setChartPercentChange:[NSDecimalNumber zero]];
    
    for(StockData *stockData in self.stocks) {
        
        stockData.xFactor = _xFactor * _barUnit;
    
        if (stockData.barUnit != _barUnit) {
             
            [stockData setNewestBarShown:floor(stockData.newestBarShown * stockData.barUnit / _barUnit)];
            stockData.oldestBarShown = floor(stockData.oldestBarShown * stockData.barUnit / _barUnit);
            stockData.barUnit = _barUnit;
           
            [stockData updatePeriodDataByDayWeekOrMonth];
            
            if (stockData.oldestBarShown > stockData.periodCount) {
                stockData.oldestBarShown = stockData.periodCount;
            }

            [stockData updateHighLow];      // must be a separate call to handle shifting
        }
        
        [stockData setPxHeight:_pxHeight withSparklineHeight:_sparklineHeight];
        
        percentChange = [stockData shiftRedraw:shiftBars withBars:[self maxBarOffset]];
        if ([percentChange compare: self.chartPercentChange] == NSOrderedDescending) {
            [self setChartPercentChange:percentChange];
        }
    }
    
    for(StockData *stock in self.stocks) {
        [stock updateLayer: self.chartPercentChange forceRecompute:NO];
    }
    
    [self renderCharts];
}

- (void) resizeLayer:(CALayer*)layer by:(CGFloat)shift {
    
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position"];
        
    animation.fromValue = [layer valueForKey:@"position"];
        
    CGPoint newPoint = layer.position;
    newPoint.x += shift;
            
    animation.toValue = [NSValue valueWithCGPoint:newPoint];
        
    layer.position = newPoint;      // Update layer position so it doesn't snap back when animation completes
        
    [layer addAnimation:animation forKey:@"position"];
}

- (void) updateMaxPercentChangeWithBarsShifted:(NSInteger)barsShifted {
        
    NSDecimalNumber *percentChange;

    BOOL outOfBars = YES;
    NSInteger MIN_BARS_SHOWN = 20;
    
    for(StockData *stock in self.stocks) {
        
        if (barsShifted == 0) {
            outOfBars = NO;
        } else if (barsShifted > 0 && barsShifted < stock.periodCount - stock.newestBarShown) {
            outOfBars = NO;
        } else if (barsShifted < 0 && stock.oldestBarShown - barsShifted > MIN_BARS_SHOWN) {
            outOfBars = NO;
        }
    }

    if (outOfBars) {
        // DLog(@"no bars to shift");
        return;
    }
    
    for(NSInteger i=0; i < self.stocks.count; i++) {
        StockData *stock = [self.stocks objectAtIndex:i];
        percentChange = [stock shiftRedraw:barsShifted withBars:[self maxBarOffset]];
    
        if ([percentChange compare: self.chartPercentChange] == NSOrderedDescending) {
            [self setChartPercentChange:percentChange];
        }
    }

    for(StockData *stock in self.stocks) {
        [stock updateLayer: self.chartPercentChange forceRecompute:NO];
    }
    
    [self renderCharts];
}

- (void) resize {
    
	[self resetDimensions];
    CGLayerRelease(_layerRef);       // release old context and get a new one
    [self createLayerContext];
    
    [self setChartPercentChange:[NSDecimalNumber zero]];
    
    for(StockData *stock in self.stocks) {
        [stock setPxHeight:_pxHeight withSparklineHeight:_sparklineHeight];
        stock.xFactor = _xFactor * _barUnit;
        [stock setNewestBarShown:(stock.oldestBarShown - [self maxBarOffset])];
        [stock updateHighLow];
        
        if ([[stock percentChange] compare: self.chartPercentChange] == NSOrderedDescending) {
            [self setChartPercentChange:[stock percentChange]];
        }
    }
    
    for(StockData *stock in self.stocks) {
        [stock updateLayer: self.chartPercentChange forceRecompute:NO];
    }
    
    [self renderCharts];
}

- (void) writeLabel:(NSDecimalNumber *)price forStock:(StockData *)s atX:(CGFloat)x showBox:(BOOL)showBox {
    
    NSString *l = [self.numberFormatter stringFromNumber:price];
     
    CGFloat y = s.yFloor - s.yFactor * [price doubleValue] + 20;    
    
    y = [s pxAlign:y alignTo:0.5];
    x = [s pxAlign:x alignTo:0.5];
    
    [self showString:l atPoint:CGPointMake(x, y) withColor:s.stock.upColor];
    
    if (showBox) {
        CGFloat boxWidth = l.length * 14, // size to fit string l in *points* not device pixels
                boxHeight = 28;
        
        CGContextSetStrokeColorWithColor(_layerContext, s.stock.upColorHalfAlpha.CGColor);
        CGContextStrokeRect(_layerContext, CGRectMake(x - 0.5, y - 24, boxWidth, boxHeight));
     }
}

// To remember the last valid bar pressed, pressedBarIndex is only reset when the touch down begins
- (void) resetPressedBar {
    _pressedBarIndex = -1;
}

- (UIImage *) magnifyBarAtX:(CGFloat)x y:(CGFloat)y {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(magnifierSize, magnifierSize), NO, self.layer.contentsScale);
    CGContextRef lensContext = UIGraphicsGetCurrentContext();

    UIColor *backgroundColor = UIColor.whiteColor;
    UIColor *textColor = UIColor.blackColor;
    
    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground]) {
        backgroundColor = UIColor.blackColor; // reverse colors
        textColor = UIColor.whiteColor;
    }
    CGContextSetFillColorWithColor(lensContext, backgroundColor.CGColor);
    CGContextFillRect(lensContext, CGRectMake(0, 0, magnifierSize, magnifierSize));
    
    CGFloat yPressed = y * self.layer.contentsScale;
    
    CGFloat scale = UIScreen.mainScreen.scale;
    CGFloat magnification = 2.0;
    
    CGFloat midpoint = magnifierSize / (2 * magnification);
    
    x = (x - midpoint) * self.layer.contentsScale;      // subtract midpoint to make the touch point the center of the lens, not the top left corner
    y = (y - 2 * midpoint) * self.layer.contentsScale;
        
    // CGContextDrawLayerAtPoint will paint pixels from the chart in layerRef as points in lensContext
    // this automatically magnifies it by 2x on 2x retina but we need to rescale by 2/3 for 3x retina screens
    if (scale >= 1) {
        CGContextScaleCTM(lensContext, magnification / scale, magnification / scale);
    }
    CGContextDrawLayerAtPoint(lensContext, CGPointMake(-x,-y), _layerRef);
    
    NSString *label = @"";
    
    CGFloat centerX = x + midpoint * scale - _xFactor * _barUnit / 2; // because xRaw starts at xFactor/scale
        
    CGContextSetBlendMode(lensContext, kCGBlendModeNormal);
        
    for (StockData *stockData in self.stocks) {

        if (stockData.oldestBarShown - roundf(centerX/(_xFactor * _barUnit)) >= 0) {
        
            _pressedBarIndex = stockData.oldestBarShown - roundf(centerX/(_xFactor * _barUnit));        // only overwrite pressedBarIndex if its valid
            
            BOOL upClose = YES;
            BarData *bar = [stockData barAtIndex:_pressedBarIndex setUpClose:&upClose];
            
            if (bar != nil) {
                CGFloat barHigh = stockData.yFloor - stockData.yFactor * bar.high;
                CGFloat barLow = stockData.yFloor - stockData.yFactor * bar.low;
                
                if (yPressed < barLow && yPressed > barHigh) {
                    // reduce opacity by filling .25 alpha background over image so scope values are clearer
                    CGContextSetFillColorWithColor(lensContext,
                                                   CGColorCreateCopyWithAlpha(backgroundColor.CGColor, 0.25));
                    CGContextFillRect(lensContext, CGRectMake(0., 0., magnifierSize, magnifierSize));
                    
                    UIColor *strokeColor = (upClose ? stockData.stock.upColor : stockData.stock.color);
                    
                    CGContextSetStrokeColorWithColor(lensContext, strokeColor.CGColor);
                    CGContextSetLineWidth(lensContext, UIScreen.mainScreen.scale);
                    CGContextSetShadow(lensContext, CGSizeMake(.5, .5), 0.75);
                    [self.numberFormatter setMaximumFractionDigits: (bar.high > 100 ? 0 : 2)];
                    
                    label = [stockData monthName:bar.month];
                    
                    if (_barUnit < 19) {
                        label = [label stringByAppendingFormat:@"%ld", bar.day];
                    } else {
                        label = [label stringByAppendingString:@"'"];   // append this before substringFromIndex on year
                        label = [label stringByAppendingString:[[NSString stringWithFormat:@"%ld", bar.year] substringFromIndex:2]];
                    }
                    
                    // show string for bar date
                    [self showString:label atPoint:CGPointMake(16. * scale, 7. * scale) withColor:textColor size:12.];
                    
                    double scopeFactor = (bar.high > bar.low) ? 31. * scale / (bar.high - bar.low) : 0;
                    double midPoint = (bar.high + bar.low)/2.;
                    
                    label = [self.numberFormatter stringFromNumber:[NSNumber numberWithDouble:bar.open]];
                    double y = 27.5 * scale + scopeFactor * (midPoint - bar.open);
                    [self showString:label atPoint:CGPointMake(10. * scale, y) withColor:textColor size:12.];
                    
                    y = (y < 27.5 * scale) ? y + 2.5 * scale : y - 5. * scale;                               // avoid text
                    CGContextMoveToPoint(lensContext, 20. * scale, y);
                    CGContextAddLineToPoint(lensContext, 25. * scale, y);
                
                    label = [self.numberFormatter stringFromNumber:[NSNumber numberWithDouble:bar.high]];
                    y = 27.5 * scale + scopeFactor * (midPoint - bar.high);
                    [self showString:label atPoint:CGPointMake(22. * scale, y) withColor:textColor size:12.];

                    y = (y < 27.5 * scale) ? y + 2.5 * scale : y - 5.* scale;                               // avoid text
                    CGContextMoveToPoint(lensContext, 25. * scale, y);
                    
                    label = [self.numberFormatter stringFromNumber:[NSNumber numberWithDouble:bar.low]];
                    y = 27.5*scale + scopeFactor * (midPoint - bar.low);
                    [self showString:label atPoint:CGPointMake(22. * scale, y) withColor:textColor size:12.];
                    
                    y = (y < 27.5*scale) ? y + 2.5*scale : y - 5. * scale;                                // avoid text
                    CGContextAddLineToPoint(lensContext, 25.*scale, y);
                    
                    label = [self.numberFormatter stringFromNumber:[NSNumber numberWithDouble:bar.close]];                    
                    y = 27.5 * scale + scopeFactor * (midPoint - bar.close);
                    [self showString:label atPoint:CGPointMake(33. * scale, y) withColor:textColor size:12.];
                    
                    y = (y < 27.5*scale) ? y + 2.5*scale : y - 5.* scale;;                               // avoid text
                    CGContextMoveToPoint(lensContext, 25.* scale, y);
                    CGContextAddLineToPoint(lensContext, 30.* scale, y);
                    CGContextStrokePath(lensContext);

                    break; // use the first bar that fits to avoid overlap
                }
            }
        }
    }
    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return screenshot;
}

// Renders string in current graphics context with default size
- (void) showString:(NSString *)string atPoint:(CGPoint)point withColor:(UIColor *)color{
    CGFloat fontSize = self.layer.contentsScale > 2. ? 25. : 22.; // Larger font needed with higher dot pitch
    [self showString:string atPoint:point withColor:color size:fontSize];
}

// Renders string in current graphics context with provided size (to set a lower size for magnifyBarAtX)
- (void) showString:(NSString *)string atPoint:(CGPoint)point withColor:(UIColor *)color size:(CGFloat)size {
    if (color == nil) {
        NSLog(@"attempting to showString %@ but color is nil", string);
    }
    
    NSDictionary *textAttributes = @{NSFontAttributeName: [UIFont systemFontOfSize:size],
                                     NSForegroundColorAttributeName: color
    };
    point.y -= size; // Shift y by font size for similar rendering to prior CGContextShowTextAtPoint
    [string drawAtPoint:point withAttributes:textAttributes];
}

- (void) requestFailedWithMessage:(NSString *)message {

    [self.progressIndicator stopAnimating]; 

    // DLog(@"RequestFailed so stopping progressIndicator because ERROR %@ and last error %f", message, [[NSDate date] timeIntervalSinceDate:self.lastNetworkErrorShown]);
}

- (void) requestFinished:(NSDecimalNumber *)newPercentChange {
    
    NSInteger chartsReady = 0;
    
    for(StockData *stock in self.stocks) {
        if (stock.ready == YES) {
            chartsReady++;
        } else {
           // DLog(@"requestFinished but %@ is NOT READY", stock.stock.symbol);
        }
    }   
    
    if ([newPercentChange compare: self.chartPercentChange] == NSOrderedDescending) {
        [self setChartPercentChange:newPercentChange];
    }
    
    if (chartsReady == [self.stocks count]) {
        for(StockData *stock in self.stocks) {
            [stock updateLayer: self.chartPercentChange forceRecompute:NO];
        }
        
        [self.layer removeAllAnimations];
        [self.layer setOpacity:1.0];
        [self renderCharts];
        [self.progressIndicator stopAnimating];        
    }
}

- (BOOL) isOpaque {
    return YES;
} 

@end
