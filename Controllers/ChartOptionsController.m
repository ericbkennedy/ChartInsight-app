#import "ChartOptionsController.h"
#import "AddFundamentalController.h"
#import "CIAppDelegate.h"     // for chart type list

enum indicatorType {  MOVING_AVERAGE, BOOK_OVERLAY, SAWTOOTH   };

@interface ChartOptionsController () {
    NSInteger fundamentalControlRow;
}

@property (strong, nonatomic) UIColor *color;
@property (strong, nonatomic) UIColor *upColor;
@property (strong, nonatomic) UIButton *defaultsButton;
@property (strong, nonatomic) UIBarButtonItem *saveButton;  // appears only when the date picker is open
@property (strong, nonatomic) NSArray *sections;
@property (nonatomic, copy) NSString *fundamentalDescription;
@property (strong, nonatomic) NSDateComponents *days;
@property (strong, nonatomic) UIDatePicker *datePicker; 
@property (strong, nonatomic) UISegmentedControl *typeSegmentedControl;
@property (strong, nonatomic) UISegmentedControl *colorSegmentedControl;
@property (strong, nonatomic) UIButton *tapWhenFinished;
@property (strong, nonatomic) NSString *listedMetricKeyString;
@property (strong, nonatomic) NSMutableArray *listedMetricKeys;
@property (strong, nonatomic) NSMutableArray *listedMetricValues;   // parallel array to preserve sort

@end
@implementation ChartOptionsController

- (void)viewDidUnload {
    [super viewDidUnload];
	self.sections = nil;        // Release any retained subviews of the main view.
}

- (id) initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self != nil) {
        fundamentalControlRow = -1;
        [self setListedMetricKeys:[NSMutableArray new]];
        [self setListedMetricValues:[NSMutableArray new]];
        [self setListedMetricKeyString:@"BasicEPSTotal,BookValuePerShare,"];
        
        // better to have a separate dateFormatter than alter the style of the AppDelegate one used for API parsing
        [self setDateFormatter:[[NSDateFormatter alloc] init]];
        [self.dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [self.dateFormatter setTimeStyle:NSDateFormatterNoStyle];
    }
    return self;
}

- (void)dealloc {	
    _delegate = nil;
    [_saveButton release];
    [_colorSegmentedControl release];
    [_typeSegmentedControl release];
    [_dateFormatter release];
	[_days release];
    if (_datePicker != nil) {
        [_datePicker release];
    }
	[super dealloc];
}

- (NSArray *) metrics {
    return [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] metrics]; 
}

+ (NSArray *)chartTypes {
    return [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] chartTypes];
}

+ (NSArray *)chartColors {
    return [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] colors];
}

