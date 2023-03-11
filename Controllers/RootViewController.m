#import "CIAppDelegate.h"
#import "RootViewController.h"
#import "ScrollChartController.h"
#import "ChartOptionsController.h"
#import "FindSeriesController.h"
#import "MoveDB.h"
#import "SettingsViewController.h"

@interface RootViewController ()

@property (assign, nonatomic) CGFloat width;
@property (assign, nonatomic) CGFloat height;
@property (assign, nonatomic) CGFloat statusBarHeight; // 0 except on iPad
@property (assign, nonatomic) CGFloat toolbarHeight;
@property (assign, nonatomic) CGFloat leftGap;
@property (assign, nonatomic) CGFloat lastShift;
@property (assign, nonatomic) CGFloat netDelta;
@property (assign, nonatomic) CGFloat pinchCount;
@property (assign, nonatomic) CGFloat pinchMidpointSum;

@property (assign, nonatomic) BOOL dragWindow;
@property (assign, nonatomic) BOOL newComparison;

@property (nonatomic, strong) UINavigationController    *popOverNav;    // required for navgiation controller within popover
@property (nonatomic, strong) UITapGestureRecognizer   *doubleTapRecognizer;
@property (nonatomic, strong) UILongPressGestureRecognizer *oneLongPressRecognizer;
@property (nonatomic, strong) UILongPressGestureRecognizer *twoLongPressRecognizer;
@property (nonatomic, strong) UIPanGestureRecognizer   *panRecognizer;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchRecognizer;
@property (nonatomic, strong) UIBarButtonItem *minimizeButton;
@property (nonatomic, strong) UIToolbar *customNavigationToolbar;     //  better formatting than using self.navigationItem
@property (strong, nonatomic) UIToolbar *settingsToolbar;

@property (strong, nonatomic) NSDateComponents *days;

@property (strong, nonatomic) ScrollChartController *scc;

@property (strong, nonatomic) NSMutableArray *list;     // stocks from comparison table

@property (strong, nonatomic) NSMutableString *dbPath;

@property (strong, nonatomic) NSDictionary *infoForPressedBar;

@property (strong, nonatomic) UITableView *tableView;

@property (strong, nonatomic) UIBarButtonItem *barTitle;

- (void) singleTap:(UITapGestureRecognizer *)recognizer;

- (void) doubleTap:(UITapGestureRecognizer *)recognizer;

- (void) trendline:(UILongPressGestureRecognizer *) recognizer;

- (void) magnify:(UILongPressGestureRecognizer *) recognizer;

- (void) handlePan:(UIPanGestureRecognizer *)recognizer;

- (void) handlePinch:(UIPinchGestureRecognizer *)recognizer;

- (NSString *) defaultDbPath;

- (NSString *) bestDbPath;
@end

@implementation RootViewController

- (void)dealloc {
    [_list removeAllObjects];
    [_list release];
    [_gregorian release];
    [super dealloc];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void) popoverPush:(UIViewController *)vc fromButton:(UIBarButtonItem *)button {
    
    self.popOverNav = [[UINavigationController alloc] initWithRootViewController:vc];
    self.popOverNav.modalPresentationStyle = UIModalPresentationPopover;
    self.popOverNav.popoverPresentationController.sourceView = self.view;
    self.popOverNav.popoverPresentationController.barButtonItem = button;
    [self presentViewController:self.popOverNav animated:YES completion:nil];
}

