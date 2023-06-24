#import "RootViewController.h"
#import "ScrollChartView.h"
#import "ChartOptionsController.h"
#import "ChartInsight-Swift.h" // for Swift classes

@interface RootViewController ()

@property (assign, nonatomic) CGFloat width;
@property (assign, nonatomic) CGFloat height;
@property (assign, nonatomic) CGFloat rowHeight;
@property (assign, nonatomic) CGFloat statusBarHeight;  // set using safeAreaInsets
@property (assign, nonatomic) CGFloat toolbarHeight;
@property (assign, nonatomic) CGFloat tableViewWidthVisible;
@property (assign, nonatomic) CGFloat lastShift;
@property (assign, nonatomic) CGFloat pinchCount;
@property (assign, nonatomic) CGFloat pinchMidpointSum;

@property (assign, nonatomic) BOOL needsReload; // set by reloadWhenVisible

@property (nonatomic, strong) UINavigationController    *popOverNav;    // required for navgiation controller within popover
@property (nonatomic, strong) UITapGestureRecognizer   *doubleTapRecognizer;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressRecognizer;
@property (nonatomic, strong) UIPanGestureRecognizer   *panRecognizer;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchRecognizer;
@property (nonatomic, strong) UIBarButtonItem *toggleListButton;
@property (nonatomic, strong) UIBarButtonItem *addStockButton;
@property (nonatomic, strong) UIToolbar *addStockToolbar;             //  in tableView header
@property (nonatomic, strong) UIToolbar *navStockButtonToolbar;     //  For stock ticker buttons in self.navigationItem.titleView

@property (strong, nonatomic) ScrollChartView *scc;

@property (strong, nonatomic) NSArray *list;     // stocks from comparison table

@property (strong, nonatomic) UITableView *tableView;

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

/// User clicked compare button to add compare another stock to the current chart
- (void) compareStock:(id)sender {
    AddStockController *addStockController = [[AddStockController alloc] init];
  //  addStockController.delegate = self;
    addStockController.isNewComparison = NO;
    [self popoverPush:addStockController fromButton:sender];
}

/// User clicked "+" add button in tableView header to chart a new stock by itself (technically this is a single-stock comparison)
- (void) addStock:(id)sender {
    AddStockController *addStockController = [[AddStockController alloc] init];
    //addStockController.delegate = self;
    addStockController.isNewComparison = YES;
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
        [self resetToolbar];
        [self.scc loadChart];
    } 
}

/* called by ChartOptionsController when chart color or type changes */ 
- (void) redrawWithStock:(Stock *)stock {
    if (self.scc != nil) {
        [self.scc.comparison saveToDb];
        for (UIBarButtonItem *button in self.navStockButtonToolbar.items) {
            if (button.tag == (NSInteger)stock) {
                [button setTintColor:stock.upColor];
            }
        }
        [self.scc redrawCharts];
    } 
}