- (UIImage *)imageForChartType:(NSInteger)type andColor:(NSInteger)c showLabel:(BOOL)showLabel {
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(32, 32), NO, UIScreen.mainScreen.scale);
    CGColorRef thisUpColor, thisDownColor;
    
    thisUpColor = thisDownColor = [[[ChartOptionsController chartColors] objectAtIndex:c] CGColor];
    
    if (c == 0) {
        thisDownColor = [UIColor colorWithRed:1. green:.0 blue:.0 alpha:1.0].CGColor;    // red
    }
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
        
    CGContextSetLineWidth(ctx, UIScreen.mainScreen.scale);
    
    CGContextSetStrokeColorWithColor(ctx, thisUpColor);
    
    if (type < 3) {

        CGFloat HL = type < 2 ? 13 : 0;
        
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, 11.5, 1);
        CGContextAddLineToPoint(ctx, 11.5, 7);
        CGContextStrokePath(ctx);
        
        CGContextMoveToPoint(ctx, 11.5, 20 - HL);
        CGContextAddLineToPoint(ctx, 11.5, 23);
        CGContextStrokePath(ctx);
        
        CGContextMoveToPoint(ctx, 28.5, 11 - HL);
        CGContextAddLineToPoint(ctx, 28.5, 14);
        CGContextStrokePath(ctx);
        
        if (type < 2) {
            
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 11.5, 6);
            CGContextAddLineToPoint(ctx, 15.5, 6);
            CGContextStrokePath(ctx);
            
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 28.5, 1);
            CGContextAddLineToPoint(ctx, 32, 1);
            CGContextStrokePath(ctx);
        
            if (type == 0) { // add open
                
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, 7.5, 19);
                CGContextAddLineToPoint(ctx, 11.5, 19);
                CGContextStrokePath(ctx);
                
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, 24.5, 11);
                CGContextAddLineToPoint(ctx, 28.5, 11);
                CGContextStrokePath(ctx);   
                
                CGContextSetStrokeColorWithColor(ctx, thisDownColor);
                
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, 0, 1);
                CGContextAddLineToPoint(ctx, 3, 1);
                CGContextStrokePath(ctx);
                
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, 17, 6);
                CGContextAddLineToPoint(ctx, 20, 6);
                CGContextStrokePath(ctx);        
            }
            
            CGContextSetStrokeColorWithColor(ctx, thisDownColor);

            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 3, 0);
            CGContextAddLineToPoint(ctx, 3, 20);
            CGContextStrokePath(ctx);
            
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 3, 19);
            CGContextAddLineToPoint(ctx, 6, 19);
            CGContextStrokePath(ctx);
            
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, 19, 11);
            CGContextAddLineToPoint(ctx, 24, 11);
            CGContextStrokePath(ctx); 
            
        } else if (type == 2) {    // candlestick
            
            CGContextStrokeRect(ctx, CGRectMake(9, 6, 5, 13));
            
            CGContextStrokeRect(ctx, CGRectMake(26, 1, 5, 10));
            
            CGContextSetFillColorWithColor(ctx, thisDownColor);
            CGContextFillRect(ctx, CGRectMake(0, 0, 6, 20));
            CGContextFillRect(ctx, CGRectMake(17, 5, 6, 7));            
        }
        CGContextSetStrokeColorWithColor(ctx, thisDownColor);        
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, 20, 2);
        CGContextAddLineToPoint(ctx, 20, 19);        
        CGContextStrokePath(ctx);
    } else {
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, 0, 1);
        CGContextAddLineToPoint(ctx, 3, 20);
        CGContextAddLineToPoint(ctx, 11.5, 6);
        CGContextAddLineToPoint(ctx, 19, 11);
        CGContextAddLineToPoint(ctx, 28.5, 1);        

        CGContextStrokePath(ctx);
    }
    
    if (showLabel) {
        CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,0.0, 0.0, -1.0, 0.0, 0.0));  // iOS flipped coordinates
         CGContextSetFontSize(ctx, 10.0);
        CGContextSelectFont (ctx, "HelveticaNeue", 10.0, kCGEncodingMacRoman);
        CGContextSetTextDrawingMode (ctx, kCGTextFill);
        [[UIColor whiteColor] setFill];
        NSString *label = [[ChartOptionsController chartTypes] objectAtIndex:type];

        CGContextShowTextAtPoint(ctx, 6 - label.length, 32, label.UTF8String, label.length);
    }
     
    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    if ([UIDevice.currentDevice.systemVersion compare:@"7" options:NSNumericSearch] == NSOrderedDescending) {
         return [screenshot imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    } else {
        return screenshot;
    }
}

- (UIImage *)imageForOverlayType:(NSInteger)type andColor:(CGColorRef)c {
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(40, 40), NO, UIScreen.mainScreen.scale);
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSetStrokeColorWithColor(ctx, c);    
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextBeginPath(ctx);
    CGContextSetLineWidth(ctx, 1.0);
    
    switch (type) {
        case MOVING_AVERAGE:
            // Use the function CGContextAddCurveToPoint to append a cubic Bézier curve from the current point,
            // using control points and an endpoint. If the control points are both above the starting and ending points,
            // the curve arches upward. If the control points are both below the start and end points, the curve arches downward.
            CGContextMoveToPoint(ctx, 1, 20);
            CGContextAddCurveToPoint(ctx, 15, 35, 25, 15, 40, 13);    
            CGContextStrokePath(ctx);
            break;
        case BOOK_OVERLAY:
            
            CGContextMoveToPoint(ctx, 1, 20);
            CGContextAddLineToPoint(ctx, 9, 19);
            CGContextAddLineToPoint(ctx, 17, 16);
            CGContextAddLineToPoint(ctx, 25, 17);
            CGContextAddLineToPoint(ctx, 33, 15);
            CGContextAddLineToPoint(ctx, 40, 16);
            
            CGContextSetLineWidth(ctx, 2.5);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0., 2.5), 0.5, c);
            CGContextSetStrokeColorWithColor(ctx, c);
            CGContextStrokePath(ctx);
            break;
            
        case SAWTOOTH:
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:1. green:0. blue:0. alpha:0.6].CGColor);
            CGContextFillRect(ctx, CGRectMake(13, 20, 5, 3));             

            CGContextSetFillColorWithColor(ctx, c);
            CGContextFillRect(ctx, CGRectMake(1, 13, 5, 7)); 
            CGContextFillRect(ctx, CGRectMake(7, 16, 5, 4)); 
            CGContextFillRect(ctx, CGRectMake(19, 10, 5, 10));
            CGContextFillRect(ctx, CGRectMake(25, 8, 5, 12)); 
            CGContextFillRect(ctx, CGRectMake(31, 5, 5, 15));
            break;
    }
            
    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return screenshot;
}

