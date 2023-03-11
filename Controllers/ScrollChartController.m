#import <CoreText/CoreText.h>
#import "ScrollChartController.h"
#import "BigNumberFormatter.h"
#import "CIAppDelegate.h"
#import "StockData.h"
#import "FundamentalAPI.h"
#import "Series.h"

const CGFloat dotPattern[2] = {1.0, 6.0};
const CGFloat dashPattern[2] = {1.0, 1.5};
const CGFloat dotGripColor[4] = {0.5, 0.5, 0.8, 1.0};
const CGFloat lightBlueColor[4] = {0.16, 0.34, 1.0, 1.0};
const CGFloat monthLineColor[4] = {.4, .4, .4, .5};
const CGFloat redMetric[4] = {1., .0, .0, .8};  // needs to be brighter than green

const CGFloat dashPatern[2] =  {1.0,  3.0};

@interface ScrollChartController () <CAAnimationDelegate> {
    CGLayerRef    layerRef;
    CGContextRef  layerContext;
    NSInteger     pressedBarIndex;   // need to track the index so we can compare against the total number of bars
    StockData     *pressedBarStock;  // track full stock object not just symbol so we can check if monthly or weekly
}
@property (strong, nonatomic) NSMutableArray    *stocks;
@property (strong, nonatomic) NSDecimalNumber   *chartPercentChange;
@property (strong, nonatomic) NSDecimalNumber   *two;
@property (strong, nonatomic) NSDecimalNumberHandler *roundDown;
@property (strong, nonatomic) BigNumberFormatter *numberFormatter;
@property (strong, nonatomic) NSArray             *sparklineKeys;
@property (strong, nonatomic) NSDate          *lastNetworkErrorShown;
@end

@implementation ScrollChartController

- (void) dealloc {
    
    for(StockData *stock in self.stocks) {
        [stock release];
    }
    [_stocks release];
    [_numberFormatter release];
    
    CGLayerRelease(layerRef); 
    [super dealloc];
}

- (void) removeStockAtIndex:(NSInteger)i {

    if (i < self.stocks.count) {
        [self.stocks removeObjectAtIndex:i];
    }
}

- (void) resetDimensions {
    svHeight = self.bounds.size.height;
    maxWidth = self.bounds.size.width;
    scaledWidth = maxWidth;
    svWidth = maxWidth - 5. - self.layer.position.x - (30 * [[self.comparison seriesList] count]);
    pxWidth = self.layer.contentsScale * svWidth;
    pxHeight = self.layer.contentsScale * svHeight;
}

- (NSInteger) maxBarOffset {
   return floor((pxWidth)/(xFactor * barUnit));
}

- (void) createLayerContext {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(maxWidth, svHeight), YES, self.layer.contentsScale);
    layerRef = CGLayerCreateWithContext(UIGraphicsGetCurrentContext(), CGSizeMake(self.layer.contentsScale * maxWidth, pxHeight), NULL);
    UIGraphicsEndImageContext();
    layerContext = CGLayerGetContext(layerRef);
    
    CGContextSetTextMatrix(layerContext, CGAffineTransformMake(1.0,0.0, 0.0, -1.0, 0.0, 0.0));  // iOS flipped coordinates
    CGContextSetFontSize(layerContext, 5 * self.layer.contentsScale);
    CGContextSetTextDrawingMode (layerContext, kCGTextFill);
}

