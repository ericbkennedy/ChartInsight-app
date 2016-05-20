#import "CIAppDelegate.h"
#import "RootViewController.h"
#import "ScrollChartController.h"
#import "ChartOptionsController.h"
#import "FindSeriesController.h"
#import "MoveDB.h"
#import "SettingsViewController.h"
#import "SupportActivity.h"

@interface RootViewController () <MFMailComposeViewControllerDelegate>

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
@property (nonatomic, strong) UIWebView                     *webView;
@property (nonatomic, strong) UIActivityIndicatorView   *webViewDownloading;
@property (nonatomic, strong) UITapGestureRecognizer   *doubleTapRecognizer;
@property (nonatomic, strong) UILongPressGestureRecognizer *oneLongPressRecognizer;
@property (nonatomic, strong) UILongPressGestureRecognizer *twoLongPressRecognizer;
@property (nonatomic, strong) UIPanGestureRecognizer   *panRecognizer;
@property (nonatomic, strong) UIPinchGestureRecognizer *pinchRecognizer;
@property (nonatomic, strong) UIBarButtonItem *minimizeButton;
@property (nonatomic, strong) UIBarButtonItem *shareChartButton;

@property (nonatomic, strong) UIBarButtonItem *webBackButton;
@property (nonatomic, strong) UIBarButtonItem *webForwardButton;
@property (nonatomic, strong) UIBarButtonItem *webRefreshButton;
@property (nonatomic, strong) UIBarButtonItem *webShareButton;

@property (nonatomic, strong) UIToolbar *customNavigationToolbar;     //  better formatting than using self.navigationItem
@property (strong, nonatomic) UIToolbar *settingsToolbar;
@property (nonatomic, strong) UIToolbar *webToolbar;

@property (strong, nonatomic) id popover;

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
    // don't release thigns set to autorelease - set them to nil in viewDidUnload
    [_list removeAllObjects];
    [_list release];
    [_gregorian release];
    [super dealloc];
}

// iOS 6 Autorotation support.
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void) popoverPush:(UIViewController *)vc createRVC:(BOOL)createRVC  fromButton:(UIBarButtonItem *)button {
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        
        Class classPopoverController = NSClassFromString(@"UIPopoverController");
        
        if (_popover != nil) {  // release it to avoid two popovers simultaneously
            [_popover dismissPopoverAnimated:YES];
            [_popover release];
        }
        
        if (createRVC) {
            [self setPopOverNav:[[UINavigationController alloc] initWithRootViewController:vc]];
            
            self.popover = [[classPopoverController alloc] initWithContentViewController:self.popOverNav];
            
        } else {
            self.popover = [[classPopoverController alloc] initWithContentViewController:vc];
        }
        
        [_popover setDelegate:vc];
        [_popover presentPopoverFromBarButtonItem:button permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
        
    } else {
        [self setTitle:@"Back"];		// Required for back button
        [[self navigationController] pushViewController:vc animated:NO];
    }    
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
    
    [self popoverPush:fcc createRVC:NO fromButton:sender];
}

