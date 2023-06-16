#import "CIAppDelegate.h"
#import "RootViewController.h"
#import "ScrollChartView.h"
#import "ChartOptionsController.h"
#import "ChartInsight-Swift.h" // for DBUpdater

@interface RootViewController ()

@property (assign, nonatomic) CGFloat width;
@property (assign, nonatomic) CGFloat height;
@property (assign, nonatomic) CGFloat statusBarHeight;  // set using safeAreaInsets
@property (assign, nonatomic) CGFloat toolbarHeight;
@property (assign, nonatomic) CGFloat leftGap;
@property (assign, nonatomic) CGFloat lastShift;
@property (assign, nonatomic) CGFloat netDelta;
@property (assign, nonatomic) CGFloat pinchCount;
@property (assign, nonatomic) CGFloat pinchMidpointSum;

@property (assign, nonatomic) BOOL dragWindow;
@property (assign, nonatomic) BOOL newComparison;
@property (assign, nonatomic) BOOL needsReload; // set by reloadWhenVisible

@property (nonatomic, strong) UINavigationController    *popOverNav;    // required for navgiation controller within popover
@property (nonatomic, strong) UITapGestureRecognizer   *doubleTapRecognizer;
@property (nonatomic, strong) UILongPressGestureRecognizer *oneLongPressRecognizer;
@property (nonatomic, strong) UILongPressGestureRecognizer *twoLongPressRecognizer;
@property (nonatomic, strong) UIPanGestureRecognizer   *panRecognizer;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchRecognizer;
@property (nonatomic, strong) UIBarButtonItem *minimizeButton;
@property (nonatomic, strong) UIToolbar *customNavigationToolbar;     //  better formatting than using self.navigationItem

@property (strong, nonatomic) NSDateComponents *days;

@property (strong, nonatomic) ScrollChartView *scc;

@property (strong, nonatomic) NSMutableArray *list;     // stocks from comparison table

@property (strong, nonatomic) NSString *dbPath;

@property (strong, nonatomic) NSDictionary *infoForPressedBar;

@property (strong, nonatomic) UITableView *tableView;

@property (strong, nonatomic) UIBarButtonItem *barTitle;
@end

@implementation RootViewController

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

- (void) addStock:(id)sender {
    
    UIBarButtonItem *button = (UIBarButtonItem *)sender;
        
    if (button.tag == 0) {
        if (self.scc.layer.position.x < 30) {
            return;
        }
        self.newComparison = YES;
    } else {
        self.newComparison = NO;
    }
    
    AddStockController *addStockController = [[AddStockController alloc] init];
    addStockController.delegate = self;
    [self popoverPush:addStockController fromButton:sender];
}

- (void) editStock:(id)sender {
        
    UIBarButtonItem *button = (UIBarButtonItem *)sender;
    
    Stock *stock = (Stock *)button.tag;
    
    ChartOptionsController *ctc = [[ChartOptionsController alloc] initWithStyle:UITableViewStyleGrouped];
    ctc.sparklineKeys = [self.scc.comparison sparklineKeys];
    ctc.stock = stock;
    ctc.delegate = self;
  
    [self popoverPush:ctc fromButton:sender];
}

- (void) reloadWithStock:(Stock *)stock {
    
    if (self.scc != nil) {
        [self.scc.comparison saveToDb];
        [self.scc clearChart];
        [self.progressIndicator startAnimating];
        [self resetToolbarWithSearch:YES];
        [self.scc loadChart];
    } 
}

/* called by ChartOptionsController when chart color or type changes */ 
- (void) redrawWithStock:(Stock *)stock {
    if (self.scc != nil) {
        [self.scc.comparison saveToDb];
        for (UIBarButtonItem *button in self.customNavigationToolbar.items) {
            if (button.tag == (NSInteger)stock) {
                [button setTintColor:[UIColor colorWithCGColor:stock.upColor]];
            }
        }
        [self.scc redrawCharts];
    } 
}