- (void) editSettings:(id)sender {
    SettingsViewController *settingsViewController = [[SettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    settingsViewController.delegate = self;
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:settingsViewController];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void) addSeries:(id)sender {        
    
    UIBarButtonItem *button = (UIBarButtonItem *)sender;
        
    if (button.tag == 0) {
        if (self.scc.layer.position.x < 30) {
            return;
        }
        self.newComparison = YES;
    } else {
        self.newComparison = NO;
    }
    
    FindSeriesController *fcc = [[FindSeriesController alloc] initWithStyle:UITableViewStylePlain];
    [fcc setDelegate:self];
    
    [self popoverPush:fcc fromButton:sender];
}

- (void) editSeries:(id)sender {
        
    UIBarButtonItem *button = (UIBarButtonItem *)sender;
    
    Series *series = (Series *)button.tag;
    
    ChartOptionsController *ctc = [[ChartOptionsController alloc] initWithStyle:UITableViewStyleGrouped];
    [ctc setSparklineKeys:[self.scc.comparison sparklineKeys]];
    [ctc setSeries:series];
    [ctc setDelegate:self];
    [ctc setGregorian:self.gregorian];
  
    [self popoverPush:ctc fromButton:sender];
}

- (void) reloadWithSeries:(Series *)series {
    
    if (self.scc != nil) {
        [self.scc.comparison saveToDb];
        [self.scc clearChart];
        [self.progressIndicator startAnimating];
        [self resetToolbarWithSearch:YES];
        [self.scc loadChart];
    } 
}

/* called by ChartOptionsController when chart color or type changes */ 
- (void) redrawWithSeries:(Series *)series {
    if (self.scc != nil) {
        [self.scc.comparison saveToDb];
        for (UIBarButtonItem *button in self.customNavigationToolbar.items) {
            if (button.tag == (NSInteger)series) {
                [button setTintColor:[UIColor colorWithCGColor:series->upColorDarkHalfAlpha]];
            }
        }
        [self.scc redrawCharts];
    } 
}

- (void) resetToolbarWithSearch:(BOOL)showSearch {

    if (showSearch) {
        self.minimizeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self action:@selector(addSeries:)];
    } else {
        self.minimizeButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"hideWebview"] style:UIBarButtonItemStylePlain target:self action:@selector(minimizeChart)];
    }
    
    if ([self.scc comparison] != nil) {

        NSMutableArray *buttons = [NSMutableArray new];
        
        [buttons addObject:self.minimizeButton];
        
        [buttons addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease]];
        
        UIBarButtonItem *button;
        Series *s;
        NSArray *stockList = self.scc.comparison.seriesList;
        for (NSInteger i = 0; i < [stockList count]; i++) {
            
            s = [stockList objectAtIndex:i];

            UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:s.symbol style:UIBarButtonItemStylePlain target:self action:@selector(editSeries:)];    
            [button setTag:(NSInteger)s];     
                        
            [button setTintColor:[UIColor colorWithCGColor:s->upColorDarkHalfAlpha]];
            
            [buttons addObject:button];
            [button release];
        }
        
        if ([stockList count] < 3 || UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            
            button = [[UIBarButtonItem alloc] initWithTitle:@"compare" style:UIBarButtonItemStylePlain target:self action:@selector(addSeries:)];
            
            [button setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIFont systemFontOfSize:10], NSFontAttributeName,nil] forState:UIControlStateNormal];

            [button setTag:(NSInteger)self.scc.comparison];
            [buttons addObject:button];
        }
        
        [buttons addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease]];

        [self.customNavigationToolbar setItems:buttons];
    }
}

- (void) nightDayToggle {
    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground]) {
        [self.customNavigationToolbar setBarStyle:UIBarStyleDefault];
        [self.settingsToolbar setBarStyle:UIBarStyleDefault];
        [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightModeOn:NO];

    } else {
        [self.customNavigationToolbar setBarStyle:UIBarStyleBlack];
        [self.settingsToolbar setBarStyle:UIBarStyleBlack];
        [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightModeOn:YES];
    }
    self.view.backgroundColor = [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] tableViewBackground];
    
//    [self.view setBackgroundColor:[UIColor colorWithRed:0.870588235 green:0.901960784 blue:0.968627451 alpha:1.0]];
    // [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] chartBackground]];
    [self.scc redrawCharts];
    [self.tableView reloadData];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground] == NO) {
        return UIStatusBarStyleLightContent;
    } else {
        return UIStatusBarStyleBlackOpaque; // old iPad doesn't support iOS 13 UIStatusBarStyleDarkContent
    }
}