- (void) editSeries:(id)sender {
        
    UIBarButtonItem *button = (UIBarButtonItem *)sender;
    
    Series *series = (Series *)button.tag;
    
    ChartOptionsController *ctc = [[ChartOptionsController alloc] initWithStyle:UITableViewStyleGrouped];
    [ctc setSparklineKeys:[self.scc.comparison sparklineKeys]];
    [ctc setSeries:series];
    [ctc setDelegate:self];
    [ctc setGregorian:self.gregorian];
  
    [self popoverPush:ctc createRVC:YES fromButton:sender];
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
    
    // DLog(@"redrawWithSeries with series %@", series.symbol);
    
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
        [buttons addObject:self.shareChartButton];

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

- (BOOL)prefersStatusBarHidden {
    return (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) ? YES: NO;
}

- (void)viewDidLoad {
    [self setPopover:nil];
        
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
    self.settingsToolbar.frame = CGRectMake(0, self.height, 205, 44);
    
    UIBarButtonItem *settingsItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"settingsUnselected"] style:UIBarButtonItemStylePlain target:self action:@selector(editSettings:)];
    
    UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:NULL action:NULL];
    
    [self.settingsToolbar setItems:@[settingsItem, flexibleSpace]];
    [self.view addSubview:self.settingsToolbar];
    
    [self setShareChartButton:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareChart)]];
   
    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground] == NO) {
        [self.customNavigationToolbar setBarStyle:UIBarStyleDefault];
        [self.settingsToolbar setBarStyle:UIBarStyleDefault];
    } else {
    	[self.customNavigationToolbar setBarStyle:UIBarStyleBlack];
        [self.settingsToolbar setBarStyle:UIBarStyleBlack];
    }
    
    [self setList:[Comparison listAll:[self bestDbPath]]];
    
    self.tableView = [[[UITableView alloc] initWithFrame:CGRectMake(0, 44, 205, self.height - 88) style:UITableViewStylePlain] autorelease];
    
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
//    [self.scc setOpacity:0.];
    [self.scc.layer setZPosition:1];
    [self.scc setNeedsDisplay];
    [self.view.layer setNeedsDisplay];
    
    [self setMagnifier:[[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 100., 100.)]];
    [self.magnifier.layer setContentsScale:UIScreen.mainScreen.scale];
    [self.magnifier.layer setZPosition:3];
    [self.magnifier setHidden:YES];
    [self.view addSubview:self.magnifier];
    
    [self setWebView:[[UIWebView alloc] init]];
    [self.webView setHidden: YES];
    [self.webView setScalesPageToFit:YES];
    [self.webView setDelegate:self];
    [self.view addSubview:self.webView];
    [self.webView.layer setZPosition:3];
    
    self.webToolbar = [UIToolbar new];
	[self.webToolbar setBarStyle:UIBarStyleBlack];
	[self.webToolbar setTranslucent:NO];
    [self.webToolbar setFrame:CGRectMake(0, self.height, self.width, self.toolbarHeight)];
    [self.webToolbar.layer setZPosition:3];
    [self.webToolbar setHidden:YES];
    [self.view addSubview:self.webToolbar];
    
    [self setWebBackButton:[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"back"] style:UIBarButtonItemStylePlain target:self.webView action:@selector(goBack)]];
    [self.webBackButton setEnabled:NO];
    [self setWebForwardButton:[[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"forward"] style:UIBarButtonItemStylePlain target:self.webView action:@selector(goForward)]];
    [self.webForwardButton setEnabled:NO];
    
    [self setWebRefreshButton:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self.webView action:@selector(reload)]];
    [self setWebShareButton:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(webShare)]];
    
    [self.webToolbar setItems:[NSArray arrayWithObjects:
                               [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease],
                               self.webBackButton,
                               [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease],
                               self.webForwardButton,
                               [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease],
                               self.webRefreshButton,
                               [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease],
                               self.webShareButton,
                               [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease], nil]];
        
    [self setWebViewDownloading:[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite]];
    
    [self setProgressIndicator:[[ProgressIndicator alloc] initWithFrame:CGRectMake(self.width/2 - 80, self.height/2 - 40, 160, 75)]];
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

- (void) resizeSubviews
{
    [self.customNavigationToolbar setFrame:CGRectMake(0, 0, self.width, self.toolbarHeight)];
    [self.tableView setFrame:CGRectMake(0, self.toolbarHeight + 44, 205, self.height - 44)];
    [self.tableView reloadData];
    [self.progressIndicator setFrame:CGRectMake(self.width/2 - 80, self.height/2 - 40, 160, 75)];
    
    [self.scc.layer setPosition:CGPointMake(self.scc.layer.position.x, self.toolbarHeight)];    // ipad menu bar
    
    CGFloat delta = self.scc.bounds.size.width - self.width;
    NSInteger shiftBars = floor(self.scc.layer.contentsScale* delta/(self.scc->xFactor * self.scc->barUnit));
    
    [self.scc updateMaxPercentChangeWithBarsShifted:- shiftBars];  // shiftBars are positive when delta is negative

    if ((UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) && NO == self.webView.hidden) {
        [self.scc setBounds:CGRectMake(0, 0, self.width, 288)];
        [self.webView setFrame:CGRectMake(0, self.toolbarHeight + 288., self.width, self.height - 288. - self.toolbarHeight)];
    } else {
        [self.scc setBounds:CGRectMake(0, 0, self.width, self.height)];
        [self.webView setFrame:CGRectMake(0, self.toolbarHeight, self.width, self.height - self.toolbarHeight)];
    }
    [self.webToolbar setFrame:CGRectMake(0, self.height, self.width, self.toolbarHeight)];
    
    [self.scc resize];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if ([self resizeFrameToSize:[UIScreen mainScreen].bounds.size]) {
        [self resizeSubviews];
    }
}

