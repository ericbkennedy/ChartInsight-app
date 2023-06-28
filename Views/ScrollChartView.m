#import "ScrollChartView.h"
#import "ChartInsight-Swift.h"

const CGFloat magnifierSize = 100.; // both width and height
const CGFloat dashPattern[2] = {1.0, 1.5};
const CGFloat dotGripColor[4] = {0.5, 0.5, 0.5, 1.0};
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
@property (strong, nonatomic) NSCalendar *gregorian;
@property (strong, nonatomic) NSDate *lastNetworkErrorShown;
@end

@implementation ScrollChartView

- (void) dealloc {
    CGLayerRelease(_layerRef); // Release CGLayerRef since it isn't managed by ARC
    [super dealloc];
}

/// Adjusts _svWidth chart area to allow one right axis per stock
- (void) updateDimensions {
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

        [self setGregorian:[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]];
        
        BigNumberFormatter *newNumberFormatter = [[BigNumberFormatter alloc] init];
        [self setNumberFormatter:newNumberFormatter];

        [self setChartPercentChange:[NSDecimalNumber zero]];
        
        [self setLastNetworkErrorShown:[NSDate dateWithTimeIntervalSinceNow:-120.]];    // ensure the first error shows
    }
    return self;
}

/// Ensure any pending requests for prior comparison are invalidated and set stockData.delegate = nil
- (void) clearChart {
    [self.progressIndicator reset];
    
    CGContextClearRect(_layerContext, CGRectMake(0, 0, self.layer.contentsScale * _maxWidth, _pxHeight));
    [self setNeedsDisplay];
    
    for (StockData *s in self.stocks) {
        [s invalidateAndCancel];    // ensures StockData, DataAPI and FundamentalAPI get deallocated
        s.delegate = nil;
    }
    
    [self.stocks removeAllObjects];
}

/// Redraw charts without loading any data if a stock color, chart type or technical changes
-(void) redrawCharts {
    for (StockData *s in self.stocks) {
        [s recompute:self.chartPercentChange forceRecompute:YES];
    }
    [self renderCharts];
}

/// Called by StockData when saved rows are insuffient
- (void) showProgressIndicator {
    [self.progressIndicator startAnimating];
}

/// Called by StockData when fundamental API returns before historical API
- (void) stopProgressIndicator {
    [self.progressIndicator stopAnimating];
}