- (void) resetToolbar {
    
    if ([self.scc comparison] != nil) {

        NSMutableArray *buttons = [NSMutableArray new];
        
        [buttons addObject:self.toggleListButton];
        
        [buttons addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease]];
        
        UIBarButtonItem *button;
        Stock *s;
        NSArray *stockList = self.scc.comparison.stockList;
        for (NSInteger i = 0; i < [stockList count]; i++) {
            
            s = [stockList objectAtIndex:i];

            UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:s.symbol style:UIBarButtonItemStylePlain target:self action:@selector(editStock:)];
            [button setTag:(NSInteger)s];     
                        
            [button setTintColor:s.upColor];
            
            [buttons addObject:button];
            [button release];
        }
        
        if ([stockList count] < 3 || UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            
            button = [[UIBarButtonItem alloc] initWithTitle:@"compare" style:UIBarButtonItemStylePlain target:self action:@selector(compareStock:)];
                        
            NSDictionary *smallFont = [NSDictionary dictionaryWithObjectsAndKeys:[UIFont systemFontOfSize:10], NSFontAttributeName,nil];
            [button setTitleTextAttributes:smallFont forState:UIControlStateNormal];
            [button setTitleTextAttributes:smallFont forState:UIControlStateHighlighted];
            
            [button setTag:(NSInteger)self.scc.comparison];
            [buttons addObject:button];
        }
        
        [buttons addObject:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease]];

        [self.navStockButtonToolbar setItems:buttons];
    }
}

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    [self isNewFrameSize:self.view.frame.size];
    self.edgesForExtendedLayout = UIRectEdgeNone;
    self.extendedLayoutIncludesOpaqueBars = NO;

    self.tableViewWidthVisible = (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) ? 66 : 100;
    self.rowHeight = (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) ? 40 : 44;
    
    [self setGregorian:[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]];
    
    self.navStockButtonToolbar = [UIToolbar new];
	self.navStockButtonToolbar.translucent = NO;
    [self.navStockButtonToolbar setFrame:CGRectMake(0, 0, self.width, self.toolbarHeight)];
    self.navigationItem.titleView = self.navStockButtonToolbar;
    
    self.addStockToolbar = [UIToolbar new];
    self.addStockToolbar.translucent = NO;
    [self.addStockToolbar setFrame:CGRectMake(0, 0, self.tableViewWidthVisible, self.rowHeight)];
    // addStockToolbar will be added as tableView footer
    
    UIBarButtonItem *addStockButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                    target:self action:@selector(addStock:)];
    [self.addStockToolbar setItems:@[addStockButton]];
     
    self.toggleListButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"toggleList"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self action:@selector(toggleList)];
    
    self.tableView = [[[UITableView alloc] initWithFrame:CGRectMake(0, 0, 205, self.height) // set by resizeFrameToSize:
                                                   style:UITableViewStylePlain] autorelease];
            
    [self.tableView setClipsToBounds:NO];      // YES would create rounded corners, which doesn't matter when the background is all the same
	[self.tableView setDelegate:self];
	[self.tableView setDataSource:self];
	[self.tableView setScrollEnabled:YES];
    self.tableView.sectionHeaderTopPadding = 1; // reduced from default padding but larger than zero to show upper border
	[self.view addSubview:self.tableView];
    [self.view sendSubviewToBack:self.tableView];
    
    [self setScc:[[ScrollChartView alloc] init]];
    [self.scc.layer setAnchorPoint:CGPointMake(0., 0.)];                      // allows bounds = frame
    [self.scc.layer setPosition:CGPointMake(self.tableViewWidthVisible, 0)];  // ipad menu bar
    [self.scc setBounds:CGRectMake(0, 0, self.width, self.height - 4)]; // Leave space between months and TabBar
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
    [self.navStockButtonToolbar addSubview:self.progressIndicator];
    [self.progressIndicator.layer setZPosition:4];
    [self.progressIndicator setHidden:YES]; // until startAnimating is called
    [self.scc setProgressIndicator:self.progressIndicator];
    
    // init gesture recognizers early so adding a new chart (vs clicking tableview) has gesture recognizers 
    self.doubleTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    [self.doubleTapRecognizer setNumberOfTapsRequired:2];
    [self.scc addGestureRecognizer:self.doubleTapRecognizer];

    self.longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(magnify:)];
    [self.longPressRecognizer setMinimumPressDuration:0.5];
    [self.longPressRecognizer setNumberOfTouchesRequired:1];
    [self.scc addGestureRecognizer:self.longPressRecognizer];
    
    self.pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self.scc addGestureRecognizer:self.pinchRecognizer];
    
    self.panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.scc addGestureRecognizer:self.panRecognizer];
 
    if (self.list.count > 0) {
        [self loadComparisonAtRow:0];
    }
}