- (void) resetToolbarWithSearch:(BOOL)showSearch {

    if (showSearch) {
        self.minimizeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSearch target:self action:@selector(addStock:)];
    } else {
        self.minimizeButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"hideWebview"] style:UIBarButtonItemStylePlain target:self action:@selector(minimizeChart)];
    }
    
    if ([self.scc comparison] != nil) {

        NSMutableArray *buttons = [NSMutableArray new];
        
        [buttons addObject:self.minimizeButton];
        
        [buttons addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease]];
        
        UIBarButtonItem *button;
        Stock *s;
        NSArray *stockList = self.scc.comparison.stockList;
        for (NSInteger i = 0; i < [stockList count]; i++) {
            
            s = [stockList objectAtIndex:i];

            UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:s.symbol style:UIBarButtonItemStylePlain target:self action:@selector(editStock:)];
            [button setTag:(NSInteger)s];     
                        
            [button setTintColor:[UIColor colorWithCGColor:s.upColor]];
            
            [buttons addObject:button];
            [button release];
        }
        
        if ([stockList count] < 3 || UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            
            button = [[UIBarButtonItem alloc] initWithTitle:@"compare" style:UIBarButtonItemStylePlain target:self action:@selector(addStock:)];
                        
            NSDictionary *smallFont = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont systemFontOfSize:10], NSFontAttributeName,nil];
            [button setTitleTextAttributes:smallFont forState:UIControlStateNormal];
            [button setTitleTextAttributes:smallFont forState:UIControlStateHighlighted];
            
            [button setTag:(NSInteger)self.scc.comparison];
            [buttons addObject:button];
        }
        
        [buttons addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease]];

        [self.customNavigationToolbar setItems:buttons];
    }
}

- (void)viewDidLoad {
    DB *updater = [[DB alloc] init];
    [updater moveDBToDocumentsForDelegate:self];                      // copy db to documents and/or update existing db
    
    [super viewDidLoad];
    
    [self resizeFrameToSize:self.view.frame.size];
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.extendedLayoutIncludesOpaqueBars = NO;

    self.leftGap = (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) ? 60 : 100;
    
    [self setGregorian:[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]];
    [self setDays:[[NSDateComponents alloc] init]];
    
    self.customNavigationToolbar = [UIToolbar new];
	self.customNavigationToolbar.translucent = NO;
    [self.customNavigationToolbar setFrame:CGRectMake(0, self.statusBarHeight, self.width, self.toolbarHeight)];
    [self.view addSubview:self.customNavigationToolbar];
    
    [self setMinimizeButton:[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"maximize"] style:UIBarButtonItemStylePlain target:self action:@selector(minimizeChart)]];
    
    [self setList:[Comparison listAll:[self bestDbPath]]];
    
    // There's a toolbar above the tableView and a tabBar below so reduce height by 2 * self.toolbarHeight
    self.tableView = [[[UITableView alloc] initWithFrame:CGRectMake(0, self.toolbarHeight + self.statusBarHeight,
                                                                    205, self.height) // set by resizeFrameToSize:
                                                   style:UITableViewStylePlain] autorelease];
        
    // EK this is also set in viewDidAppear:  self.view.backgroundColor = UIColor.secondarySystemBackgroundColor;
    
    [self.tableView setClipsToBounds:NO];      // YES would create rounded corners, which doesn't matter when the background is all the same
	[self.tableView setDelegate:self];
	[self.tableView setDataSource:self];
	[self.tableView setScrollEnabled:YES];
	[self.view addSubview:self.tableView];
    [self.view sendSubviewToBack:self.tableView];
    
    [self setScc:[[ScrollChartView alloc] init]];
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

    [self setProgressIndicator:[[ProgressIndicator alloc] initWithFrame:CGRectMake(0, 0, self.width, 4.)]];
    // Add progressIndicator as subview of customNavigationToolbar to ensure placement below status bar
    [self.customNavigationToolbar addSubview:self.progressIndicator];
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
    self.progressIndicator.frame = CGRectMake(0, 0, self.width, 4); // relative to parent customNavigationToolbar
    self.scc.layer.position = CGPointMake(self.scc.layer.position.x, combinedToolbarHeight);
    
    [self.tableView reloadData];
    
    CGFloat delta = self.scc.bounds.size.width - newSize.width;
    NSInteger shiftBars = floor(self.scc.layer.contentsScale* delta/(self.scc.xFactor * self.scc.barUnit));
    
    [self.scc updateMaxPercentChangeWithBarsShifted: -shiftBars];  // shiftBars are positive when delta is negative

    self.scc.bounds = CGRectMake(0, 0, newSize.width, newSize.height - combinedToolbarHeight);
    [self.scc resize];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if ([self resizeFrameToSize:self.view.frame.size]) {
        [self resizeSubviewsForSize:CGSizeMake(self.width, self.height)];
    }
    if (self.needsReload) {
        [self reloadList:nil];
        self.needsReload = NO;
    }
}