- (void) renderColorSegments {
    NSArray *colorList = [ChartOptionsController chartColors];
    UIColor *thisUpColor;    
    [self.colorSegmentedControl removeAllSegments];
    
    for (NSInteger i = 0; i < colorList.count; i++) {
        thisUpColor = [colorList objectAtIndex:i];
        
        [self.colorSegmentedControl insertSegmentWithImage:[self imageForChartType:self.series->chartType andColor:i showLabel:NO] atIndex:i animated:NO];
        if ([self.series matchesColor:thisUpColor]) {
            [self.colorSegmentedControl setSelectedSegmentIndex: i];
        }
    }
}

- (CGFloat) segmentWidth:(UIInterfaceOrientation)toOrientation {
    CGFloat width = 320;
    
    if (UIDeviceOrientationIsLandscape(toOrientation)) {
        if ([UIScreen mainScreen].bounds.size.height == 480) {
            width = 480;
        } else if ([UIScreen mainScreen].bounds.size.height == 568) {
            width = 568;    // TODO: test this on the iPhone 5 in landscape mode
        }
    }
    return width - 18.;
}

- (void) updateListedMetrics {
    
    for (NSArray *category in [self metrics]) {
        for (NSArray *metric in category) {
            NSString *key = [metric objectAtIndex:0];
            if ([self.listedMetricKeyString rangeOfString:key].length > 0) {
                [self.listedMetricKeys addObject:key];
                
                if ([self.series.fundamentalList rangeOfString:key].length > 0) {
                    [self.listedMetricValues addObject:[NSDecimalNumber one]];
                } else {
                    [self.listedMetricValues addObject:[NSDecimalNumber zero]];
                }
            }
        }
    }    
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setColor:[UIColor colorWithCGColor:self.series->color]];
    [self setUpColor:[UIColor colorWithCGColor:self.series->upColor]];
    [self.view setBackgroundColor:[UIColor colorWithRed:.85 green:.86 blue:.88 alpha:1.0]];
    
    // Add metrics from other chart in the series
    for (NSString *key in self.sparklineKeys) {
        [self setListedMetricKeyString:[self.listedMetricKeyString stringByAppendingFormat:@"%@,", key]];
    }
    
    if (self.series->hasFundamentals == 1) {
        
        
        [self setListedMetricKeyString:[self.listedMetricKeyString stringByReplacingOccurrencesOfString:@"CostOfSales" withString:@""]];
        [self setListedMetricKeyString:[self.listedMetricKeyString stringByReplacingOccurrencesOfString:@"ResearchAndDevelopmentExpenses" withString:@""]];
        [self setListedMetricKeyString:[self.listedMetricKeyString stringByReplacingOccurrencesOfString:@"SellingGeneralAndAdministrativeExpenses" withString:@""]];
        [self setListedMetricKeyString:[self.listedMetricKeyString stringByReplacingOccurrencesOfString:@"TangibleBookValuePerShare" withString:@""]];
    }    
    
    [self setListedMetricKeyString:[self.listedMetricKeyString stringByAppendingString:self.series.fundamentalList]];
    
    [self updateListedMetrics];

    [self setTapWhenFinished:[[UIButton alloc] init]];
    [self.tapWhenFinished setHidden:YES];
    
    self.title = [NSString stringWithFormat:@"%@ Chart Options", self.series.symbol];
    
	[self setSections:@[@"", @"Color", @"Financials", @"Technicals", @"", @""]];
    
    // Show the saveButton even on the iPad to reassure people that the values will be saved
    self.saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(saveAndClose)];
    [self.saveButton setStyle:UIBarButtonItemStylePlain];
    
    CGRect segmentRect = CGRectMake(9.0f, .0f, [self segmentWidth:[[UIApplication sharedApplication] statusBarOrientation]], 45.0f);
    
    [self setTypeSegmentedControl:[[UISegmentedControl alloc] initWithFrame:segmentRect]];
    
    [self.typeSegmentedControl addTarget:self action:@selector(chartTypeChanged:) forControlEvents:UIControlEventValueChanged];
    
    for (NSInteger i = 0; i < [[ChartOptionsController chartTypes] count]; i++) {
        
        [self.typeSegmentedControl insertSegmentWithImage:[self imageForChartType:i andColor:0 showLabel:YES] atIndex:i animated:NO];
    }
    [self setColorSegmentedControl:[[UISegmentedControl alloc] initWithFrame:segmentRect]];
    
    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground]) {
        // selectedcolor only shows up if darker than tintColor, so don't use black
        [self.typeSegmentedControl setTintColor:[UIColor darkGrayColor]];
        [self.colorSegmentedControl setTintColor:[UIColor darkGrayColor]];
    } else {
        [self.typeSegmentedControl setTintColor:[UIColor lightGrayColor]];
        [self.colorSegmentedControl setTintColor:[UIColor lightGrayColor]];
    }
    
    [self.typeSegmentedControl setSelectedSegmentIndex:self.series->chartType];
    [self.typeSegmentedControl setNeedsDisplay]; // fixes initial issue with incorrect divider image
    
    [self.colorSegmentedControl addTarget:self action:@selector(chartColorChanged:) forControlEvents:UIControlEventValueChanged];
        
    [self renderColorSegments];
    
    [self setDays:[[NSDateComponents alloc] init]];

    self.navigationItem.leftBarButtonItem = self.saveButton;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(confirmDelete)];
    
    [self.navigationItem.rightBarButtonItem setTintColor:[UIColor redColor]];
}

