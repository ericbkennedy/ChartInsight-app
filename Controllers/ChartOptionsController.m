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
@property (strong, nonatomic) UIBarButtonItem *doneButton;
@property (strong, nonatomic) NSArray *sections;
@property (nonatomic, copy) NSString *fundamentalDescription;
@property (strong, nonatomic) UISegmentedControl *typeSegmentedControl;
@property (strong, nonatomic) UISegmentedControl *colorSegmentedControl;
@property (strong, nonatomic) UIButton *tapWhenFinished;
@property (strong, nonatomic) NSString *listedMetricKeyString;
@property (strong, nonatomic) NSMutableArray *listedMetricKeys;
@property (strong, nonatomic) NSMutableArray *listedMetricValues;   // parallel array to preserve sort

@end
@implementation ChartOptionsController

- (instancetype) initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self != nil) {
        fundamentalControlRow = -1;
        [self setListedMetricKeys:[NSMutableArray new]];
        [self setListedMetricValues:[NSMutableArray new]];
        [self setListedMetricKeyString:@"EarningsPerShareBasic,CIRevenuePerShare,CINetCashFromOpsPerShare"];
        
        [self setDateFormatter:[[NSDateFormatter alloc] init]];
        [self.dateFormatter setDateStyle:NSDateFormatterShortStyle];
        [self.dateFormatter setTimeStyle:NSDateFormatterNoStyle];
    }
    return self;
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
        [[UIColor whiteColor] setFill];
        NSString *label = [[ChartOptionsController chartTypes] objectAtIndex:type];
        NSDictionary *textAttributes = @{NSFontAttributeName: [UIFont systemFontOfSize:9.0]};
        [label drawAtPoint:CGPointMake(6. - label.length, 22.) withAttributes:textAttributes];
    }
     
    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return [screenshot imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
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

- (CGFloat) segmentWidthForOrientation:(UIInterfaceOrientation)toOrientation {
    CGFloat width = 320;
    CGFloat horizontalPadding = 18;
    
    if (UIInterfaceOrientationIsLandscape(toOrientation)) {
        width = 375;
    } else if (self.view.frame.size.width > width) {
        width = self.view.frame.size.width;
    }
    return width - horizontalPadding;
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
    
    if (@available(iOS 13, *)) {
        self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
        self.tableView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    } else {
        self.view.backgroundColor = [UIColor colorWithRed:.85 green:.86 blue:.88 alpha:1.0];
        self.tableView.backgroundColor = self.view.backgroundColor;
    }
    
    // Add metrics from other chart in the series
    for (NSString *key in self.sparklineKeys) {
        [self setListedMetricKeyString:[self.listedMetricKeyString stringByAppendingFormat:@"%@,", key]];
    }
    
    [self setListedMetricKeyString:[self.listedMetricKeyString stringByAppendingString:self.series.fundamentalList]];
    
    [self updateListedMetrics];

    [self setTapWhenFinished:[[UIButton alloc] init]];
    [self.tapWhenFinished setHidden:YES];
    
    self.title = [NSString stringWithFormat:@"%@ Chart Options", self.series.symbol];
    
	[self setSections:@[@"", @"Color", @"Financials", @"Technicals", @""]];
    
    // Show the doneButton even on the iPad to reassure people that the values will be saved
    self.doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(saveAndClose)];
    [self.doneButton setStyle:UIBarButtonItemStylePlain];
    
    NSMutableArray *segments = [NSMutableArray array];
    for (NSInteger i = 0; i < [[ChartOptionsController chartTypes] count]; i++) {
        segments[i] = [self imageForChartType:i andColor:0 showLabel:YES];
    }
    self.typeSegmentedControl = [[UISegmentedControl alloc] initWithItems:segments];
    [self.typeSegmentedControl addTarget:self action:@selector(chartTypeChanged:) forControlEvents:UIControlEventValueChanged];

    // frame width is often zero at this point so create an empty segmentedControl
    // and allow renderColorSegments to add the segments later
    self.colorSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[]];
        
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
    
    self.navigationItem.leftBarButtonItem = self.doneButton;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(deleteStock)];
    
    [self.navigationItem.rightBarButtonItem setTintColor:[UIColor redColor]];
}

- (void) deleteStock {

    [self.delegate performSelector:@selector(deleteSeries:) withObject:self.series];
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
        
        case 3: return 3;   // technical options (RSI removed 2023
            
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
    
    cell.textLabel.textColor = [UIColor lightGrayColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    
    CGFloat segmentWidth = [self segmentWidthForOrientation:[[UIApplication sharedApplication] statusBarOrientation]];
    
    if (section == 0) {
        self.typeSegmentedControl.frame = CGRectMake(9.0, .0, segmentWidth, 45.);
        [cell addSubview:self.typeSegmentedControl];
                
    } else if (section == 1) {
        self.colorSegmentedControl.frame = CGRectMake(9.0, .0, segmentWidth, 45.);
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
        }
        
    } else if (section == 4) {
        
        if (self.defaultsButton == nil) {
            
            [self setDefaultsButton:[UIButton buttonWithType:UIButtonTypeSystem]];            
            [self.defaultsButton.titleLabel setFont:[UIFont systemFontOfSize:14]];
            [self.defaultsButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
            [self.defaultsButton setFrame:CGRectMake(0, 0, segmentWidth - 2., 44.)];
            [self.defaultsButton setBackgroundColor:[UIColor clearColor]];
            [self.defaultsButton setOpaque:NO];
            [self.defaultsButton addTarget:self action:@selector(updateDefaults) forControlEvents:UIControlEventTouchDown];
        }
        
        [self.defaultsButton setTitle:@"Use These Settings For New Charts" forState:UIControlStateNormal];  // ensures it is reset after a change
        [cell.contentView addSubview:self.defaultsButton];
    }
	return cell;
}

- (void) updateDefaults {

    [[NSUserDefaults standardUserDefaults] setInteger:self.series->chartType forKey:@"chartTypeDefault"];
    [[NSUserDefaults standardUserDefaults] setValue:self.series.technicalList forKey:@"technicalDefaults"];
    [[NSUserDefaults standardUserDefaults] setValue:self.series.fundamentalList forKey:@"fundamentalDefaults"];
    
    [self.defaultsButton setTitleColor:[UIColor darkTextColor] forState:UIControlStateNormal];
    [self.defaultsButton setTitle:@"Default Chart Settings Saved" forState:UIControlStateNormal];
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
    [self.tapWhenFinished removeFromSuperview];
    self.tapWhenFinished.hidden = YES;
    self.tableView.scrollEnabled = YES;
    [[self delegate] performSelector:@selector(reloadWithSeries:) withObject:self.series];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)rawIndexPath {
    
    [self.tableView deselectRowAtIndexPath:rawIndexPath animated:YES];  // deselect before deleting to avoid deselecting deleted index
    
    NSInteger section = rawIndexPath.section; 

    if (section == 2) {
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

@end