// called by FindSeriesController when a new stock is added
- (void) insertSeries:(NSMutableArray *)newSeriesList {
    
  //  DLog(@"running insert series with newserieslist count %d", [newSeriesList count]);

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
    
  //  DLog(@"deleteSeries with sender %d", sender);
    
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


- (BOOL) resizeFrameToSize:(CGSize)newSize
{
	CGFloat newWidth, newHeight;
    self.toolbarHeight = 44;
    
    newWidth = newSize.width;
    newHeight = newSize.height;
    
    self.statusBarHeight = (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) ? 20. : 0;
    
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
    
    if (self.webView.hidden == NO) {    // WebView showing, so hide it
        [self.progressIndicator stopAnimating];
        [self.webView loadHTMLString:@"" baseURL:[NSURL URLWithString:@"about:blank"]];
        
        [self resetToolbarWithSearch:YES];
        self.scc->showDotGrips = YES;
        [self.scc.layer setPosition:CGPointMake(0, self.toolbarHeight)];  // ipad menu bar
        [self.scc setBounds:CGRectMake(0, 0, self.width, self.height)];
        [self.minimizeButton setImage:[UIImage imageNamed:@"minimize"]];
        [self.scc resize];
        [self.webView setHidden:YES];
        [self.webToolbar setHidden:YES];
    }
    
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
        animation.delegate = self;
        
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

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
   if ([self resizeFrameToSize:size]) {
        [self resizeSubviews];
    }
}

// the only purpose of this recognizer is to prevent selecting cells behing the CALayer ScrollChartController
- (void)singleTap:(UITapGestureRecognizer *)recognizer {
    
    CGPoint point = [recognizer locationInView:self.view];
    
    BOOL belowTopToolbar = (point.y > self.toolbarHeight) ? YES : NO;
    
    if (self.webView.hidden == NO && point.y > self.toolbarHeight && point.y - self.toolbarHeight < self.height) {
     }
    
    if (point.x >= self.scc.layer.position.x && belowTopToolbar && (self.webView.hidden || point.y < self.webView.frame.origin.y)) {
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
        CGPoint touch = [recognizer locationOfTouch:i inView:self.scc];
  //      NSLog(@"trendline touch %ld %f, %f", i, touch.x, touch.y);
    }
    
    NSLog(@"\n");
    recognizer.cancelsTouchesInView =YES;
}

- (void)magnify:(UILongPressGestureRecognizer *)recognizer {
    
    if ([recognizer state] == UIGestureRecognizerStateBegan) {
        [self.scc resetPressedBar];
    }

    CGFloat xPress = [recognizer locationInView:self.view].x - 5. - self.scc.layer.position.x; // 5pts of left buffer for grip
    CGFloat yPress = [recognizer locationInView:self.view].y - 5. - self.toolbarHeight;      // 5 pts of top buffer
    
    NSLog(@"press at x %f, y %f", xPress, yPress);
    
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
        
        // Advantages of having SCC track the bar is that it can also tell whether the bar is a day or a month  based on the barUnit
        // from a news filtering perspective, the date range that matters may be what happened BEFORE the newer bar
                
        // To determine whether to show the menu, we need to
        // 1. call SCC to see if a bar was selected prior to lift-up, and if so what dates is corresponds to (consider weekly & monthly)
        // 2. for the newest bar, an intraday option should also be available which will open up a new window
        // 3. the arrow point may need to be set differently for a close chart than a candlestick, so let SCC handle that
        
        // Data that SCC will need to return:
        // CGPoint for arrow (can it adjust for scc.position.x)
        // period end date (which handles weekly and monthly) and allows intraday menu check
        // stock symbol, which I'll need for the news and SEC searches
        
        [self setInfoForPressedBar:[self.scc infoForPressedBar]];
       
        if (self.infoForPressedBar != nil) {
            
            [self becomeFirstResponder];       // must enable before UIMenuController -- note, call this on self NOT self.view
            NSMutableArray *menuItems = [NSMutableArray arrayWithCapacity:3];
            UIMenuController *menuController = [UIMenuController sharedMenuController];

            [menuItems addObject:[[[UIMenuItem alloc] initWithTitle: @"News" action:@selector( getNews: )] autorelease]];
            
            if ([[self.infoForPressedBar objectForKey:@"hasFundamentals"] isEqualToString:@"YES"]) {
                [menuItems addObject:[[[UIMenuItem alloc] initWithTitle: @"SEC Filings" action:@selector( getSECFilings: )] autorelease]];
            }
            
            NSDate *dateValue = [[(CIAppDelegate *)[[UIApplication sharedApplication] delegate] dateFormatter] dateFromString:[self.infoForPressedBar objectForKey:@"endDateString"]];
            
            if ([dateValue timeIntervalSinceNow] > -500000.) {
                 [menuItems addObject:[[[UIMenuItem alloc] initWithTitle: @"Intraday" action:@selector( getIntraday: )] autorelease]];                
            } 
            
            [menuController setMenuItems:menuItems];
            
            CGPoint location = [[self.infoForPressedBar objectForKey:@"arrowTip"] CGPointValue];

            [menuController setTargetRect:CGRectMake(location.x + self.scc.layer.position.x, location.y + self.toolbarHeight, 1., 1.) inView:self.view];
            [menuController setMenuVisible:YES animated:NO];
        }        
        [self.magnifier setHidden:YES];
    }
}