- (void) confirmDelete {
    
    UIAlertController *deleteAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete %@?", self.series.symbol]
                                                                                                            message:nil
                                                                                                    preferredStyle:UIAlertControllerStyleActionSheet];
                                                                                                        
    [deleteAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        [self.delegate performSelector:@selector(deleteSeries:) withObject:self.series];
    }];
    
    [deleteAlert addAction:deleteAction];

    [self presentViewController:deleteAlert animated:YES completion:nil];
}

- (void) saveAndClose {
    
    if (self.tapWhenFinished.hidden == NO) {
         [[self delegate] performSelector:@selector(reloadWithSeries:) withObject:self.series]; 
    }
    [self.delegate performSelector:@selector(popContainer)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self.sections objectAtIndex:section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
        
    switch (section) {
        case 2: 
            if (self.series->hasFundamentals > 0) {
                NSInteger fundamentalRows = [self.listedMetricKeys count];    // should be a count
                //  && UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
                if (10 > fundamentalRows) {
                    fundamentalRows++; // allow adding new fundamentals
                }
                
                if (fundamentalControlRow > 0) {
                    fundamentalRows++;
                }
                return fundamentalRows;
            }
            return 1;   // no fundamentals
        
        case 3: return 4;   // technical options
            
        default: return 1;
    }
}

- (void) technicalToggled:(id)sender {

    NSString *type;
    UISwitch *onOff = (UISwitch *)sender;
    
    switch ([onOff tag]) {
        case 0:
            type = @"sma50";    break;
     
        case 1:
            type = @"sma200";    break;
            
        case 2:
            type = @"bollingerBand220";    break;
            
        case 3:
            type = @"rsi14";    break;
    }

    if ([[self.series technicalList] rangeOfString:type].length > 0) {
        onOff.on = NO;
        [self.series removeFromTechnicals:type];
    } else {
        onOff.on = YES;
        [self.series addToTechnicals:type];
    }
    
    [self.tableView reloadData];    
    [[self delegate] performSelector:@selector(redrawWithSeries:) withObject:self.series];
}

- (void) fundamentalToggled:(id)sender {
    
    UISwitch *onOff = (UISwitch *) sender;
    
    NSInteger tag = [onOff tag];
    if (tag < 0 || tag > [self.listedMetricKeys count]) {
        return; // not valid
    }
    
    NSString *key = [self.listedMetricKeys objectAtIndex:tag];
        
    if ([[self.series fundamentalList] rangeOfString:key].length > 0) {
        [self.listedMetricValues replaceObjectAtIndex:tag withObject:[NSDecimalNumber zero]];
        onOff.on = NO;
        [self.series removeFromFundamentals:key];           // remove has immediate impact

    } else {    // add requires call to server
        onOff.on = YES;
        [self.listedMetricValues replaceObjectAtIndex:tag withObject:[NSDecimalNumber one]];
        [self.series addToFundamentals:key];
    }
    [self.tableView reloadData];
    [[self delegate] performSelector:@selector(reloadWithSeries:) withObject:self.series];    
}

- (void) addedFundamental:(NSString *)key {

    [self.series addToFundamentals:key];
    [self.listedMetricKeys removeAllObjects];
    [self.listedMetricValues removeAllObjects];
    
    [self setListedMetricKeyString:[self.listedMetricKeyString stringByAppendingString:key]];
    [self updateListedMetrics];

    [[self tableView] reloadData];
    [[self delegate] performSelector:@selector(reloadWithSeries:) withObject:self.series];
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)rawIndexPath {
    
    NSInteger row = rawIndexPath.row, section = rawIndexPath.section;
    
    UITableViewCell *cell;
    
    if (section == 2 || section == 3) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
    } else {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease];
    }
    
    [cell setBackgroundColor:[UIColor colorWithRed:.85 green:.86 blue:.88 alpha:1.0]];
    
    cell.textLabel.textColor = [UIColor lightGrayColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    
    if (section == 0) {
        [cell addSubview:self.typeSegmentedControl];
        
    } else if (section == 1) {        
        
        [cell addSubview:self.colorSegmentedControl];

    } else if (section == 2) {
        
        if (self.series->hasFundamentals > 0) {
            
            if (fundamentalControlRow > 0) {
                if (fundamentalControlRow == row) {
                    cell.textLabel.text = self.fundamentalDescription;
                    cell.textLabel.font = [UIFont systemFontOfSize:12];
                    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
                    cell.textLabel.numberOfLines = 4;
                    cell.textLabel.textColor  = [UIColor darkGrayColor];
                    return cell;
                } else if (fundamentalControlRow < row) {
                    row--;
                }
            }
            
            UISwitch *onOff = [UISwitch new];
            [onOff addTarget:self action:@selector(fundamentalToggled:) forControlEvents:UIControlEventTouchUpInside];
            [cell setAccessoryView:onOff];
            [onOff setTag:row]; 
            [onOff release];
            
            if (row < [self.listedMetricKeys count]) {
                NSString *key = [self.listedMetricKeys objectAtIndex:row];
            
                if ([key isEqualToString:@"BookValuePerShare"]) {
                    [[cell imageView] setImage:[self imageForOverlayType:BOOK_OVERLAY andColor:self.series->upColorHalfAlpha]];
                } else {
                    [[cell imageView] setImage:[self imageForOverlayType:SAWTOOTH andColor:self.series->upColorHalfAlpha]];
                }
            
                cell.textLabel.text = [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] titleForKey:key];
                
                if ([[self.listedMetricValues objectAtIndex:row] isEqualToNumber:[NSDecimalNumber one]]) {
                    onOff.on = YES;
                    cell.textLabel.textColor = [UIColor darkGrayColor]; // [UIColor colorWithCGColor:self.series->upColor];
                }
            } else {
                cell.textLabel.text = @"        Add Financial Metric";
                [cell.textLabel setTextColor:[UIColor darkGrayColor]];
                UIButton *b = [UIButton buttonWithType:UIButtonTypeContactAdd];
                [b addTarget:self action:@selector(addMetric) forControlEvents:UIControlEventTouchUpInside];
                cell.accessoryView = b;
            }

        } else {
            cell.textLabel.text = [NSString stringWithFormat:@"None available for %@", self.series.symbol];
        }
        
    } else if (section == 3) {
            
        UISwitch *onOff = [UISwitch new];
        [onOff addTarget:self action:@selector(technicalToggled:) forControlEvents:UIControlEventTouchUpInside];
        [cell setAccessoryView:onOff];
        [onOff setTag:row];
        [onOff release];
        
        if (row == 0) {            
            cell.textLabel.text = @"50 Simple Moving Avg";
            
            [[cell imageView] setImage:[self imageForOverlayType:MOVING_AVERAGE andColor:self.series->colorInverseHalfAlpha]];
            
            if ([[self.series technicalList] rangeOfString:@"sma50"].length > 0) {
                onOff.on = YES;
                cell.textLabel.textColor = [UIColor darkGrayColor]; // [UIColor colorWithCGColor:self.series->upColor];
            }
        } else if (row == 1) {
            
            [[cell imageView] setImage:[self imageForOverlayType:MOVING_AVERAGE andColor:self.series->upColorHalfAlpha]];
            
            cell.textLabel.text = @"200 Simple Moving Avg";
            
            if ([[self.series technicalList] rangeOfString:@"sma200"].length > 0) {
                onOff.on = YES;
                cell.textLabel.textColor = [UIColor darkGrayColor]; // [UIColor colorWithCGColor:self.series->upColor];
            }
        } else if (row == 2) {
            [[cell imageView] setImage:[self imageForOverlayType:MOVING_AVERAGE andColor:self.series->upColorHalfAlpha]];
            
            cell.textLabel.text = @"Bollinger Bands 2, 20";
            
            if ([[self.series technicalList] rangeOfString:@"bollingerBand220"].length > 0) {
                onOff.on = YES;
                cell.textLabel.textColor = [UIColor darkGrayColor]; // [UIColor colorWithCGColor:self.series->upColor];
            }
        } else if (row == 3) {
            [[cell imageView] setImage:[self imageForOverlayType:MOVING_AVERAGE andColor:self.series->upColorHalfAlpha]];
            
            cell.textLabel.text = @"RSI 14 periods";
            
            if ([[self.series technicalList] rangeOfString:@"rsi14"].length > 0) {
                onOff.on = YES;
                cell.textLabel.textColor = [UIColor darkGrayColor]; //  [UIColor colorWithCGColor:self.series->upColor];
            }
        }
        
    } else if (section == 4) {
        
        if (self.defaultsButton == nil) {
            
            [self setDefaultsButton:[UIButton buttonWithType:UIButtonTypeSystem]];            
            [self.defaultsButton.titleLabel setFont:[UIFont systemFontOfSize:14]];
            [self.defaultsButton setTitleColor:[UIColor colorWithWhite:0.9 alpha:0.9] forState:UIControlStateNormal];
                
            [self.defaultsButton setFrame:CGRectMake(0, 0, [self segmentWidth:[[UIApplication sharedApplication] statusBarOrientation]] - 2., 44.)];
            [self.defaultsButton setBackgroundColor:[UIColor clearColor]];
            [self.defaultsButton setOpaque:NO];
            [self.defaultsButton addTarget:self action:@selector(updateDefaults) forControlEvents:UIControlEventTouchDown];
        }
        
        [self.defaultsButton setTitle:@"Use These Settings For New Charts" forState:UIControlStateNormal];  // ensures it is reset after a change
        [cell.contentView addSubview:self.defaultsButton];
            
 
    } else if (section == 5) {
        
        cell.textLabel.text = @"Newest Date Shown";
        [cell.textLabel setTextColor:[UIColor darkGrayColor]];
        [cell.detailTextLabel setTextColor:[UIColor darkGrayColor]];

        if (self.series->daysAgo == 0) {
            cell.detailTextLabel.text = @"Today";
        } else {
            [[self days] setDay:-self.series->daysAgo];
            NSDate *dateAgo = [self.gregorian dateByAddingComponents:self.days toDate:[NSDate date] options:0];
            cell.detailTextLabel.text = [self.dateFormatter stringFromDate:dateAgo];
        }
    }
	return cell;
}