- (void) resizeSubviewsForSize:(CGSize)newSize {
    [self.navStockButtonToolbar setFrame:CGRectMake(0, 0, newSize.width, self.toolbarHeight)];
    self.tableView.frame = CGRectMake(0, 0, 205, newSize.height);
    self.progressIndicator.frame = CGRectMake(0, 0, self.width, 4); // relative to parent customNavigationToolbar
    self.scc.layer.position = CGPointMake(self.scc.layer.position.x, 0);
    
    [self.tableView reloadData];
    
    CGFloat delta = self.scc.bounds.size.width - newSize.width;
    NSInteger shiftBars = floor(self.scc.layer.contentsScale* delta/(self.scc.xFactor * self.scc.barUnit));
    
    [self.scc updateMaxPercentChangeWithBarsShifted: -shiftBars];  // shiftBars are positive when delta is negative

    self.scc.bounds = CGRectMake(0, 0, newSize.width, newSize.height);
    [self.scc resize];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if ([self isNewFrameSize:self.view.frame.size]) {
        [self resizeSubviewsForSize:CGSizeMake(self.width, self.height)];
    }
    if (self.needsReload) {
        [self reloadKeepExistingComparison:NO];
        self.needsReload = NO;
    }
}

/// called by AddStockController when a new stock is added
- (void) insertStock:(Stock *)stock isNewComparison:(BOOL)isNewComparison {
    
    if (isNewComparison || self.scc.comparison == nil) {
        [self.scc setComparison:[[Comparison alloc] init]];
        [self.scc.comparison setId: 0];  // new unsaved comparison
        [self.scc.comparison setStockList:[NSMutableArray arrayWithCapacity:3]];
    }
    
    NSMutableArray *otherColors = [NSMutableArray arrayWithArray:Stock.chartColors];
    UIColor *lightGreen = otherColors[0];
    
    // If this stock is being compared to other stocks, make sure it uses a different color or gray
    // But don't alter chart type because it is set as a default
    for (NSInteger i = 0; i < self.scc.comparison.stockList.count; i++) {
        NSInteger grayIndex = otherColors.count - 1;
        
        // Stop comparing before grayIndex so gray is used by default for multiple stocks
        for (NSInteger c = 0; c < grayIndex; c++) {

            Stock *s = self.scc.comparison.stockList[i];
            if ([s hasUpColor:[otherColors objectAtIndex:c]]) {
                [otherColors removeObjectAtIndex:c];
                // can't just break because the color could be used by the 2nd stock of 3
            }
        }
    }
        
    [stock setUpColor:(UIColor *)[otherColors objectAtIndex:0]];

    if ([stock hasUpColor:lightGreen]) {
        stock.color = UIColor.redColor;
    } else {
        stock.color = (UIColor *)[otherColors objectAtIndex:0];
    }
    
    if (otherColors.count > 1) {
        [otherColors removeObjectAtIndex:0];
    }
    [self.scc.comparison add:stock];
    [self reloadKeepExistingComparison:YES];
    [self popContainer];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.list count];
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.rowHeight;
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
    return cell;
}

- (void) deleteStock:(NSInteger)sender {
    
    if (self.scc != nil && sender > 0) {
        Stock *s = (Stock *)sender;
        
        // deleteStock runs async so determine stockList count before calling it
        NSInteger stockCountBeforeDeletion = self.scc.comparison.stockList.count;
        
        [self.scc.comparison deleteStock:s];
        
        if (stockCountBeforeDeletion <= 1) {
            [self.scc.comparison deleteFromDb];
            [self reloadKeepExistingComparison:NO];
        } else {
            [self.scc redrawCharts];
            [self reloadKeepExistingComparison:YES];
        }
        [self resetToolbar];
    }
    [self popContainer];
}

/// Find the keyWindow and get the safeAreaInsets for the notch and other unsafe areas
- (UIEdgeInsets) getSafeAreaInsets {
    for (UIWindowScene *scene in [[[UIApplication sharedApplication] connectedScenes] allObjects]) {
        if (scene.keyWindow != nil) { // can be nil for iPadOS apps which support multiple windows
            UIWindow *keyWindow = scene.keyWindow;
            if ([keyWindow respondsToSelector:@selector(safeAreaInsets)]) {
                return keyWindow.safeAreaInsets;
            }
        }
    }
    return UIEdgeInsetsMake(0, 0, 0, 0);
}