- (void)viewDidLoad {
    MoveDB *move = [[[MoveDB alloc] init] autorelease];
    [move moveDBforDelegate:self];                      // copy db to documents or check existing db
    
    [super viewDidLoad];
    
    [self resizeFrameToSize:[UIScreen mainScreen].bounds.size];

    self.leftGap = (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) ? 60 : 100;
    
    [self.view setBackgroundColor:[(CIAppDelegate *)[[UIApplication sharedApplication] delegate] chartBackground]];	
        
    [self setGregorian:[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]];
    [self setDays:[[NSDateComponents alloc] init]];
    
    self.customNavigationToolbar = [UIToolbar new];
	self.customNavigationToolbar.translucent = NO;
    [self.customNavigationToolbar setFrame:CGRectMake(0, self.statusBarHeight, self.width, self.toolbarHeight)];
    [self.view addSubview:self.customNavigationToolbar];
    
    [self setMinimizeButton:[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"maximize"] style:UIBarButtonItemStylePlain target:self action:@selector(minimizeChart)]];
    
    self.settingsToolbar = [UIToolbar new];
    self.settingsToolbar.translucent = NO;
    self.settingsToolbar.frame = CGRectMake(0, self.height + 20, 205, self.toolbarHeight);
    
    UIBarButtonItem *settingsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"settingsUnselected"] style:UIBarButtonItemStylePlain target:self action:@selector(editSettings:)];
    
    UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:NULL action:NULL];
    
    [self.settingsToolbar setItems:@[settingsItem, flexibleSpace]];
    [self.view addSubview:self.settingsToolbar];
   
    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground] == NO) {
        // Note if user selected dark mode in settings that will override the bar style here
        [self.customNavigationToolbar setBarStyle:UIBarStyleDefault];
        [self.settingsToolbar setBarStyle:UIBarStyleDefault];
    } else {
    	[self.customNavigationToolbar setBarStyle:UIBarStyleBlack];
        [self.settingsToolbar setBarStyle:UIBarStyleBlack];
    }
    
    [self setList:[Comparison listAll:[self bestDbPath]]];
    
    self.tableView = [[[UITableView alloc] initWithFrame:CGRectMake(0, self.toolbarHeight + self.statusBarHeight,
                                                                    205, self.height - 2 * self.toolbarHeight)
                                                   style:UITableViewStylePlain] autorelease];
    
    [self.tableView setBackgroundColor:[UIColor clearColor]];
    [self.tableView setClipsToBounds:NO];      // YES would create rounded corners, which doesn't matter when the background is all the same
	[self.tableView setDelegate:self];
	[self.tableView setDataSource:self];
	[self.tableView setScrollEnabled:YES];
	[self.view addSubview:self.tableView];
    [self.view sendSubviewToBack:self.tableView];
    
    [self setScc:[[ScrollChartController alloc] init]];
    [self.scc.layer setAnchorPoint:CGPointMake(0., 0.)];                      // allows bounds = frame
    [self.scc.layer setPosition:CGPointMake(self.leftGap, CGRectGetMaxY(self.customNavigationToolbar.frame))];  // ipad menu bar
    [self.scc setBounds:CGRectMake(0, 0, self.width, self.height)];
    [self.scc resetDimensions];
    [self.scc createLayerContext];

    [self.scc setGregorian:self.gregorian];
    [self.view addSubview:self.scc];
    [self.scc.layer setZPosition:1];
    [self.scc setNeedsDisplay];
    [self.view.layer setNeedsDisplay];
    
    [self setMagnifier:[[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 100., 100.)]];
    [self.magnifier.layer setContentsScale:UIScreen.mainScreen.scale];
    [self.magnifier.layer setZPosition:3];
    [self.magnifier setHidden:YES];
    [self.view addSubview:self.magnifier];
        
    [self setProgressIndicator:[[ProgressIndicator alloc] initWithFrame:CGRectMake(0, 32., self.width, 4)]];
    [self.view addSubview:self.progressIndicator];
    [self.progressIndicator.layer setZPosition:4];
    [self.progressIndicator setHidden:YES]; // until startAnimating is called
    [self.scc setProgressIndicator:self.progressIndicator];
    
    // init gesture recognizers early so adding a new chart (vs clicking tableview) has gesture recognizers 
    self.doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    [self.doubleTapRecognizer setNumberOfTapsRequired:2];
    [self.scc addGestureRecognizer:self.doubleTapRecognizer];

    self.twoLongPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(trendline:)];
    [self.twoLongPressRecognizer setMinimumPressDuration:0.4];
    [self.twoLongPressRecognizer setNumberOfTouchesRequired:2];
    [self.scc addGestureRecognizer:self.twoLongPressRecognizer];
    
    self.oneLongPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(magnify:)];
    [self.oneLongPressRecognizer setMinimumPressDuration:0.5];
    [self.oneLongPressRecognizer setNumberOfTouchesRequired:1];
    [self.scc addGestureRecognizer:self.oneLongPressRecognizer];
    // don't require twoLongPressRecognizer to fail because they respond to different numbers of touches
    
    self.pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self.scc addGestureRecognizer:self.pinchRecognizer];
    
    self.panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.scc addGestureRecognizer:self.panRecognizer];
 
    if (self.list.count > 0) {
        [self loadComparisonAtRow:0];
    }
    self.dragWindow = NO;
}