// Defaults are updated rarely so strip out industrial fundamentals and save as bankFundamentalDefaults
- (void) updateDefaults {

    [[NSUserDefaults standardUserDefaults] setInteger:self.series->chartType forKey:@"chartTypeDefault"];
    [[NSUserDefaults standardUserDefaults] setValue:self.series.technicalList forKey:@"technicalDefaults"];
    [[NSUserDefaults standardUserDefaults] setValue:self.series.fundamentalList forKey:@"fundamentalDefaults"];
    
    NSString *bankFundamentalDefaults = [self.series.fundamentalList stringByReplacingOccurrencesOfString:@"CostOfSales," withString:@""];
    bankFundamentalDefaults = [bankFundamentalDefaults stringByReplacingOccurrencesOfString:@"ResearchAndDevelopmentExpenses," withString:@""];
    bankFundamentalDefaults = [bankFundamentalDefaults stringByReplacingOccurrencesOfString:@"SellingGeneralAndAdministrativeExpenses," withString:@""];
    bankFundamentalDefaults = [bankFundamentalDefaults stringByReplacingOccurrencesOfString:@"TangibleBookValuePerShare," withString:@""];

    [[NSUserDefaults standardUserDefaults] setValue:bankFundamentalDefaults forKey:@"bankFundamentalDefaults"];
    
    [self.defaultsButton setTitle:@"Default Chart Settings Saved" forState:UIControlStateNormal];
}