- (BOOL) isNewFrameSize:(CGSize)newSize {
    CGFloat newWidth = newSize.width;
    CGFloat newHeight;
    UIEdgeInsets safeAreaInsets = [self getSafeAreaInsets]; // replace deprecated method
    
    self.toolbarHeight = 44; // Extra height for lines
    self.statusBarHeight = 20;
    if (safeAreaInsets.top > self.statusBarHeight) {
        self.statusBarHeight = safeAreaInsets.top;
    }

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
	//[self.navigationController setNavigationBarHidden:YES animated:NO];
//    [self.navigationController setToolbarHidden:NO animated:NO]
    
    self.view.backgroundColor = [UIColor secondarySystemBackgroundColor];
    
    [super viewWillAppear:animated];
}

- (void) toggleList {
 
    CGFloat delta = - self.scc.layer.position.x;
    if (self.scc.layer.position.x < 1.) {
        delta += self.tableViewWidthVisible;    // maximize chart
    }
    
    self.scc.svWidth   -= delta;
    self.scc.pxWidth   = UIScreen.mainScreen.scale * self.scc.svWidth;

    self.scc.layer.position = CGPointMake(self.scc.layer.position.x + delta, self.scc.layer.position.y);
    
    NSInteger shiftBars = round(self.scc.layer.contentsScale* delta/(self.scc.xFactor * self.scc.barUnit));       // don't use floor; it drops bars
    [self.scc updateMaxPercentChangeWithBarsShifted: - shiftBars];  // shiftBars are positive when delta is negative
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
    [self resetToolbar];
}

- (void) tableView:(UITableView *)clickedTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {    
    if (self.list.count > indexPath.row) {
        [self loadComparisonAtRow:indexPath.row];
	}
}

// Button to add stocks in header so results appear above keyboard
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return self.addStockToolbar;
}

-(CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return self.rowHeight;
}

- (void) viewWillDisappear:(BOOL)animated {
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [super viewWillDisappear:animated];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    if ([self isNewFrameSize:size]) {
        [self resizeSubviewsForSize:size];
    }
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
    delta = (currentShift - self.lastShift) * UIScreen.mainScreen.scale;

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
     
        CGFloat pinchMidpoint = [recognizer locationInView:self.view].x - self.scc.layer.position.x - 5;
        

        if (recognizer.state == UIGestureRecognizerStateBegan) {
            self.pinchCount = self.pinchMidpointSum = 0.;
            
        } else if (recognizer.state == UIGestureRecognizerStateChanged) {
            self.pinchCount += 1.;
            self.pinchMidpointSum += pinchMidpoint;
            pinchMidpoint = self.pinchMidpointSum / self.pinchCount;          // average of touches smooths touch errors
            [self.scc resizeChartImage:(recognizer.scale)  withCenter:pinchMidpoint];
        } else {
            [self.scc resizeChart:(recognizer.scale)];
        }
 //   }
}

- (void) popContainer {
    if (self.popOverNav != nil) {
        [self.popOverNav dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void) reloadKeepExistingComparison:(BOOL)keepComparison {
    
    // Replace completionHandler with async function after rewriting this class to Swift
    [Comparison listAllWithCompletionHandler:^(NSArray <Comparison *> *newList) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.list = newList;
            [self.tableView reloadData];

            Comparison *comparisonToChart = nil;
            if (keepComparison) {
                comparisonToChart = self.scc.comparison;
            } else if (self.list.count > 0) {
                comparisonToChart = [self.list objectAtIndex:0];
            }

            if (comparisonToChart != nil) {
                [self.scc clearChart];
                [self.progressIndicator startAnimating];

                [self.scc setComparison:comparisonToChart];
                [self resetToolbar];
                [self.scc loadChart];
            }
        });
    }];
}

- (void) reloadWhenVisible {
    self.needsReload = YES;
}

- (BOOL)isOpaque {
    return YES;
} 

- (void)updateList:(NSArray <Comparison *>*)newList {
    self.list = newList;
    [self.tableView reloadData];

    if (self.list.count > 0) {
        Comparison *comparisonToChart = self.list[0];
        [self.progressIndicator startAnimating];
        [self.scc setComparison:comparisonToChart];
        [self resetToolbar];
        [self.scc loadChart];
    }
}


@end