- (void) resizeSubviewsForSize:(CGSize)newSize {
    [self.customNavigationToolbar setFrame:CGRectMake(0, self.statusBarHeight, newSize.width, self.toolbarHeight)];
    CGFloat combinedToolbarHeight = self.statusBarHeight + self.toolbarHeight;
    
    self.tableView.frame = CGRectMake(0, combinedToolbarHeight, 205, newSize.height - combinedToolbarHeight);
    self.settingsToolbar.frame = CGRectMake(0, newSize.height - self.toolbarHeight, 205, self.toolbarHeight);    
    self.progressIndicator.frame = CGRectMake(0, 32., self.width, 4);
    self.scc.layer.position = CGPointMake(self.scc.layer.position.x, combinedToolbarHeight);
    
    [self.tableView reloadData];
    
    CGFloat delta = self.scc.bounds.size.width - newSize.width;
    NSInteger shiftBars = floor(self.scc.layer.contentsScale* delta/(self.scc->xFactor * self.scc->barUnit));
    
    [self.scc updateMaxPercentChangeWithBarsShifted: -shiftBars];  // shiftBars are positive when delta is negative

    self.scc.bounds = CGRectMake(0, 0, newSize.width, newSize.height - combinedToolbarHeight);
    [self.scc resize];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if ([self resizeFrameToSize:[UIScreen mainScreen].bounds.size]) {
        [self resizeSubviewsForSize:CGSizeMake(self.width, self.height)];
    }
}

// called by FindSeriesController when a new stock is added
- (void) insertSeries:(NSMutableArray *)newSeriesList {

    if (self.newComparison || self.scc.comparison == nil) {
        [self.scc setComparison:[[Comparison alloc] init]];
        [self.scc.comparison setId: 0];  // new unsaved comparison
        [self.scc.comparison setSeriesList:[NSMutableArray arrayWithCapacity:3]];
    }
    
    NSMutableArray *otherColors = [NSMutableArray arrayWithArray:[ChartOptionsController chartColors]];
    
    for (NSInteger i = 0; i < [[self.scc.comparison seriesList] count]; i++) {
        for (NSInteger c = 0; c < [otherColors count]; c++) {
            
            Series *s = [self.scc.comparison.seriesList objectAtIndex:i];
            if ([s matchesColor:[otherColors objectAtIndex:c]]) {
                [otherColors removeObjectAtIndex:c];
                // can't just break because the color could be used by the 2nd stock of 3
            }
        }
    }
    
    UIColor *green = [[ChartOptionsController chartColors] objectAtIndex:0];
    
    for (NSInteger i = 0; i < newSeriesList.count; i++) {
        Series *s = [newSeriesList objectAtIndex:i];
        [s convertDateStringToDate];
        
        // don't alter chart type because it is set as a default
        [s setUpColor:[(UIColor *)[otherColors objectAtIndex:0] CGColor]];

        if ([s matchesColor:green]) {
        //    // DLog(@"matches green");
            [s setColor: [UIColor redColor].CGColor ];
        } else {
            [s setColor:[(UIColor *)[otherColors objectAtIndex:0] CGColor]];
        }
        
        if (otherColors.count > 1) {    
            [otherColors removeObjectAtIndex:0];
        }
        [[self.scc.comparison seriesList] addObject:s];        
    }
    [self.scc.comparison saveToDb];
    [self reloadList:self.scc.comparison];
    [self popContainer];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.list count];
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        return 40;
    }
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
	UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"recyclableCell"];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"recyclableCell"] autorelease];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
    
    Comparison *comparison = [self.list objectAtIndex:indexPath.row];
 
    cell.textLabel.text = [comparison title];
    cell.textLabel.font = [UIFont systemFontOfSize:13];
    
    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground] != NO) {
        cell.textLabel.textColor = [UIColor lightGrayColor];
    } else {
        cell.textLabel.textColor = [UIColor colorWithRed:.490 green:.479 blue:0.432 alpha:1.0];
    }
    return cell;
}