// Allows customizing the menu by limiting which menus are supported
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if ((action == @selector(getNews:)) || (action == @selector(getSECFilings:)) || (action == @selector(getIntraday:))) {
        return YES;
    }
    return NO;
}

/* To support an inline webview on the iPad, RVC must manage a UIWebView directly. 
 To avoid bugs caused by two different ways of doing things, it makes the most sense to have the iPhone version
 also use the same version.  
 
For consistency, the down hideWebview button can hide the webview even on the iPhone
For visual consistency, the webview can slide up and slide down on both the iPhone and iPad.  The only difference is whether there is room left for a chart.
The advantage of this approach is that it allows potentially showing a tiny chart at the top of the iPhone 5 in portrait mode.
 */

- (void) showWebview:(NSString *)url title:(NSString *)title {
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {

        // must animate the bounds http://developer.apple.com/library/mac/#qa/qa1620/_index.html
        // Prepare the animation from the old size to the new size
        CGRect oldBounds = self.scc.bounds;
        CGRect newBounds = oldBounds;
        newBounds.size = CGSizeMake(self.width, 288);   // iphone landscape chart size
        CABasicAnimation *boundsAnimation = [CABasicAnimation animationWithKeyPath:@"bounds"];
        
        boundsAnimation.fromValue = [NSValue valueWithCGRect:oldBounds];
        boundsAnimation.toValue = [NSValue valueWithCGRect:newBounds];
            
        CABasicAnimation *positionAnimation = [CABasicAnimation animationWithKeyPath:@"position"];
        positionAnimation.fromValue = [self.scc valueForKey:@"position"];
        
        CGPoint newPosition = self.scc.layer.position;
        newPosition = CGPointMake(0., newPosition.y);
        positionAnimation.toValue = [NSValue valueWithCGPoint:newPosition];
        
        CAAnimationGroup *animationGroup = [CAAnimationGroup animation];
        animationGroup.duration = 0.25;
        animationGroup.animations = @[boundsAnimation, positionAnimation];
        
        [self.scc.layer addAnimation:animationGroup forKey:@"positionAndBounds"];
        
        self.scc.layer.position = newPosition;       // Update layer position so it doesn't snap back when animation completes
        self.scc.bounds = newBounds;
        [self.scc.layer setAffineTransform:CGAffineTransformIdentity];
        self.scc->showDotGrips = NO;
        
        [self.scc resize];
        
        [self resetToolbarWithSearch:NO];

        [self.webView setFrame:CGRectMake(0, self.toolbarHeight + 288., self.width, self.height - 288. - self.toolbarHeight)];
        
    } else {
        
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0., 11., 200., 21.)];
        [titleLabel setFont:[UIFont fontWithName:@"Helvetica-Bold" size:18]];
        [titleLabel setBackgroundColor:[UIColor clearColor]];
        [titleLabel setTextColor:[UIColor lightGrayColor]];
        [titleLabel setText:title];
        [titleLabel setTextAlignment:NSTextAlignmentCenter];
        
        UIBarButtonItem *titleButton = [[UIBarButtonItem alloc] initWithCustomView:titleLabel];
        UIBarButtonItem *activityButton = [[UIBarButtonItem alloc] initWithCustomView:self.webViewDownloading];
        
        UIBarButtonItem *hideWebview = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"hideWebview"] style:UIBarButtonItemStylePlain target:self action:@selector(minimizeChart)];

        NSArray *buttons = [NSArray arrayWithObjects:hideWebview,
                            [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease],
                            titleButton,
                            [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease],
                            activityButton, nil];
        [titleLabel release];
        [activityButton release];
        
        [self.customNavigationToolbar setItems:buttons];
        [self.webViewDownloading startAnimating];
        [self.webView setFrame:CGRectMake(0, self.toolbarHeight, self.width, self.height - self.toolbarHeight)];
    }
    [self.webToolbar setFrame:CGRectMake(0, self.height, self.width, self.toolbarHeight)];
    [self.webToolbar setHidden:NO];
    
    NSURLRequest *requestObj = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    [self.webView loadRequest:requestObj];
    [self.webView setHidden:NO];
    [self.progressIndicator startAnimating];
}