/// Render charts for the stocks in scrollChartView.comparison and fetch data as needed
- (void) loadChart {

    [self setChartPercentChange:[NSDecimalNumber zero]];
    
    [self updateDimensions];     // adjusts chart area to allow one right axis per stock
    
    self.sparklineKeys = self.comparison.sparklineKeys;
    
    _sparklineHeight = 100 * [self.sparklineKeys count];
    
    for (Stock *stock in self.comparison.stockList) {
        StockData *stockData = [[StockData alloc] initWithStock:stock
                                                      gregorian:_gregorian
                                                       delegate:self
                                                 oldestBarShown:[self maxBarOffset]];
        [self.stocks addObject:stockData];

        stockData.barUnit = _barUnit;
        stockData.xFactor = _xFactor * _barUnit;
        [stockData setPxHeight:_pxHeight sparklineHeight:_sparklineHeight];
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
        
    if (self.stocks.count > 0) {
        stockData = [self.stocks objectAtIndex:0];
        [stockData copyChartElements];
        
        CGContextSetStrokeColor(_layerContext, monthLineColor);        
        CGContextSetLineWidth(_layerContext, 1.0);   // in pixels not points
        
        CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
        
        NSInteger monthLabelIndex = 0;
        CGFloat offset = 10 *  self.layer.contentsScale;
         
        for (NSInteger m = 0; m < stockData.chartElements.monthLines.count; m++) {
            NSValue *monthPointValue = stockData.chartElements.monthLines[m];
            CGPoint topPoint = monthPointValue.CGPointValue;

            m++; // 2nd point is chartbase
            monthPointValue = stockData.chartElements.monthLines[m];
            p = monthPointValue.CGPointValue;
            
            CGContextBeginPath(_layerContext);
            CGContextMoveToPoint(_layerContext, topPoint.x, topPoint.y);
            CGContextAddLineToPoint(_layerContext, p.x, p.y);
            CGContextSetStrokeColor(_layerContext, monthLineColor);
            CGContextStrokePath(_layerContext);

            monthLabelIndex = floorf(m/2);
            
            if (monthLabelIndex < stockData.chartElements.monthLabels.count) {
                label = stockData.chartElements.monthLabels[monthLabelIndex];
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
        if (s > 0) { // Already copied above in order to render monthLines
            [stockData copyChartElements];
        }
        
        if (stockData.oldestBarShown <= 0) {
            continue; // nothing to draw, so skip it
        }
        
        NSArray <NSString *> *fundamentalKeys = [stockData fundamentalKeys];
        
        if (fundamentalKeys.count > 0) {
            stocksWithFundamentals++;
            for (NSString *key in fundamentalKeys) {
                NSInteger r = stockData.newestReportInView;
                
                do {
                    reportValue = [stockData fundamentalValueForReport:r metric:key];
                    [self.comparison updateMinMaxFor:key value:reportValue];  // handles notANumber

                } while (++r <= stockData.oldestReportInView);
            }
        }
        
        CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
        CGContextSetLineWidth(_layerContext, 1.0);   // pIXELs
                
        if (stockData.chartElements.movingAvg1.count > 2) {
            CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.colorInverseHalfAlpha.CGColor);
            [self strokeLineFromPoints:stockData.chartElements.movingAvg1 context:_layerContext];
        }
        
        if (stockData.chartElements.movingAvg2.count > 2) {
            CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColorHalfAlpha.CGColor);
            [self strokeLineFromPoints:stockData.chartElements.movingAvg2 context:_layerContext];
        }

        if (stockData.chartElements.upperBollingerBand.count > 2) {
            CGContextSetLineDash(_layerContext, 0., dashPattern, 2);
            CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
            [self strokeLineFromPoints:stockData.chartElements.upperBollingerBand context:_layerContext];
            [self strokeLineFromPoints:stockData.chartElements.middleBollingerBand context:_layerContext];
            [self strokeLineFromPoints:stockData.chartElements.lowerBollingerBand context:_layerContext];

            CGContextSetLineDash(_layerContext, 0, NULL, 0);    // reset to solid
        }
        
        CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
        
        CGContextSetLineWidth(_layerContext, 1.0 * self.layer.contentsScale);   // pIXELs
        
        CGContextSetFillColorWithColor(_layerContext, stockData.stock.color.CGColor);
        CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.color.CGColor);
        
        [self strokeLinesFromPoints:stockData.chartElements.redPoints context:_layerContext];
        
        for (NSValue *value in stockData.chartElements.hollowRedBars) {
            CGContextStrokeRect(_layerContext, value.CGRectValue);
        }

        for (NSValue *value in stockData.chartElements.redBars) {
            CGContextFillRect(_layerContext, value.CGRectValue);
        }
                
        CGContextSetStrokeColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
        
        if (stockData.chartElements.greenBars.count > 0) {
            for (NSValue *value in stockData.chartElements.greenBars) {
                CGContextStrokeRect(_layerContext, value.CGRectValue);
            }
            
            CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
            
            for (NSValue *value in stockData.chartElements.filledGreenBars) {
                CGContextFillRect(_layerContext, value.CGRectValue);
            }
        }
        
        CGContextSetFillColorWithColor(_layerContext, stockData.stock.colorHalfAlpha.CGColor);
        for (NSValue *value in stockData.chartElements.redVolume) {
            CGContextFillRect(_layerContext, value.CGRectValue);
        }
        
        CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColorHalfAlpha.CGColor);
        for (NSValue *value in stockData.chartElements.blackVolume) {
            CGContextFillRect(_layerContext, value.CGRectValue);
        }
        
        switch (stockData.stock.chartType) {
            case ChartTypeOhlc:
            case ChartTypeHlc:
                CGContextSetBlendMode(_layerContext, kCGBlendModeNormal);
                // now that blend mode is set, fall through to next case to render lines
            case ChartTypeCandle:
                [self strokeLinesFromPoints:stockData.chartElements.points context:_layerContext];
                break;
            case ChartTypeClose:
                CGContextSetLineJoin(_layerContext, kCGLineJoinRound);
                [self strokeLineFromPoints:stockData.chartElements.points context:_layerContext];
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
        two = [[NSDecimalNumber alloc] initWithInt:2];

        if ([range doubleValue] > 1000) {
            increment = [[NSDecimalNumber alloc] initWithInt:10000];
            
            while ([[range decimalNumberByDividingBy:increment withBehavior:self.roundDown] doubleValue] < 4.) {   
                // too many labels
                increment = [increment decimalNumberByDividingBy:two];
            }
            
        } else if ([range doubleValue] > 20) {
            increment = [[NSDecimalNumber alloc] initWithInt:5];
            
            while ([[range decimalNumberByDividingBy:increment withBehavior:self.roundDown] doubleValue] > 10.) {   
                // too many labels
                increment = [increment decimalNumberByMultiplyingBy:two];
            }
            
        } else if ([range doubleValue] > 10) {
            increment = [[NSDecimalNumber alloc] initWithInt:2];
        } else if ([range doubleValue] > 5) {
            increment = [[NSDecimalNumber alloc] initWithInt:1];
        } else if ([range doubleValue] > 2.5) {
            increment = [[NSDecimalNumber alloc] initWithDouble:0.5];
        } else if ([range doubleValue] > 1) {
            increment = [[NSDecimalNumber alloc] initWithDouble:0.25];
        } else if ([range doubleValue] > 0.5) {
            increment = [[NSDecimalNumber alloc] initWithDouble:0.1];
        } else {
            increment = [[NSDecimalNumber alloc] initWithDouble:0.05];
        }
        
        avoidLabel = stockData.lastPrice;
        CGFloat minSpace = 20; // Skip any label within this distance of the avoidLabel value
        
        if (minSpace < fabs(stockData.yFactor * [[stockData.maxHigh decimalNumberBySubtracting:stockData.lastPrice] doubleValue])) {
            // lastPrice is lower than maxHigh
            [self writeLabel:stockData.maxHigh forStock:stockData atX:x showBox:NO];
            avoidLabel = stockData.maxHigh;
        }
        
        nextLabel = [[stockData.maxHigh decimalNumberByDividingBy:increment withBehavior:self.roundDown] decimalNumberByMultiplyingBy:increment];
        
        if ([stockData.maxHigh compare:stockData.lastPrice] == NSOrderedDescending) {
            [self writeLabel:stockData.lastPrice forStock:stockData atX:x showBox:YES];
            
            if (minSpace > fabs(stockData.yFactor * [[stockData.lastPrice decimalNumberBySubtracting:nextLabel] doubleValue])) {
                nextLabel = [nextLabel decimalNumberBySubtracting:increment];       // go to next label
            }
        }
                
        while ([nextLabel compare:stockData.minLow] == NSOrderedDescending) {
            
            if (minSpace < fabs(stockData.yFactor * [[avoidLabel decimalNumberBySubtracting:nextLabel] doubleValue])) {
                [self writeLabel:nextLabel forStock:stockData atX:x showBox:NO];
            }

            nextLabel = [nextLabel decimalNumberBySubtracting:increment];
            
            if (minSpace > fabs(stockData.yFactor * [[stockData.lastPrice decimalNumberBySubtracting:nextLabel] doubleValue])) {
                avoidLabel = stockData.lastPrice;
            } else {
                avoidLabel = stockData.minLow;
            }
        }
        
        // If last price is near the minLow, skip minLow (e.g. RIMM)
        if (minSpace < fabs(stockData.yFactor * [[stockData.minLow decimalNumberBySubtracting:stockData.lastPrice] doubleValue])) {
            [self writeLabel:stockData.minLow forStock:stockData atX:x showBox:NO];
        }
    }
    
    NSDecimalNumber *sparkHeight = [[NSDecimalNumber alloc] initWithDouble:90];
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
            NSMutableArray <NSNumber *> *fundamentalAlignments = stockData.chartElements.fundamentalAlignments;
            
            if (stockData.oldestBarShown > 0 && fundamentalAlignments.count > 0) {
                CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColorHalfAlpha.CGColor);

                NSInteger r = stockData.newestReportInView;
                if (title == nil) {
                    title = [(AppDelegate *)[[UIApplication sharedApplication] delegate] titleForKey:key];
                    CGFloat x = MIN(_pxWidth + 5, fundamentalAlignments[r].floatValue + 10);
                    CGContextSetFillColorWithColor(_layerContext, stockData.stock.upColor.CGColor);
                    UIColor *stockColor = [UIColor colorWithCGColor:stockData.stock.upColor.CGColor];
                    [self showString:title atPoint:CGPointMake(x, yLabel) withColor:stockColor];
                }
            
                for (/* r = newestReportInView  */; r < stockData.oldestReportInView && fundamentalAlignments[r] > 0; r++) {
                    
                    reportValue = [stockData fundamentalValueForReport:r metric:key];
            
                    if ([reportValue isEqualToNumber:[NSDecimalNumber notANumber]]) {
                        continue;
                    }
                                        
                    if (r + 1 < fundamentalAlignments.count) { // can calculate bar width to older report
                        qWidth = fundamentalAlignments[r].floatValue - fundamentalAlignments[r + 1].floatValue - 3;
                    } else { // no older reports so use default fundamental bar width
                        qWidth = MIN(fundamentalAlignments[r].floatValue, stockData.xFactor * 60/_barUnit) ;
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
                    CGContextFillRect(_layerContext, CGRectMake(fundamentalAlignments[r].floatValue, y, -qWidth, -h));
                                        
                    if (_barUnit < 5. && stocksWithFundamentals == 1) {     // don't show labels for monthly or comparison charts
                        label = [self.numberFormatter stringFromNumber:reportValue maxDigits:2*_xFactor];
                        CGContextSetBlendMode(_layerContext, kCGBlendModePlusLighter);
                    
                        labelPosition.x = fundamentalAlignments[r].floatValue - 11.5 * label.length - 10;
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

    if (self.layer.position.x > 0) { // draw line at chart left edge to visually separate from list of tickers
        CGContextSetStrokeColor(ctx, monthLineColor);
        CGContextSetLineWidth(ctx, 1.0);   // pIXELs
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, 0.5, 0.5);
        CGContextAddLineToPoint(ctx, 0.5, _svHeight);
        CGContextStrokePath(ctx);
    }
}

/// Horizontally scale chart image during pinch/zoom gesture and calculate scaleShift for final shiftRedraw
- (void) scaleChartImage:(CGFloat)newScale withCenter:(CGFloat)touchMidpoint {
    
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

/// Check if a stock has less price data available so the caller can limit all stocks to that shorter date range
- (NSInteger) maxSupportedPeriodsForComparison:(NSInteger *)oldestBarShown {
    NSInteger maxSupportedPeriods = 0;
    for (StockData *stockData in self.stocks) {
        if (*oldestBarShown == 0) {
            *oldestBarShown = stockData.oldestBarShown;
        }
        NSInteger periodCountAtNewScale = [stockData maxPeriodSupportedWithBarUnit:_barUnit];
        
        if (maxSupportedPeriods == 0 || maxSupportedPeriods > periodCountAtNewScale) {
            maxSupportedPeriods = periodCountAtNewScale;
        }
    }
    return maxSupportedPeriods;
}

/// Complete pinch/zoom transformation by rerendering the chart with the newScale
/// Uses scaleShift set by resizeChartImage so the rendered chart matches the temporary transformation
- (void) scaleChart:(CGFloat)newScale {
    
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
    
    // Check if a stock has less price data available and limit all stocks to that shorter date range
    NSInteger currentOldestShown = 0;
    NSInteger maxSupportedPeriods = [self maxSupportedPeriodsForComparison:&currentOldestShown];
        
    if (newXfactor == _xFactor) {
        return; // prevent strange pan when zoom hits max or mix
    } else if (currentOldestShown + shiftBars > maxSupportedPeriods) { // already at maxSupportedPeriods
        shiftBars = 0;
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
            
            if (stockData.oldestBarShown > maxSupportedPeriods) {
                stockData.oldestBarShown = maxSupportedPeriods;
            }

            [stockData updateHighLow];      // must be a separate call to handle shifting
        }
        
        [stockData setPxHeight:_pxHeight sparklineHeight:_sparklineHeight];
        
        percentChange = [stockData shiftRedraw:shiftBars withBars:[self maxBarOffset]];
        if ([percentChange compare: self.chartPercentChange] == NSOrderedDescending) {
            [self setChartPercentChange:percentChange];
        }
    }
    
    for(StockData *stock in self.stocks) {
        [stock recompute:self.chartPercentChange forceRecompute:NO];
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
    NSInteger maxSupportedPeriods = 0, currentOldestShown = 0;
    
    for(StockData *stock in self.stocks) {
        if (maxSupportedPeriods == 0 || maxSupportedPeriods > stock.periodData.count) {
            maxSupportedPeriods = stock.periodData.count;
        }
        if (currentOldestShown == 0) {
            currentOldestShown = stock.oldestBarShown;
        }
        
        if (barsShifted == 0) {
            outOfBars = NO;
        } else if (barsShifted > 0) { // users panning to older dates
            if (currentOldestShown + barsShifted >= maxSupportedPeriods) { // already at max
                outOfBars = YES;
            } else if (barsShifted < stock.periodData.count - stock.newestBarShown) {
                outOfBars = NO;
            }
        } else if (barsShifted < 0 && stock.oldestBarShown - barsShifted > MIN_BARS_SHOWN) {
            outOfBars = NO;
        }
    }

    if (outOfBars) {
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
        [stock recompute:self.chartPercentChange forceRecompute:NO];
    }
    
    [self renderCharts];
}

/// Create rendering context to match scrollChartViews.bounds. Called on initial load and after rotation
- (void) resize {
    
	[self updateDimensions];
    CGLayerRelease(_layerRef);       // release old context and get a new one
    [self createLayerContext];
    
    [self setChartPercentChange:[NSDecimalNumber zero]];
    
    for(StockData *stock in self.stocks) {
        [stock setPxHeight:_pxHeight sparklineHeight:_sparklineHeight];
        stock.xFactor = _xFactor * _barUnit;
        [stock setNewestBarShown:(stock.oldestBarShown - [self maxBarOffset])];
        [stock updateHighLow];
        
        if ([[stock percentChange] compare: self.chartPercentChange] == NSOrderedDescending) {
            [self setChartPercentChange:[stock percentChange]];
        }
    }
    
    for(StockData *stock in self.stocks) {
        [stock recompute:self.chartPercentChange forceRecompute:NO];
    }
    
    [self renderCharts];
}

- (void) writeLabel:(NSDecimalNumber *)price forStock:(StockData *)s atX:(CGFloat)x showBox:(BOOL)showBox {
    
    NSString *l = [self.numberFormatter stringFromNumber:price];
     
    CGFloat y = s.yFloor - s.yFactor * [price doubleValue] + 20;    
    
    CGFloat pxPerPoint = 1 / self.layer.contentsScale; // newer devices have 3 pixels per point
    y = [s pxAlign:y alignTo:pxPerPoint];
    x = [s pxAlign:x alignTo:pxPerPoint];
        
    if (showBox) {
        CGFloat boxWidth = l.length * 14, // size to fit string l in *points* not device pixels
                padding = 4,
                boxHeight = 28;
        
        CGContextSetStrokeColorWithColor(_layerContext, s.stock.upColorHalfAlpha.CGColor);
        CGContextStrokeRect(_layerContext, CGRectMake(x - pxPerPoint, y - boxHeight + padding, boxWidth, boxHeight));
    }
    // Text after box so it appears on top of background
    [self showString:l atPoint:CGPointMake(x, y) withColor:s.stock.upColor];
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
    
    if ([(AppDelegate *)UIApplication.sharedApplication.delegate darkMode]) {
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
            
            BarData *bar = [stockData barAt:_pressedBarIndex];
            
            if (bar != nil) {
                CGFloat barHigh = stockData.yFloor - stockData.yFactor * bar.high;
                CGFloat barLow = stockData.yFloor - stockData.yFactor * bar.low;
                
                if (yPressed < barLow && yPressed > barHigh) {
                    // reduce opacity by filling .25 alpha background over image so scope values are clearer
                    CGContextSetFillColorWithColor(lensContext,
                                                   CGColorCreateCopyWithAlpha(backgroundColor.CGColor, 0.25));
                    CGContextFillRect(lensContext, CGRectMake(0., 0., magnifierSize, magnifierSize));
                    
                    UIColor *strokeColor = bar.upClose ? stockData.stock.upColor : stockData.stock.color;
                    
                    CGContextSetStrokeColorWithColor(lensContext, strokeColor.CGColor);
                    CGContextSetLineWidth(lensContext, UIScreen.mainScreen.scale);
                    CGContextSetShadow(lensContext, CGSizeMake(.5, .5), 0.75);
                    [self.numberFormatter setMaximumFractionDigits: (bar.high > 100 ? 0 : 2)];
                    
                    label = bar.monthName;
                    
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

    // NSLog(@"RequestFailed so stopping progressIndicator because ERROR %@ and last error %f", message, [[NSDate date] timeIntervalSinceDate:self.lastNetworkErrorShown]);
}

- (void) requestFinished:(NSDecimalNumber *)newPercentChange {
    
    NSInteger chartsReady = 0;
    
    for(StockData *stock in self.stocks) {
        if (stock.ready == YES) {
            chartsReady++;
        } else {
           // NSLog(@"requestFinished but %@ is NOT READY", stock.stock.ticker);
        }
    }   
    
    if ([newPercentChange compare: self.chartPercentChange] == NSOrderedDescending) {
        [self setChartPercentChange:newPercentChange];
    }
    
    if (chartsReady == [self.stocks count]) {
        // Check if a stock has less price data available and limit all stocks to that shorter date range
        NSInteger currentOldestShown = 0;
        NSInteger maxSupportedPeriods = [self maxSupportedPeriodsForComparison:&currentOldestShown];
                
        for(StockData *stock in self.stocks) {
            if (stock.oldestBarShown > maxSupportedPeriods) {
                stock.oldestBarShown = maxSupportedPeriods;
            }
        }
        
        [self.layer removeAllAnimations];
        [self.layer setOpacity:1.0];
        [self renderCharts];
        [self.progressIndicator stopAnimating];        
    }
}

/// Create a continuous path using the points provided and stroke the final path
- (void) strokeLineFromPoints:(NSArray <NSValue *> *)points context:(CGContextRef)context {
    if (points.count > 0) { // Avoid creating and stroking an empty path
        CGContextBeginPath(context);
        for (NSInteger i = 0; i < points.count; i++) {
            NSValue *value = points[i];
            if (i == 0) {
                CGContextMoveToPoint(context, value.CGPointValue.x, value.CGPointValue.y);
            } else {
                CGContextAddLineToPoint(context, value.CGPointValue.x, value.CGPointValue.y);
            }
        }
        CGContextStrokePath(context);
    }
}

/// Create separate lines from each pair of points and stroke each line separately
- (void) strokeLinesFromPoints:(NSArray <NSValue *> *)points context:(CGContextRef)context {
    for (NSInteger i = 0; i < points.count; i++) {
        NSValue *value = points[i];
        if (i % 2 == 0) {
            CGContextBeginPath(context);
            CGContextMoveToPoint(context, value.CGPointValue.x, value.CGPointValue.y);
        } else {
            CGContextAddLineToPoint(context, value.CGPointValue.x, value.CGPointValue.y);
            CGContextStrokePath(context);
        }
    }
}

/// Ensure tableView doesn't show through when new stock is added
- (BOOL) isOpaque {
    return YES;
} 

@end