- (void) deleteSeries:(NSInteger)sender {
    
    if (self.scc != nil && sender > 0) {
        Series *s = (Series *)sender;

        UIBarButtonItem *buttonToRemove = nil;
        
        for (UIBarButtonItem *button in self.customNavigationToolbar.items) {
            if (button.tag == sender) {
                buttonToRemove = button;
            }
        }
        
        [self.scc.comparison deleteSeries:s];
        
        if (self.scc.comparison.seriesList.count < 1) {
            [self.scc.comparison deleteFromDb];
         //   DLog(@"deleted all from DB");
            [self reloadList:nil];
        } else {
            [self.scc redrawCharts];
            [self reloadList:self.scc.comparison];
        }
        [self resetToolbarWithSearch:YES];
    }
    [self popContainer];
}


- (BOOL) resizeFrameToSize:(CGSize)newSize {
	CGFloat newWidth, newHeight;
    self.toolbarHeight = 44;
    
    newWidth = newSize.width;
    newHeight = newSize.height;
    
    self.statusBarHeight = 20.; // NOTE this could be larger if a navigation app is running
    
	if (self.width != newWidth) {
		self.width = newWidth;
		self.height = newHeight - self.toolbarHeight - self.statusBarHeight;
 		return TRUE;
	}
	return FALSE;
}

- (void) viewWillAppear:(BOOL)animated {
    // hide navigationController so our customToolbar can take its place for better button sizing
	[self.navigationController setNavigationBarHidden:YES animated:NO];
    [super viewWillAppear:animated];
}

- (NSString *) defaultDbPath {			// read only path in bundle
	return [[NSBundle mainBundle] pathForResource:@"charts.db" ofType:nil];	
}

- (NSString *) bestDbPath {				// avoids opening the read-only DB if it has already been moved

	if ([self.dbPath length] > 5) {
		return self.dbPath;
	} else {
		return [self defaultDbPath];
	}
}

- (void) minimizeChart {
 
    CGFloat delta = - self.scc.layer.position.x;
    if (self.scc.layer.position.x < 1.) {
        delta += self.leftGap;    // maximize chart
        [self.minimizeButton setImage:[UIImage imageNamed:@"maximize"]];
    } else {
        [self.minimizeButton setImage:[UIImage imageNamed:@"minimize"]]; 
    }
    
    self.scc->svWidth   -= delta;
    self.scc->pxWidth   = UIScreen.mainScreen.scale * self.scc->svWidth;

    self.scc.layer.position = CGPointMake(self.scc.layer.position.x + delta, self.scc.layer.position.y);
    
    NSInteger shiftBars = round(self.scc.layer.contentsScale* delta/(self.scc->xFactor * self.scc->barUnit));       // don't use floor; it drops bars
    [self.scc updateMaxPercentChangeWithBarsShifted: - shiftBars];  // shiftBars are positive when delta is negative
}

- (void) dragLayer:(UIPanGestureRecognizer *)recognizer delta:(CGFloat)delta {
    
    delta = roundf(delta);      // preserve pixel alignment
    
    if (self.scc.layer.position.x > self.tableView.frame.size.width + 30 && delta > 0) {
        return; // too small
        
    } else if (self.scc.layer.position.x < 30 && [recognizer translationInView:self.view].x < 0) {   // snap to left edge
        
        recognizer.enabled = NO;    // cancel addition touches
        delta = - self.scc.layer.position.x;     // don't set newPoint.x to zero because it causes a bounce
        self.netDelta += delta;
    } else {
        self.netDelta += delta;
    }
        
    self.scc->svWidth -= delta;
    self.scc->pxWidth = UIScreen.mainScreen.scale * self.scc->svWidth;
    
    self.scc.layer.position = CGPointMake(self.scc.layer.position.x + delta, self.scc.layer.position.y);
    
    if (recognizer.enabled == NO || [recognizer state] == UIGestureRecognizerStateEnded) {
        
        NSInteger shiftBars =  ceil(self.scc.layer.contentsScale* self.netDelta/(self.scc->xFactor * self.scc->barUnit));
        
        [self.scc updateMaxPercentChangeWithBarsShifted:- shiftBars];  // shiftBars are positive when delta is negative
        
        recognizer.enabled = YES;
        self.dragWindow = NO;
        
        if (self.scc.layer.position.x < 1.) {
            [self.minimizeButton setImage:[UIImage imageNamed:@"minimize"]];
        } else {
            [self.minimizeButton setImage:[UIImage imageNamed:@"maximize"]];
        }
    }
}