- (id) init {
    if (self = [super init]) {
        scaleShift = 0.;
        xFactor = 7.5;
        barUnit = 1.; // daily
        
        [self.layer setContentsScale:UIScreen.mainScreen.scale];
        self.stocks = [[NSMutableArray alloc] init];
       
        [self setRoundDown:[NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundDown scale:0 raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO]];
        
        [self setTwo:[[[NSDecimalNumber alloc] initWithInt:2] autorelease]];
        
        pt2px = 0.5/(self.layer.contentsScale);
        
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
    
    CGContextClearRect(layerContext, CGRectMake(0, 0, self.layer.contentsScale * maxWidth, pxHeight));
    [self setNeedsDisplay];
    
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
    
    self->sparklineHeight = 100 * [self.sparklineKeys count];
    
    for (Series *series in self.comparison.seriesList) {
        StockData *stockData = [StockData alloc];
        [self.stocks addObject:stockData];
        [stockData release];
        [stockData setSeries:series];
        // DLog(@"days Ago %d  for %@", series.daysAgo, series.symbol);
        
        stockData->oldestBarShown = [self maxBarOffset];
        // DLog(@"oldestBarShown %d", stockData->oldestBarShown);
        
        [stockData setDelegate:self];
        [stockData setGregorian:self.gregorian];

        stockData->barUnit = barUnit;
        stockData->xFactor = xFactor * barUnit;
        [stockData setPxHeight:pxHeight withSparklineHeight:sparklineHeight];
    
        [stockData initWithDaysAgo:series->daysAgo];
    }
}

- (void) renderCharts {

    CGContextClearRect(layerContext, CGRectMake(0, 0, self.layer.contentsScale * maxWidth, pxHeight + 5));    
    
    StockData *stock;

    CGContextSetBlendMode(layerContext, kCGBlendModeNormal);
    
    NSDecimalNumber *reportValue = [NSDecimalNumber notANumber];    // init for safety
    CGPoint p;
    NSString *label;
    
    NSInteger dateShift = -1;
    
    if (self.stocks.count > 0) {
        stock = [self.stocks objectAtIndex:0];
        
        dateShift = stock.series->daysAgo + stock->oldestBarShown;
        
        CGContextSetStrokeColor(layerContext, monthLineColor);        
        CGContextSetLineWidth(layerContext, 1.0);   // pIXELs
        CGContextStrokeLineSegments(layerContext, stock->monthLines, stock->monthCount);
        
        
        CGContextSetFontSize(layerContext, 9 * self.layer.contentsScale);
        CGContextSelectFont (layerContext, "HelveticaNeue", 9*self.layer.contentsScale, kCGEncodingMacRoman);
        CGContextSetFillColorWithColor(layerContext, stock.series->upColor);
        
        NSInteger monthLabelIndex = 0;
        CGFloat offset = 10 *  self.layer.contentsScale;
         
        for (NSInteger m = 0; m < stock->monthCount; m++) {
            m++; // 2nd point is chartbase
            
            p = (CGPoint) stock->monthLines[m];
            
            monthLabelIndex = floorf(m/2);
            
            if (monthLabelIndex < [[stock monthLabels] count]) {
                label = [[stock monthLabels] objectAtIndex:monthLabelIndex];
                CGContextShowTextAtPoint(layerContext, p.x, p.y + offset, label.UTF8String, label.length);
            }
        }
    }
    
    // To determine the min and max values for each fundamental metric, first go through all of the stocks
    // and go through their fundamentals, comparing them by key type.
    // Then, if the sparklineCount > 0, go through it again to render the sparklines
    // using a dictionary is preferable because it makes checking for uniqueness and lookups easier
    // ordering of the series can be inforced in a later version
    [self.comparison resetMinMax];
    
    NSInteger stocksWithFundamentals = 0;
    
    for(NSInteger s = self.stocks.count - 1; s >= 0; s--) {    // go backwards so stock[0] draws on top
        
        stock = [self.stocks objectAtIndex:s];
        
        if (stock->oldestBarShown <= 0) {
            continue; // nothing to draw, so skip it
        }
        
        if ([stock fundamentalAPI] != nil) {
            stocksWithFundamentals++;
            for (NSString *key in [[[stock fundamentalAPI] columns] allKeys]) {
                NSInteger r = [stock fundamentalAPI].newestReportInView;
                // DLog(@"checking key %@", key);
                if ([key isEqualToString:@"BookValuePerShare"]) { continue; }
                
                do {
                    reportValue = [[stock fundamentalAPI] valueForReport:r withKey:key];
                    // DLog(@"report value is %@", reportValue);
                    [self.comparison updateMinMaxForKey:key withValue:reportValue];  // handles notANumber

                } while (++r <= [stock fundamentalAPI].oldestReportInView);
            }
        }
        
        CGContextSetStrokeColorWithColor(layerContext, stock.series->upColor);
        CGContextSetLineWidth(layerContext, 1.0);   // pIXELs
        
        if (s == 1 && dateShift != stock.series->daysAgo + stock->oldestBarShown) { // 3rd chart must use same dates as 2nd
    
            dateShift = stock.series->daysAgo + stock->oldestBarShown;
            
            CGContextSetStrokeColor(layerContext, monthLineColor);
            CGContextStrokeLineSegments(layerContext, stock->monthLines, stock->monthCount);
            
            CGContextSetFontSize(layerContext, 9 * self.layer.contentsScale);
            CGContextSetFillColorWithColor(layerContext, stock.series->upColor);
            
            NSInteger monthLabelIndex = 0;
            CGFloat offset = 10 *  self.layer.contentsScale;
            
            for (NSInteger m = 0; m < stock->monthCount; m++) {
                m++; // 2nd point is chartbase
                
                p = (CGPoint) stock->monthLines[m];
                
                monthLabelIndex = floorf(m/2);
                
                if (monthLabelIndex < [[stock monthLabels] count]) {
                    label = [[stock monthLabels] objectAtIndex:monthLabelIndex];
                    CGContextShowTextAtPoint(layerContext, p.x, p.y + offset * (s + 1), [label UTF8String], [label length]);
                } else {
                   // DLog(@"Missing month label for index %d", monthLabelIndex);
                }
            }
        }
        
        if ([[stock bookValue] isEqualToNumber:[NSDecimalNumber notANumber]] == NO) {
                    
            NSInteger r = [stock fundamentalAPI].newestReportInView;
            CGContextSaveGState(layerContext);
            CGContextBeginPath(layerContext);
            
            CGFloat y = 0.;
            BOOL firstReport = YES;
            
            while ((reportValue = [[stock fundamentalAPI] valueForReport:r withKey:@"BookValuePerShare"]) && r < [stock fundamentalAPI].oldestReportInView) {
                
                if ([reportValue isEqualToNumber:[NSDecimalNumber notANumber]]) {
                    r++;
                    continue;
                }
                y = stock->yFactor * [[stock.maxHigh decimalNumberBySubtracting:reportValue] doubleValue];
                
                if (firstReport) {  // first report
                    CGContextMoveToPoint(layerContext, stock->fundamentalAlignments[r], y + sparklineHeight);
                    firstReport = NO;
                } else {
                    CGContextAddLineToPoint(layerContext, stock->fundamentalAlignments[r], y + sparklineHeight);
                }
                r++;
            }    
            CGContextSetLineWidth(layerContext, 5.);
            CGContextSetShadowWithColor(layerContext, CGSizeMake(0., 5.), 0.5, stock.series->upColorHalfAlpha);
            CGContextSetStrokeColorWithColor(layerContext, stock.series->upColorHalfAlpha);
            CGContextStrokePath(layerContext);  
            CGContextRestoreGState(layerContext);
        }
        
        if (stock->movingAvg1Count > 2) {
            CGContextSetStrokeColorWithColor(layerContext, stock.series->colorInverseHalfAlpha);
            CGContextBeginPath(layerContext);
            CGContextAddLines(layerContext, stock->movingAvg1, stock->movingAvg1Count);
            CGContextStrokePath(layerContext);
        }
        
        if (stock->movingAvg2Count > 2) {
            CGContextSetStrokeColorWithColor(layerContext, stock.series->upColorHalfAlpha);
            CGContextBeginPath(layerContext);
            CGContextAddLines(layerContext, stock->movingAvg2, stock->movingAvg2Count);
            CGContextStrokePath(layerContext);
        }

        if (stock->bbCount > 2) {
            CGContextSetLineDash(layerContext, 0., dashPattern, 2);
            CGContextSetStrokeColorWithColor(layerContext, stock.series->upColor);
            CGContextBeginPath(layerContext);
            CGContextAddLines(layerContext, stock->ubb, stock->bbCount);
            CGContextStrokePath(layerContext);

            CGContextBeginPath(layerContext);
            CGContextAddLines(layerContext, stock->lbb, stock->bbCount);
            CGContextStrokePath(layerContext);
            
            CGContextBeginPath(layerContext);
            CGContextAddLines(layerContext, stock->mbb, stock->bbCount);
            CGContextStrokePath(layerContext);
            CGContextSetLineDash(layerContext, 0, NULL, 0);    // reset to solid
        }
        
        CGContextSetStrokeColorWithColor(layerContext, stock.series->upColor);
        
        CGContextSetLineWidth(layerContext, 1.0 * self.layer.contentsScale);   // pIXELs
        
        CGContextSetFillColorWithColor(layerContext, stock.series->color);
        CGContextSetStrokeColorWithColor(layerContext, stock.series->color);
        
        if (stock->redPointCount > 0) {
            CGContextStrokeLineSegments(layerContext, stock->redPoints, stock->redPointCount);
        }
        
        if (stock->redBarCount > 0) {
            
            for (NSInteger r = 0; r < stock->hollowRedCount; r++) {
                CGContextStrokeRect(layerContext, stock->hollowRedBars[r]);
            }
            CGContextFillRects(layerContext, stock->redBars, stock->redBarCount);
        }
        
        CGContextSetStrokeColorWithColor(layerContext, stock.series->upColor);
        
        if (stock->whiteBarCount > 0) {
            for (NSInteger r = 0; r < stock->whiteBarCount; r++) {
                CGContextStrokeRect(layerContext, stock->greenBars[r]);
            }    
            
            CGContextSetFillColorWithColor(layerContext, stock.series->upColor);
            CGContextFillRects(layerContext, stock->filledGreenBars, stock->filledGreenCount);
        }
        
        CGContextSetFillColorWithColor(layerContext, stock.series->colorHalfAlpha);
        CGContextFillRects(layerContext, stock->redVolume, stock->redCount);
        
        CGContextSetFillColorWithColor(layerContext, stock.series->upColorHalfAlpha);
        CGContextFillRects(layerContext, stock->blackVolume, stock->blackCount);

        
        switch (stock.series->chartType) {
            case 0:
            case 1:
                CGContextSetBlendMode(layerContext, kCGBlendModeNormal);
                CGContextStrokeLineSegments(layerContext, stock->points, stock->pointCount);
                break;
            
            case 2:
                CGContextStrokeLineSegments(layerContext, stock->points, stock->pointCount);
                break;
            case 3:
                CGContextBeginPath(layerContext);
                CGContextAddLines(layerContext, stock->points, stock->pointCount);
                CGContextSetLineJoin(layerContext, kCGLineJoinRound);
                CGContextStrokePath(layerContext);
                break;
        }
            
        CGContextSetFillColorWithColor(layerContext, stock.series->upColor);
        
        [self.numberFormatter setMaximumFractionDigits:0];
        
        CGFloat fontSize;
        
        if ([[stock maxHigh] doubleValue] < 9999) {
            if ([[stock maxHigh] doubleValue] < 100) {
                [self.numberFormatter setMaximumFractionDigits:2];
            }
            fontSize = 10 * self.layer.contentsScale;
        } else if ([[stock maxHigh] doubleValue] < 99999) {
            fontSize = 8 * self.layer.contentsScale;
        } else {
            fontSize = 7 * self.layer.contentsScale;
        }
        
        CGContextSetFontSize(layerContext, fontSize);
        
        CGFloat x = pxWidth + (s + .15) * 30 * self.layer.contentsScale;
        
        /* Algorithm for displaying price increments: show actual high and low.  No need to show scaled low
         
         Ensure that there is enough space in between incements.  
         
         Show increments in rounded amounts (e.g., 550, 560, 570, etc.)
         
         To do this we need to use NSDecimalNumber for precision.
         
         Note that even the increment needs to be an NSDecimalNumber for penny stocks.
         */
        
        NSDecimalNumber *range = [[stock maxHigh] decimalNumberBySubtracting:[stock scaledLow]];
        
        NSDecimalNumber *increment, *avoidLabel, *nextLabel;

        if ([range doubleValue] > 1000) {
            increment = [[[NSDecimalNumber alloc] initWithInt:10000] autorelease];
            
            while ([[range decimalNumberByDividingBy:increment withBehavior:self.roundDown] doubleValue] < 4.) {   
                // too many labels
                increment = [increment decimalNumberByDividingBy:self.two];
            }
            
        } else if ([range doubleValue] > 20) {
            increment = [[[NSDecimalNumber alloc] initWithInt:5] autorelease];
            
            while ([[range decimalNumberByDividingBy:increment withBehavior:self.roundDown] doubleValue] > 10.) {   
                // too many labels
                increment = [increment decimalNumberByMultiplyingBy:self.two];
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
        
        avoidLabel = stock.lastPrice;
        
//        // Optional: show book value on yAxis
//        if ([stock.bookValue isEqualToNumber:[NSDecimalNumber notANumber]] == NO) {
//            [self writeLabel:stock.bookValue forStock:stock atX:x showBox:YES];
//        }
        
        if (15 < fabs(stock->yFactor * [[stock.maxHigh decimalNumberBySubtracting:stock.lastPrice] doubleValue])) {
            // lastPrice is lower than maxHigh
            [self writeLabel:stock.maxHigh forStock:stock atX:x showBox:NO];
            avoidLabel = stock.maxHigh;
        }
        
        nextLabel = [[stock.maxHigh decimalNumberByDividingBy:increment withBehavior:self.roundDown] decimalNumberByMultiplyingBy:increment];
        
        if ([stock.maxHigh compare:stock.lastPrice] == NSOrderedDescending) {
            [self writeLabel:stock.lastPrice forStock:stock atX:x showBox:YES];
            
            if (15 > fabs(stock->yFactor * [[stock.lastPrice decimalNumberBySubtracting:nextLabel] doubleValue])) {
                nextLabel = [nextLabel decimalNumberBySubtracting:increment];       // go to next label
            }
        }
                
        while ([nextLabel compare:stock.minLow] == NSOrderedDescending) {
            
            if (15 < fabs(stock->yFactor * [[avoidLabel decimalNumberBySubtracting:nextLabel] doubleValue])) {
                [self writeLabel:nextLabel forStock:stock atX:x showBox:NO];
            }

            nextLabel = [nextLabel decimalNumberBySubtracting:increment];
            
            if (20 > fabs(stock->yFactor * [[stock.lastPrice decimalNumberBySubtracting:nextLabel] doubleValue])) {                                
                avoidLabel = stock.lastPrice;
            } else {
                avoidLabel = stock.minLow;
            }
        }
        
        // If last price is near the minLow, skip minLow (e.g. RIMM)
        if (15 < fabs(stock->yFactor * [[stock.minLow decimalNumberBySubtracting:stock.lastPrice] doubleValue])) {
            [self writeLabel:stock.minLow forStock:stock atX:x showBox:NO];
        }
    }
    
    NSDecimalNumber *sparkHeight = [[[NSDecimalNumber alloc] initWithDouble:(90)] autorelease];
    double qWidth = xFactor * 60;   // use SCC xFactor to avoid having to divide by barUnit
  
    double h = 0., yNegativeAdjustment = 0., y = [sparkHeight doubleValue], yLabel = 15;
    
    for (NSString *key in self.sparklineKeys) { // go through keys in order in case one series has the key turned off
        NSDecimalNumber *range = [self.comparison rangeForKey:key];   
        if ([range isEqualToNumber:[NSDecimalNumber notANumber]] || [range isEqualToNumber:[NSDecimalNumber zero]]) {
            continue; // skip it
        }
        
        NSDecimalNumber *sparklineYFactor;
        
        sparklineYFactor = [sparkHeight decimalNumberByDividingBy:range];

        if ([[self.comparison minForKey:key] compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
            
            if ([[self.comparison maxForKey:key] compare:[NSDecimalNumber zero]] == NSOrderedAscending) {

                yNegativeAdjustment = -1 * [sparkHeight doubleValue];
            } else {
                yNegativeAdjustment = [[[self.comparison minForKey:key] decimalNumberByMultiplyingBy:sparklineYFactor] doubleValue];
            }
            
            y += yNegativeAdjustment;
        }
        NSString *title = nil, *label = nil;
        CGPoint labelPosition = CGPointZero;
       
        for (StockData *stock in self.stocks) {
            
            if ([stock.series.fundamentalList rangeOfString:key].length < 3) {
                continue;
            }
            
            if (stock->oldestBarShown > 0 && [stock fundamentalAPI] != nil) {
                CGContextSetFillColorWithColor(layerContext, [stock series]->upColorHalfAlpha);

                NSInteger r = [stock fundamentalAPI].newestReportInView;
                if (title == nil) {
                    title = [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] titleForKey:key];
                    CGFloat x = MIN(pxWidth + 5, stock->fundamentalAlignments[r] + 10);
                    CGContextSetFillColorWithColor(layerContext, [stock series]->upColor);
                    CGContextShowTextAtPoint (layerContext, x, yLabel, [title UTF8String], [title length]);
                }
            
                for (/* r = newestReportInView  */; r < stock.fundamentalAPI.oldestReportInView && stock->fundamentalAlignments[r] > 0; r++) {
                    
                    reportValue = [[stock fundamentalAPI] valueForReport:r withKey:key];
            
                    if ([reportValue isEqualToNumber:[NSDecimalNumber notANumber]]) {
                        continue;
                    }
                    qWidth = stock->fundamentalAlignments[r] - stock->fundamentalAlignments[r + 1] - 3;
                    
                    if (qWidth < 0 || stock->fundamentalAlignments[r + 1] < 1.) {
                        qWidth = MIN(stock->fundamentalAlignments[r], stock->xFactor * 60/barUnit) ;
                    }
                    h = [[reportValue decimalNumberByMultiplyingBy:sparklineYFactor] doubleValue];
                    
                    if ([reportValue compare:[NSDecimalNumber zero]] == NSOrderedAscending) {   // negative value
                        labelPosition.y = y + 18;  // subtracting the height pushes it too far down
                        CGContextSetFillColor(layerContext, redMetric);
                    } else {
                        labelPosition.y = y + 18 - h;
                        CGContextSetFillColorWithColor(layerContext, [stock series]->upColorHalfAlpha);
                    }
                    
                    CGContextSetBlendMode(layerContext, kCGBlendModeNormal);
                    CGContextFillRect(layerContext, CGRectMake(stock->fundamentalAlignments[r], y, -qWidth, -h));
                                        
                    if (barUnit < 5. && stocksWithFundamentals == 1) {     // don't show labels for monthly or comparison charts
                        label = [self.numberFormatter formatFinancial:reportValue withXfactor:xFactor];
                        CGContextSetBlendMode(layerContext, kCGBlendModePlusLighter);
                    
                        labelPosition.x = stock->fundamentalAlignments[r] - 11.5 * label.length;
                        
                        CGContextShowTextAtPoint(layerContext, labelPosition.x, labelPosition.y, label.UTF8String, label.length);
                    }
                }                
            }
        }
        y += 10 + [sparkHeight doubleValue] - yNegativeAdjustment;
        yLabel += 10 + [sparkHeight doubleValue];
        yNegativeAdjustment = 0.;
    }
    [self setNeedsDisplay];
}

- (void) drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] chartBackground].CGColor);
    
    CGContextFillRect(ctx, CGRectMake(0, 0, self.layer.contentsScale * maxWidth, pxHeight + 5));    // labels and moving averages extend outside pxHeight and leave artifacts
    
    CGContextDrawLayerInRect(ctx, CGRectMake(5 + scaleShift, 5, scaledWidth, svHeight), layerRef);

    // Draw left-hand draggable line between tableview and chart area
    CGContextSetStrokeColor(ctx, dotGripColor);
    CGContextSetLineWidth(ctx, 1.0);   // pIXELs
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 0.5, 0);
    CGContextAddLineToPoint(ctx, 0.5, svHeight);
    CGContextStrokePath(ctx);
}