- (void) getNews:(UIMenuController *)controller {
    	
    NSArray *startDate = [self.infoForPressedBar objectForKey:@"startDate"];
    NSArray *endDate = [self.infoForPressedBar objectForKey:@"endDate"];
    
    NSString *url = [NSString stringWithFormat:@"http://chartinsight.com/getNews.php?sym=%@&sy=%@&sm=%@&sd=%@&ey=%@&em=%@&ed=%@", [self.infoForPressedBar objectForKey:@"symbolEncoded"], [startDate objectAtIndex:0], [startDate objectAtIndex:1], [startDate objectAtIndex:2], [endDate objectAtIndex:0], [endDate objectAtIndex:1], [endDate objectAtIndex:2]];
    [self showWebview:url title:[NSString stringWithFormat:@"%@ News", [self.infoForPressedBar objectForKey:@"symbol"]]];
}

- (void) getSECFilings:(UIMenuController *) controller {
	
    NSArray *endDate = [self.infoForPressedBar objectForKey:@"endDate"];
    NSString *url = [NSString stringWithFormat:@"http://chartinsight.com/getSECFilings.php?sym=%@&ey=%@&em=%@&ed=%@", [self.infoForPressedBar objectForKey:@"symbolEncoded"], [endDate objectAtIndex:0], [endDate objectAtIndex:1], [endDate objectAtIndex:2]];
    
    // DLog(@"url is %@", url);
    [self showWebview:url title:[NSString stringWithFormat:@"%@ SEC Filings", [self.infoForPressedBar objectForKey:@"symbol"]]];
}

- (void) getIntraday:(UIMenuController *)controller {
    
    NSString *url = [NSString stringWithFormat:@"http://chartinsight.com/getIntraday.php?sym=%@", [self.infoForPressedBar objectForKey:@"symbolEncoded"]];
    [self showWebview:url title:[NSString stringWithFormat:@"%@ Intraday Chart", [self.infoForPressedBar objectForKey:@"symbol"]]];
}


- (void)doubleTap:(UITapGestureRecognizer *)recognizer {
    
    recognizer.cancelsTouchesInView = YES;
    
    CGFloat pinchMidpoint = [recognizer locationInView:self.view].x - self.scc.layer.position.x - 5;
    
    NSLog(@"pinchmidoint is %f vs scc position %f so pinchMidpoint is %f", [recognizer locationInView:self.view].x, self.scc.layer.position.x, pinchMidpoint);
    
    if (self.scc->xFactor > 10) {
        [self.scc resizeChartImage:0.5 withCenter:pinchMidpoint];
        [self.scc resizeChart:0.5];
    } else {
        [self.scc resizeChartImage:2.0 withCenter:pinchMidpoint];
        [self.scc resizeChart:2.0];
    }
}

/*
- (BOOL) gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if ([recognizer locationInView:self.view].x >= self.scc.layer.position.x ) {
        return YES;
    }
    return NO;
}
 */