- (void) loadComparisonAtRow:(NSInteger)row {
    
    [self.scc clearChart];
    
    [self.progressIndicator startAnimating];
    
    if ([self.scc.layer zPosition] < 1) {
        
        [self.scc.layer setZPosition:1];
        
        CAKeyframeAnimation* animation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        animation.duration = 1.0;
        animation.values = @[ @0.2, @1.0];
        animation.keyTimes = @[ @0.0, @1.0];
        
        self.scc.layer.opacity = 1.0;
        [self.scc.layer addAnimation:animation forKey:@"opacity"];
    }
    
    [self.scc setComparison:[self.list objectAtIndex:row]];
    [self.scc loadChart];
    [self resetToolbarWithSearch:YES];
}

- (void) tableView:(UITableView *)clickedTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {    
    if (self.list.count > indexPath.row) {
        [self loadComparisonAtRow:indexPath.row];
	}
}

- (void) viewWillDisappear:(BOOL)animated {
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [super viewWillDisappear:animated];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    if ([self resizeFrameToSize:size]) {
        [self resizeSubviewsForSize:size];
    }
}

// the only purpose of this recognizer is to prevent selecting cells behing the CALayer ScrollChartController
- (void)singleTap:(UITapGestureRecognizer *)recognizer {
    
    CGPoint point = [recognizer locationInView:self.view];
    
    BOOL belowTopToolbar = (point.y > self.toolbarHeight) ? YES : NO;

    if (point.x >= self.scc.layer.position.x && belowTopToolbar) {
        recognizer.cancelsTouchesInView = YES;   //
         DLog(@" * * * * single tap CANCELS");
    } else {
        recognizer.cancelsTouchesInView = NO;
    }
}

// required for UIMenuController support
-(BOOL)canBecomeFirstResponder {
    return YES;
}

// required to support multi-touch long press
-(BOOL) gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES ;
}

// To follow the example of the Notes app, the magnifier should appear above the user's finger and should overlap the title bar
// when the price is at the top of the range

// only RootViewController can do that, so it should handle displaying the magnifying glass based on response from SCC
// SCC is the only thing that can inspect its arrays to determine which bars are being pressed and get the data for them
// SCC returns a UIImage that contains the enlarged data and labels for the max and min
- (void)trendline:(UILongPressGestureRecognizer *)recognizer {
    
    for (NSInteger i =0; i < recognizer.numberOfTouches; i++) {
  //      CGPoint touch = [recognizer locationOfTouch:i inView:self.scc];
  //      DLog(@"trendline touch %ld %f, %f", i, touch.x, touch.y);
    }
    
    recognizer.cancelsTouchesInView =YES;
}

- (void)magnify:(UILongPressGestureRecognizer *)recognizer {
    
    if ([recognizer state] == UIGestureRecognizerStateBegan) {
        [self.scc resetPressedBar];
    }

    CGFloat xPress = [recognizer locationInView:self.view].x - 5. - self.scc.layer.position.x; // 5pts of left buffer for grip
    CGFloat yPress = [recognizer locationInView:self.view].y - 5. - self.toolbarHeight;      // 5 pts of top buffer
    
    [self.magnifier setFrame:CGRectMake( [recognizer locationInView:self.view].x - 40, yPress - 75., 100., 100.)];
    
    self.magnifier.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    self.magnifier.layer.borderWidth = 3;
    self.magnifier.layer.cornerRadius = 50;
    self.magnifier.layer.masksToBounds = YES;
    
    // Note that this always returns some image, even when the user moves to the Y axis labels
    // the lift-up behavior should only show a context menu when the user lifts up while a bar is selected
    // SCC can handle this by setting pressedBar = nil during magnifyBarAtX
    
    UIImage *screenshot = [self.scc magnifyBarAtX:xPress  y:yPress];

    [self.magnifier setImage:screenshot];
    [self.magnifier setHidden:NO];
    
    if ([recognizer state] == UIGestureRecognizerStateEnded) {
        [self.magnifier setHidden:YES];
    }
}