/// called by AddStockController when a new stock is added
- (void) insertStock:(Stock *)stock {
    DLog(@"Inserted %@ %@", stock.symbol, stock.name);
    
    if (self.newComparison || self.scc.comparison == nil) {
        [self.scc setComparison:[[Comparison alloc] init]];
        [self.scc.comparison setId: 0];  // new unsaved comparison
        [self.scc.comparison setStockList:[NSMutableArray arrayWithCapacity:3]];
    }
    
    NSMutableArray *otherColors = [NSMutableArray arrayWithArray:[ChartOptionsController chartColors]];
    
    for (NSInteger i = 0; i < self.scc.comparison.stockList.count; i++) {
        NSInteger grayIndex = otherColors.count - 1;
        
        // Stop comparing before grayIndex so gray is used by default for multiple stocks
        for (NSInteger c = 0; c < grayIndex; c++) {

            Stock *s = self.scc.comparison.stockList[i];
            if ([s matchesColor:[otherColors objectAtIndex:c]]) {
                [otherColors removeObjectAtIndex:c];
                // can't just break because the color could be used by the 2nd stock of 3
            }
        }
    }
        
    // don't alter chart type because it is set as a default
    [stock setUpColor:[(UIColor *)[otherColors objectAtIndex:0] CGColor]];

    UIColor *green = [[ChartOptionsController chartColors] objectAtIndex:0];

    if ([stock matchesColor:green]) {
    //    // DLog(@"matches green");
        [stock setColor: [UIColor redColor].CGColor ];
    } else {
        [stock setColor:[(UIColor *)[otherColors objectAtIndex:0] CGColor]];
    }
    
    if (otherColors.count > 1) {
        [otherColors removeObjectAtIndex:0];
    }
    [[self.scc.comparison stockList] addObject:stock];
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

- (void) deleteStock:(NSInteger)sender {
    
    if (self.scc != nil && sender > 0) {
        Stock *s = (Stock *)sender;

        UIBarButtonItem *buttonToRemove = nil;
        
        for (UIBarButtonItem *button in self.customNavigationToolbar.items) {
            if (button.tag == sender) {
                buttonToRemove = button;
            }
        }
        
        [self.scc.comparison deleteStock:s];
        
        if (self.scc.comparison.stockList.count < 1) {
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

/// Find the keyWindow and get the safeAreaInsets for the notch and other unsafe areas
- (UIEdgeInsets) getSafeAreaInsets {
    UIEdgeInsets noInsets = UIEdgeInsetsMake(0, 0, 0, 0);
    for (UIWindowScene *scene in [[[UIApplication sharedApplication] connectedScenes] allObjects]) {
        if (scene.keyWindow != nil) { // can be nil for iPadOS apps which support multiple windows
            UIWindow *keyWindow = scene.keyWindow;
            if ([keyWindow respondsToSelector:@selector(safeAreaInsets)]) {
                return keyWindow.safeAreaInsets;
            }
        }
    }
    return noInsets;
}

- (BOOL) resizeFrameToSize:(CGSize)newSize {
	CGFloat newWidth, newHeight;
    UIEdgeInsets safeAreaInsets = [self getSafeAreaInsets]; // replace deprecated method
    
    self.toolbarHeight = 44;
    self.statusBarHeight = 20;
    if (safeAreaInsets.top > self.statusBarHeight) {
        self.statusBarHeight = safeAreaInsets.top;
    }
    
    newWidth = newSize.width;

    // To show stock ticker buttons in the toolbar, a custom toolbar is displayed and the navigationController's toolbar is hidden
    // Thus newSize must be reduced by height of 2 toolbars
    newHeight = newSize.height - self.statusBarHeight - 2 * self.toolbarHeight - safeAreaInsets.bottom;
        
	if (self.width != newWidth) {
		self.width = newWidth;
        self.height = newHeight;
 		return TRUE;
	}
	return FALSE;
}

- (void) viewWillAppear:(BOOL)animated {
    // hide navigationController so our customToolbar can take its place for better button sizing
	[self.navigationController setNavigationBarHidden:YES animated:NO];
    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground]) {
        [self.customNavigationToolbar setBarStyle:UIBarStyleBlack];
    } else {
        [self.customNavigationToolbar setBarStyle:UIBarStyleDefault];
    }
    
    self.view.backgroundColor = [UIColor secondarySystemBackgroundColor];
    
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
    
    self.scc.svWidth   -= delta;
    self.scc.pxWidth   = UIScreen.mainScreen.scale * self.scc.svWidth;

    self.scc.layer.position = CGPointMake(self.scc.layer.position.x + delta, self.scc.layer.position.y);
    
    NSInteger shiftBars = round(self.scc.layer.contentsScale* delta/(self.scc.xFactor * self.scc.barUnit));       // don't use floor; it drops bars
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
        
    self.scc.svWidth -= delta;
    self.scc.pxWidth = UIScreen.mainScreen.scale * self.scc.svWidth;
    
    self.scc.layer.position = CGPointMake(self.scc.layer.position.x + delta, self.scc.layer.position.y);
    
    if (recognizer.enabled == NO || [recognizer state] == UIGestureRecognizerStateEnded) {
        
        NSInteger shiftBars =  ceil(self.scc.layer.contentsScale* self.netDelta/(self.scc.xFactor * self.scc.barUnit));
        
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

// the only purpose of this recognizer is to prevent selecting cells behing the CALayer ScrollChartView
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
    
    const float midpoint = 50.;
    const float height = 2 * midpoint;
    const float width = 2 * midpoint;
    
    [self.magnifier setFrame:CGRectMake( [recognizer locationInView:self.view].x - midpoint, yPress - midpoint, width, height)];
    
    self.magnifier.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    self.magnifier.layer.borderWidth = 1;
    self.magnifier.layer.cornerRadius = midpoint;
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

// 2x zoom on the tapped locationInView if current zoom is less than max (scc.xFactor = 50)
- (void)doubleTap:(UITapGestureRecognizer *)recognizer {
    
    recognizer.cancelsTouchesInView = YES;
    
    CGFloat pinchMidpoint = [recognizer locationInView:self.view].x - self.scc.layer.position.x - 5;
    
    [self.scc resizeChartImage:2.0 withCenter:pinchMidpoint];
    [self.scc resizeChart:2.0];
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
        deltaBars = floor(delta/(self.scc.xFactor * self.scc.barUnit));
    } else {
        deltaBars = ceil(delta/(self.scc.xFactor * self.scc.barUnit));
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

- (void) reloadWhenVisible {
    self.needsReload = YES;
}

- (BOOL)isOpaque {
    return YES;
} 

- (void) dbMoved:(NSString *)newPath {
    DLog(@"Moved to %@", newPath);
	[self setDbPath:newPath];
    [self reloadList:nil];
}


@end