- (void) dateChanged:(id)sender {
    
	NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
    
    [self setDays:[self.gregorian components:NSDayCalendarUnit fromDate:self.datePicker.date toDate:[NSDate date] options:0]];
    
    NSInteger daysAgo = [self.days day];
    
    if (daysAgo < 0) {
        daysAgo = 0;    // prevent future dates
    }
    
    self.series->daysAgo = daysAgo;
    
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
	cell.detailTextLabel.text = [self.dateFormatter stringFromDate:self.datePicker.date];
}

- (void) chartTypeChanged:(id) sender {
    
    self.series->chartType = [self.typeSegmentedControl selectedSegmentIndex];
    [self renderColorSegments];
    [self.tableView reloadData]; 
    [[self delegate] performSelector:@selector(redrawWithSeries:) withObject:self.series];
}

- (void) chartColorChanged:(id) sender {
    NSArray *colorList = [ChartOptionsController chartColors];
    
    NSInteger selectedIndex = [self.colorSegmentedControl selectedSegmentIndex];
    
    if (selectedIndex == 0) {
        [self setUpColor:[colorList objectAtIndex:0]];
        [self setColor:[UIColor colorWithRed:1. green:.0 blue:.0 alpha:1.0]];    // red

    } else if (selectedIndex < colorList.count) {
        [self setUpColor:[colorList objectAtIndex:selectedIndex]];
        [self setColor:[colorList objectAtIndex:selectedIndex]];
    }
    
    [self.series setColor:[self.color CGColor]];
    [self.series setUpColor:[self.upColor CGColor]];
    [self.tableView reloadData];    // changes color for fundamental overlay
    
    [[self delegate] performSelector:@selector(redrawWithSeries:) withObject:self.series]; 
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2 && indexPath.row == fundamentalControlRow) {
        return 70.;
    }
    return 44;
}