- (void)doubleTap:(UITapGestureRecognizer *)recognizer {
    
    recognizer.cancelsTouchesInView = YES;
    
    CGFloat pinchMidpoint = [recognizer locationInView:self.view].x - self.scc.layer.position.x - 5;
    
    DLog(@"pinchmidoint is %f vs scc position %f so pinchMidpoint is %f", [recognizer locationInView:self.view].x, self.scc.layer.position.x, pinchMidpoint);
    
    if (self.scc->xFactor > 10) {
        [self.scc resizeChartImage:0.5 withCenter:pinchMidpoint];
        [self.scc resizeChart:0.5];
    } else {
        [self.scc resizeChartImage:2.0 withCenter:pinchMidpoint];
        [self.scc resizeChart:2.0];
    }
}

- (void) handlePan:(UIPanGestureRecognizer *)recognizer {
    
    recognizer.cancelsTouchesInView = YES;
    
    CGFloat delta, currentShift;
    
    if (recognizer.state == UIGestureRecognizerStateCancelled) {
        self.lastShift = 0;
        return;    // enabled = NO causes another loop with the canceled state, so exit
        
    } else if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.lastShift = 0;
    }
    
    currentShift = [recognizer translationInView:self.view].x;
    delta = currentShift - self.lastShift;

   // DLog(@"%f = %f - %f", delta, currentShift, lastShift);
    
    if (self.dragWindow) {
        self.lastShift = currentShift;
        
        return [self dragLayer:recognizer delta:delta];
    }

    delta *= UIScreen.mainScreen.scale; // adjust for Retina scale after dragLayer call

    NSInteger deltaBars;
    
    if (delta > 0) {
        deltaBars = floor(delta/(self.scc->xFactor * self.scc->barUnit)); 
    } else {
        deltaBars = ceil(delta/(self.scc->xFactor * self.scc->barUnit));
    }
    
    if (deltaBars == 0)  {
        return; // avoid intermediate redraw (kills retina iPad performance)
    } else {
        [self.scc updateMaxPercentChangeWithBarsShifted:deltaBars];
        self.lastShift = currentShift;
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)recognizer {
   // DLog(@"handle pinch with scale %f", (recognizer.scale));
 
    // take location of initial touch into account when calculating view
    
    // the rule is that whatever is bracketed by the users fingers when the pinch starts should be bracketed after redraw
    // as that matches iPhoto zooming
    
    // only horizontal scaling is supported (changing date range), so we just need to find the INITAL center of the touches in view
    // and then scale around that
    // using the center makes more sense than trying to handle multiple touch points
            
    // Note that if the user wants to zoom a section on the right, it should keep that area in view
    
//    CGFloat centerX = [recognizer locationInView:self.view].x;
    
//    if ([recognizer locationInView:self.view].x >= self.scc.layer.position.x) {
    
        recognizer.cancelsTouchesInView =YES;
     
       // DLog(@"recognizer state = %d", recognizer.state);
        CGFloat pinchMidpoint = [recognizer locationInView:self.view].x - self.scc.layer.position.x - 5;
        

        if (recognizer.state == UIGestureRecognizerStateBegan) {
            // DLog(@"start location of touches x = %f", ([recognizer locationInView:self.view].x - self.scc.layer.position.x));
            self.pinchCount = self.pinchMidpointSum = 0.;
            
        } else if (recognizer.state == UIGestureRecognizerStateChanged) {
            self.pinchCount += 1.;
            self.pinchMidpointSum += pinchMidpoint;
            pinchMidpoint = self.pinchMidpointSum / self.pinchCount;          // average of touches smooths touch errors
            [self.scc resizeChartImage:(recognizer.scale)  withCenter:pinchMidpoint];
        } else {
            // DLog(@" end: location of touches x = %f", pinchMidpoint);
            [self.scc resizeChart:(recognizer.scale)];
        }
 //   }
}

- (void) popContainer {
    if (self.popOverNav != nil) {
        [self.popOverNav dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void) reloadList:(Comparison *)comparison {
        
    [self.list removeAllObjects];
    [self setList:[Comparison listAll:[self bestDbPath]]];
    [self.tableView reloadData];

    if (comparison == nil) {
        if (self.list.count > 0) {
            comparison = [self.list objectAtIndex:0];
        }
    }
    
    if (comparison != nil) {
        
        [self.scc clearChart];
        [self.progressIndicator startAnimating];
        
        [self.scc setComparison:comparison];
        [self resetToolbarWithSearch:YES];
        [self.scc loadChart];
    }
}

- (BOOL)isOpaque {
    return YES;
} 

- (void) dbMoved:(NSString *)newPath {

	[self setDbPath:(NSMutableString *)newPath];
    [self reloadList:nil];
}


@end