/* Transforms chart during pinch/zoom gesture and to calculate scaleShift for final shiftRedraw */
- (void) resizeChartImage:(CGFloat)newScale withCenter:(CGFloat)touchMidpoint {
    
    CGFloat scaleFactor = xFactor * newScale;
    
    if (scaleFactor <= .25) {
        scaleFactor = .25;
        newScale = .25/xFactor;
        
    } else if (scaleFactor > 50) { // too zoomed in, so make no change
        scaleFactor = 50;
        newScale = 50/xFactor;
    }
    
    if (scaleFactor == xFactor) {
        return; // prevent strange pan when zoom hits max or mix
    }
  
    scaleShift = touchMidpoint * (1 - newScale);        // shift image by scaled change to touch midpoint
    
    scaledWidth = maxWidth * newScale;                  // scale image
    
    [self setNeedsDisplay];
}

// Uses scaleShift set by resizeChartImage so the rendered chart matches the temporary transformation
- (void) resizeChart:(CGFloat)newScale {
    
    scaledWidth = maxWidth;     // reset buffer output width after temporary transformation
    
    CGFloat newXfactor = xFactor * newScale;
        
    // Keep scc.xFactor and scc.barUnit separate and multiply them together for StockData.xFactor
    
    if (newXfactor < 1.) {
        barUnit = 19.;              // switch to monthly
        
        if (newXfactor < .25) {
            newXfactor = .25;   // minimum size for monthly charting
        }
    } else if (newXfactor < 3) {
        barUnit = 4.5;          // switch to weekly

    } else if (barUnit == 19. && newXfactor  * barUnit > 20.) {
        barUnit = 4.5;              // switch to weekly
        
    } else if (barUnit == 4.5 && newXfactor  * barUnit > 10. ) {
        barUnit = 1.;               // switch to daily

    }  else if (newXfactor > 50) { // too small, so make no change
        newXfactor = 50;
    }
    
    NSInteger shiftBars = floor(self.layer.contentsScale*scaleShift /( barUnit * newXfactor));
    scaleShift = 0.;
    
    if (newXfactor == xFactor) {
        return; // prevent strange pan when zoom hits max or mix
    }

    xFactor = newXfactor;
    
    NSDecimalNumber *percentChange;
    
    [self setChartPercentChange:[NSDecimalNumber zero]];
    
    for(StockData *stock in self.stocks) {
        
        stock->xFactor = xFactor * barUnit;
    
        if (stock->barUnit != barUnit) {
             
            [stock setNewestBarShown:floor(stock->newestBarShown * stock->barUnit / barUnit)];
            stock->oldestBarShown = floor(stock->oldestBarShown * stock->barUnit / barUnit);

            stock->barUnit = barUnit;
           
            [stock summarizeByDateFrom:0 oldBars:0];
            [stock updateHighLow];      // must be a separate call to handle shifting
        }
        
        [stock setPxHeight:pxHeight withSparklineHeight:sparklineHeight];
        
        percentChange = [stock shiftRedraw:shiftBars withBars:[self maxBarOffset]];
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
    
    for(StockData *stock in self.stocks) {
        
        if (barsShifted == 0) {
            outOfBars = NO;
        } else if (barsShifted > 0 && barsShifted < stock->bars - stock.newestBarShown) {
            outOfBars = NO;
        } else if (barsShifted < 0 && stock->oldestBarShown > abs((int)barsShifted)) {
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
    CGLayerRelease(layerRef);       // release old context and get a new one
    [self createLayerContext];
    
    [self setChartPercentChange:[NSDecimalNumber zero]];
    
    for(StockData *stock in self.stocks) {
        [stock setPxHeight:pxHeight withSparklineHeight:sparklineHeight];
        stock->xFactor = xFactor * barUnit;
        [stock setNewestBarShown:(stock->oldestBarShown - [self maxBarOffset])];
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
     
    CGFloat y = s->yFloor - s->yFactor * [price doubleValue] + 20;    
    
    y = [s pxAlign:y alignTo:0.5];
    x = [s pxAlign:x alignTo:0.5];
    
    CGContextShowTextAtPoint (layerContext, x, y, [l UTF8String], [l length]);
    
    if (showBox) {
        CGPoint textPosition = CGContextGetTextPosition(layerContext);
                
        CGContextSetStrokeColorWithColor(layerContext,s.series->upColorHalfAlpha);
        CGContextStrokeRect(layerContext, CGRectMake(x - 0.5, y - 9*UIScreen.mainScreen.scale, textPosition.x - x, 10*UIScreen.mainScreen.scale));
     }
}

// To remember the last valid bar pressed, pressedBarIndex is only reset when the touch down begins
- (void) resetPressedBar {
    pressedBarIndex = -1;
    pressedBarStock = nil;
}

- (UIImage *) screenshot {
    
    CGFloat fullWidth = svWidth + (30 * [[self.comparison seriesList] count]);
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(fullWidth, 20 + svHeight), YES, self.layer.contentsScale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetTextMatrix(context, CGAffineTransformMake(1.0,0.0, 0.0, -1.0, 0.0, 0.0));  // iOS flipped coordinates
    CGContextSetFontSize(layerContext, 10 * self.layer.contentsScale);
    CGContextSetTextDrawingMode (context, kCGTextFill);
    
    CGContextSetFillColorWithColor(context, [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] chartBackground].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, fullWidth, svHeight + 40));
    
    if (self.layer.contentsScale == 2.) {
        CGContextScaleCTM(context, 0.5, 0.5);
    }
    
    CGContextDrawLayerAtPoint(context, CGPointMake(0, 30), layerRef);
    
    CGFloat x = 2.;
    NSString *label;
    for (StockData *stock in self.stocks) {
        CGContextSetFillColorWithColor(context, stock.series->upColor);

        label = [NSString stringWithFormat:@"%@ ", stock.series.symbol];
    
        if (barUnit > 18) {
            label = [label stringByAppendingString:@"monthly "];
        } else if (barUnit > 4) {
            label = [label stringByAppendingString:@"weekly "];
        }
        CGContextShowTextAtPoint(context, x * self.layer.contentsScale, 20., [label UTF8String], [label length]);
        x += 3 * label.length * self.layer.contentsScale;
        label = @"";
    }
    
    label = @" on Chart Insight app";
    
    CGContextShowTextAtPoint(context, x * self.layer.contentsScale, 20., [label UTF8String], [label length]);
        
     UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
     UIGraphicsEndImageContext();
     return screenshot;
}


- (UIImage *) magnifyBarAtX:(CGFloat)x y:(CGFloat)y {
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(100, 100), NO, self.layer.contentsScale);    
    CGContextRef lensContext = UIGraphicsGetCurrentContext();
    
    CGContextSetTextMatrix(lensContext, CGAffineTransformMake(1.0,0.0, 0.0, -1.0, 0.0, 0.0));  // iOS flipped coordinates
    CGContextSelectFont (lensContext, "HelveticaNeue", 5 * self.layer.contentsScale, kCGEncodingMacRoman);
    CGContextSetTextDrawingMode (lensContext, kCGTextFill);
    
    CGContextSetFillColorWithColor(lensContext, [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] chartBackground].CGColor);
    CGContextFillRect(lensContext, CGRectMake(0, 0, 100., 100.));
    
    CGFloat yPressed = y * self.layer.contentsScale;
    
    x = (x - 25.) * self.layer.contentsScale;      // subtract 25. to make the touch point the center of the lens, not the top left corner
    y = (y - 25.) * self.layer.contentsScale;
       
    CGFloat scale = UIScreen.mainScreen.scale;
    
    if (scale == 1.) {
        CGContextScaleCTM(lensContext, 2., 2.); 
    }
    
    CGContextDrawLayerAtPoint(lensContext, CGPointMake(-x,-y), layerRef);
    
    NSString *label = @"";
    
    CGFloat centerX = x + 25. * scale - xFactor * barUnit / 2; // because xRaw starts at xFactor/2
        
    CGContextSetBlendMode(lensContext, kCGBlendModeNormal);
        
    for (StockData *stock in self.stocks) {

        if (stock->oldestBarShown - roundf(centerX/(xFactor * barUnit)) >= 0) {
        
            pressedBarIndex = stock->oldestBarShown - roundf(centerX/(xFactor * barUnit));        // only overwrite pressedBarIndex if its valid
            
            BOOL upClose = YES;
            BarStruct          *pressedBar = [stock barAtIndex:pressedBarIndex setUpClose:&upClose];
            
            if (pressedBar != nil) {
                pressedBarStock = stock;        // save for UIMenuController
                
                BarStruct bar = *pressedBar; // dereference pointer
        
                CGFloat barHigh = stock->yFloor - stock->yFactor * bar.high;
                CGFloat barLow = stock->yFloor - stock->yFactor * bar.low;
                
                if (yPressed < barLow && yPressed > barHigh) {
                    
                    // reduce opacity by filling .25 alpha background over image so scope values are clearer
                    CGContextSetFillColorWithColor(lensContext,
                                                   CGColorCreateCopyWithAlpha([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] chartBackground].CGColor, 0.25));
                    CGContextFillRect(lensContext, CGRectMake(0., 0., 100., 100.));
                    
                    CGContextSetStrokeColorWithColor(lensContext, (upClose ? stock.series->upColor : stock.series->color));
                    CGContextSetLineWidth(lensContext, UIScreen.mainScreen.scale);
                    CGContextSetShadow(lensContext, CGSizeMake(.5, .5), 0.75);
                    [self.numberFormatter setMaximumFractionDigits: (bar.high > 100 ? 0 : 2)];
                    
                    label = [stock monthName:bar.month];
                    
                    if (barUnit < 19) {
                        label = [label stringByAppendingFormat:@"%ld", bar.day];
                    } else {
                        label = [label stringByAppendingString:@"'"];   // append this before substringFromIndex on year
                        label = [label stringByAppendingString:[[NSString stringWithFormat:@"%ld", bar.year] substringFromIndex:2]];
                    }
                    
                    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground]) {
                        [[UIColor whiteColor] setFill];
                    } else {
                        [[UIColor blackColor] setFill];
                    }
                    CGContextShowTextAtPoint(lensContext, 16.* scale, 7. * scale, [label UTF8String], [label length]);        // bar date
                    
                    double scopeFactor = (bar.high > bar.low) ? 31. * scale / (bar.high - bar.low) : 0;
                    double midPoint = (bar.high + bar.low)/2.;
                    
                    label = [self.numberFormatter stringFromNumber:[NSNumber numberWithDouble:bar.open]];
                    double y = 27.5 * scale + scopeFactor * (midPoint - bar.open);
                    CGContextShowTextAtPoint(lensContext, 10. * scale, y, [label UTF8String], [label length]);
                    
                    y = (y < 27.5 * scale) ? y + 2.5 * scale : y - 5. * scale;                               // avoid text
                    CGContextMoveToPoint(lensContext, 20. * scale, y);
                    CGContextAddLineToPoint(lensContext, 25. * scale, y);
                
                    label = [self.numberFormatter stringFromNumber:[NSNumber numberWithDouble:bar.high]];
                    y = 27.5 * scale + scopeFactor * (midPoint - bar.high);
                    CGContextShowTextAtPoint(lensContext, 22. * scale, y, [label UTF8String], [label length]);

                    y = (y < 27.5 * scale) ? y + 2.5 * scale : y - 5.* scale;                               // avoid text
                    CGContextMoveToPoint(lensContext, 25. * scale, y);
                    
                    label = [self.numberFormatter stringFromNumber:[NSNumber numberWithDouble:bar.low]];
                    y = 27.5*scale + scopeFactor * (midPoint - bar.low);
                    CGContextShowTextAtPoint(lensContext, 22. * scale, y, [label UTF8String], [label length]);
                    
                    y = (y < 27.5*scale) ? y + 2.5*scale : y - 5. * scale;                                // avoid text
                    CGContextAddLineToPoint(lensContext, 25.*scale, y);
                    
                    label = [self.numberFormatter stringFromNumber:[NSNumber numberWithDouble:bar.close]];                    
                    y = 27.5 * scale + scopeFactor * (midPoint - bar.close);
                    CGContextShowTextAtPoint(lensContext, 33.*scale, y, [label UTF8String], [label length]);
                    
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

- (NSDictionary *) infoForPressedBar {
    if (pressedBarIndex >= 0 && pressedBarStock != nil) {
        return [pressedBarStock infoForBarAtIndex:pressedBarIndex];
    }
    return nil;
}

- (void) requestFailedWithMessage:(NSString *)message {

    [self.progressIndicator stopAnimating]; 

    // DLog(@"RequestFailed so stopping progressIndicator because ERROR %@ and last error %f", message, [[NSDate date] timeIntervalSinceDate:self.lastNetworkErrorShown]);
}

- (void) requestFinished:(NSDecimalNumber *)newPercentChange {
    
    NSInteger chartsReady = 0;
    
    for(StockData *stock in self.stocks) {
        if (stock->ready == YES) {
            chartsReady++;
        } else {
           // DLog(@"requestFinished but %@ is NOT READY", stock.series.symbol);
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