- (void) hidePicker {
    [self.tableView reloadData];
    [self.datePicker removeFromSuperview];
    [self.tapWhenFinished removeFromSuperview];
    self.tapWhenFinished.hidden = YES;
    self.tableView.scrollEnabled = YES;
    [[self delegate] performSelector:@selector(reloadWithSeries:) withObject:self.series];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)rawIndexPath {
    
    [self.tableView deselectRowAtIndexPath:rawIndexPath animated:YES];  // deselect before deleting to avoid deselecting deleted index
    
    NSInteger section = rawIndexPath.section; 

    if (section == 4) {
         
    } if (section == 5) {
        if (self.datePicker == nil) {
            [self setDatePicker:[[UIDatePicker alloc] init]];
            [self.datePicker setDatePickerMode:UIDatePickerModeDate];   
            [self.datePicker addTarget:self action:@selector(dateChanged:) forControlEvents:UIControlEventValueChanged];
        }
        
        UITableViewCell *targetCell = [table cellForRowAtIndexPath:rawIndexPath];
        
        if ([targetCell.detailTextLabel.text isEqualToString:@"Today"]) {
            self.datePicker.date = [NSDate date];
            self.series->daysAgo = 0;
        } else {
            self.datePicker.date = [self.dateFormatter dateFromString:targetCell.detailTextLabel.text];
        }
        
        if (self.datePicker.superview == nil)	{
            self.tableView.scrollEnabled = NO; // or the picker will scroll
            [self.tapWhenFinished setFrame:CGRectMake(CGRectGetMinX(self.view.bounds), CGRectGetMinY(self.view.bounds), self.view.bounds.size.width, self.view.frame.size.height - 180)];   // since we disable scrolling, it only needs to be frame.size.height - 180 tall
            [self.tapWhenFinished setHidden:NO];
            [self.tapWhenFinished setTitle:@"Tap When Finished" forState:UIControlStateNormal];
            [self.tapWhenFinished setTitleShadowColor:[UIColor blackColor] forState:UIControlStateNormal];
            [self.tapWhenFinished setOpaque:NO];
            [self.tapWhenFinished setBackgroundColor:[UIColor colorWithWhite:0. alpha:0.6]];
            [self.tapWhenFinished addTarget:self action:@selector(hidePicker) forControlEvents:UIControlEventTouchUpInside];
            [self.view addSubview:self.tapWhenFinished];
            [self.view bringSubviewToFront:self.tapWhenFinished];
            [self.view addSubview: self.datePicker];
        }
        
        // use the bounds because the scrollview bounds is larger than the screen height
        [self.datePicker setFrame:CGRectMake(CGRectGetMinX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 180, self.view.bounds.size.width, 180)];
        
    } else if (section == 2) {
        NSInteger row = rawIndexPath.row;
        NSInteger rowToFollow = row;
        
        NSInteger adjRow = row;
        if (fundamentalControlRow > 0 && adjRow > 0) {     // avoid -1 index value
            adjRow--;
        }
        
        NSIndexPath *indexPathToDelete = nil, *indexPathToInsert = nil;
        
        if (row == fundamentalControlRow) {         // clicking control row has no effect
            rowToFollow = -1;

        } else if (fundamentalControlRow > 0) {
            if (row + 1 == fundamentalControlRow) {
                rowToFollow = -1;               // clicking on parent hides control row
            } else if (row > fundamentalControlRow) {     
                rowToFollow--;      // account for deletion of existing fundamentalControlRow
            }
            indexPathToDelete = [NSIndexPath indexPathForRow:fundamentalControlRow inSection:section];
            fundamentalControlRow = -1;
        }
        BOOL clickedAddMetric = NO;
        if (rowToFollow + 1 == [self tableView:table numberOfRowsInSection:section]) {
            clickedAddMetric = YES;
        }
        
        if (rowToFollow > -1 && !clickedAddMetric) {  // no control row on add row      
            
            [self setFundamentalDescription:[(CIAppDelegate *)[[UIApplication sharedApplication] delegate] descriptionForKey:[self.listedMetricKeys objectAtIndex:adjRow]]];
            
            fundamentalControlRow = rowToFollow + 1;

            indexPathToInsert = [NSIndexPath indexPathForRow:fundamentalControlRow inSection:section];

            if ([indexPathToInsert isEqual:indexPathToDelete]) {
                fundamentalControlRow = -1;
                indexPathToInsert = nil;
            }            
        }        
 
        [self.tableView  beginUpdates];
        if (indexPathToDelete != nil) {
            [self.tableView deleteRowsAtIndexPaths:@[indexPathToDelete] withRowAnimation:UITableViewRowAnimationTop];
        }
        if (indexPathToInsert) {
            [self.tableView insertRowsAtIndexPaths:@[indexPathToInsert] withRowAnimation:UITableViewRowAnimationTop];
        }
        [self.tableView endUpdates];        
        
        if (clickedAddMetric) {
            [self addMetric];
        }
    }
}