- (void) handlePan:(UIPanGestureRecognizer *)recognizer {
    
    recognizer.cancelsTouchesInView = YES;
    
    CGFloat delta, currentShift;
    
    if (recognizer.state == UIGestureRecognizerStateCancelled) {
        self.lastShift = 0;
        return;    // enabled = NO causes another loop with the canceled state, so exit
        
    } else if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.lastShift = 0;
        
        if (self.webView.hidden) {
            self.dragWindow = [recognizer locationInView:self.view].x - self.scc.layer.position.x < 45.0 ? YES : NO;
            self.netDelta = 0;
        }
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
    if (_popover != nil) {
        [_popover dismissPopoverAnimated:YES];
        [_popover release];
        _popover = nil;
    } else {
        [[self navigationController] popViewControllerAnimated:YES];    // pop this controller off stack
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

// UIWebViewDelegate methods
- (BOOL)webView:(UIWebView *)wv shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)nt {

    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        [self.webViewDownloading startAnimating];
    }
    
   [self.webRefreshButton setEnabled:YES];
    
    // DLog(@"request is %@", [request URL]);
    
    return YES;
}

- (void) shareChart {
    
    NSString *textToShare =  @""; // Chart Insight";

    for (int i = 0; i < [self.scc.comparison.seriesList count]; i++) {
        
        Series *s = [self.scc.comparison.seriesList objectAtIndex:i];
        
        textToShare = [textToShare stringByAppendingFormat:@"%@ ", s.symbol];
    }

    textToShare = [textToShare stringByAppendingString:@"Chart Insight"];
    
    UIImage *imageToShare = [self.scc screenshot];
    
    if (imageToShare != nil) {
        
            MFMailComposeViewController *mailForm = [[[MFMailComposeViewController alloc] init] autorelease];
            mailForm.mailComposeDelegate = self;
            
            [mailForm setSubject:textToShare];
            
            NSData *imageData = [NSData dataWithData:UIImagePNGRepresentation(imageToShare)];
            [mailForm addAttachmentData:imageData mimeType:@"image/png" fileName:@"screenshot.png"];
            
            [self presentViewController:mailForm animated:YES completion:nil];     // don't use popoverPush; it prevents the magnify menu from appearing afterwards
            
        } else {
        
//            SupportActivityProvider *customProvider = [[SupportActivityProvider alloc] init];
//            NSArray *items = [NSArray arrayWithObjects:customProvider,textToShare,imageToShare,nil];
//            
//            SupportActivity *ca = [[SupportActivity alloc]init];
//            
//            UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:[NSArray arrayWithObject:ca]];
//            
//            activityVC.excludedActivityTypes = @[UIActivityTypePostToWeibo, UIActivityTypeAssignToContact, UIActivityTypeCopyToPasteboard, UIActivityTypeSaveToCameraRoll];
//            
//            [self popoverPush:activityVC createRVC:NO fromButton:self.shareChartButton];
//            
//            [self presentViewController:activityVC animated:YES completion:nil];     // don't use popoverPush; it prevents the magnify menu from appearing afterwards
//        }
    }
}

// Dismisses the message composition interface when users tap Cancel or Send
- (void)mailComposeController:(MFMailComposeViewController*)controller
          didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {
	
	switch (result) {
		case MFMailComposeResultCancelled:
			// DLog(@"Result: Mail sending canceled");
			break;
		case MFMailComposeResultSaved:
			// DLog(@"Result: Mail saved");
			break;
		case MFMailComposeResultSent:
			// DLog(@"Result: Mail sent");
			break;
		case MFMailComposeResultFailed:
			// DLog(@"Result: Mail sending failed");
			break;
		default:
			// DLog(@"Result: Mail not sent");
			break;
	}
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)webViewDidFinishLoad:(UIWebView *)wv {
    
 //   NSString *html = [wv stringByEvaluatingJavaScriptFromString:@"document.body.innerHTML"];
    
   // DLog(@"webview finished loading %@", html );
    
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        [self.webViewDownloading stopAnimating];
    }
    
    [self.progressIndicator stopAnimating];
    
    
    if ([self.webView canGoBack]) {
        [self.webBackButton setEnabled:YES];
    } else {
        [self.webBackButton setEnabled:NO];
    }
    
    if ([self.webView canGoForward]) {                  // this doesn't always work
        [self.webForwardButton setEnabled:YES];
    } else {
        [self.webForwardButton setEnabled:NO];
    }
}
- (void)webView:(UIWebView *)wv didFailLoadWithError:(NSError *)error {
    // DLog(@"webivew failed with error %@", error);
    [self.progressIndicator stopAnimating];
    if ([error code] != NSURLErrorCancelled) {     // user clicked a link before page finished loading

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