- (void) addMetric {
    AddFundamentalController *flc = [[AddFundamentalController alloc] initWithStyle:UITableViewStylePlain];
    [flc setDelegate:self];
    NSMutableArray *otherMetrics = [NSMutableArray new];    
    
    for (NSArray *category in [self metrics]) {     // add to a parallel array to avoid affecting the objects in [self metrics]
        NSMutableArray *availableMetrics = [NSMutableArray new];
        for (NSArray *type in category) {
            NSString *key = [type objectAtIndex:0];
            if ([self.listedMetricKeyString rangeOfString:key].length == 0) {      // skip already listed ones
                
                if (self.series->hasFundamentals == 2 || ([key isEqualToString:@"CostOfSales"] == NO 
                        && [key isEqualToString:@"ResearchAndDevelopmentExpenses"] == NO 
                        && [key isEqualToString:@"SellingGeneralAndAdministrativeExpenses"] == NO
                        && [key isEqualToString:@"TangibleBookValuePerShare"] == NO)) {
                    [availableMetrics addObject:type];
                }
            }
        }
        [otherMetrics addObject:availableMetrics];
    }
    [flc setMetrics:otherMetrics];
    [[self navigationController] pushViewController:flc animated:YES];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}


- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toOrientation duration:(NSTimeInterval)duration {
    
    CGFloat newWidth = [self segmentWidth:toOrientation];
    
    CGRect segmentRect = CGRectMake(9., 0.,  newWidth, 45.);
    
    [self.typeSegmentedControl setFrame:segmentRect];
    [self.colorSegmentedControl setFrame:segmentRect];
    
    [self.defaultsButton setFrame:CGRectMake(0, 0, newWidth - 2, 44.)];

    [self.tableView reloadData];    // force segment redraw
}

@end
