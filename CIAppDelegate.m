//
//  CIAppDelegate.m
//  ChartInsight
//
//  Created by Eric Kennedy 
//  Copyright (c) 2013 Chart Insight LLC. All rights reserved.

#import "CIAppDelegate.h"
#import "RootViewController.h"
#import "SettingsViewController.h"

@interface CIAppDelegate ()
@property (strong, nonatomic) NSMutableArray *metrics;
@property (strong, nonatomic) NSMutableDictionary *metricKeys;
@property (strong, nonatomic) RootViewController *favoritesViewController;
@end

@implementation CIAppDelegate

- (void)dealloc {
    [_window release];
    [super dealloc];
}

- (void)nightModeOn:(BOOL)on
{
    if (on) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"nightBackground"];
        [[[self navigationController] navigationBar] setBarStyle:UIBarStyleBlack];
        [[[self navigationController] navigationBar] setTranslucent:NO];
        self.chartBackground = [UIColor blackColor];
        self.tableViewBackground = [UIColor colorWithWhite:0.1 alpha:1.0];
    } else {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"nightBackground"];
        [[[self navigationController] navigationBar] setBarStyle:UIBarStyleDefault];
        [[[self navigationController] navigationBar] setTranslucent:NO];
        self.chartBackground = [UIColor colorWithWhite:0.964705882 alpha:1.0];
        self.tableViewBackground = [UIColor colorWithRed:0.870588235 green:0.901960784 blue:0.968627451 alpha:1.0];
    }
    
    if (@available(iOS 13, *)) {    // Override system light or dark setting based on nightModeOn toggle
        _window.overrideUserInterfaceStyle = on ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    }
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [self setWindow:[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]]];

    self.favoritesViewController = [[RootViewController alloc] init];

    [self setNavigationController:[[UINavigationController alloc] initWithRootViewController:self.favoritesViewController]];
    [self.window setRootViewController:self.navigationController];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"nightBackground"] == 1) {
        [self nightModeOn:YES];
    } else {
        [self nightModeOn:NO];
    }
    
    [self setChartTypes:@[@"OHLC", @"HLC", @"Candle", @"Close"]];
    
    NSMutableArray *colorList =[NSMutableArray arrayWithCapacity:20];
    [colorList addObject: [UIColor colorWithRed:0. green:.6 blue:.0 alpha:1.0]];    // green (implies red)
    [colorList addObject: [UIColor colorWithRed:.0 green:.6 blue:1. alpha:1.0]];    // light blue
    [colorList addObject: [UIColor colorWithRed:.8 green:.6 blue:1. alpha:1.0]];    // light purple
    [colorList addObject: [UIColor colorWithRed:.6 green:.6 blue:.6 alpha:1.0]];    // pure white
    [colorList addObject: [UIColor colorWithRed:1. green:.8 blue:.0 alpha:1.0]];    // ripe lemon
    [colorList addObject: [UIColor colorWithRed:1. green:.6 blue:.0 alpha:1.0]];    // orange
    
    [self setColors:colorList];
    
    [self setDateFormatter:[[NSDateFormatter alloc] init]];
    self.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]; // 1996-12-19T16:39:57-08:00
    [self.dateFormatter setLocale: self.locale];  // override user locale
    [self.dateFormatter setDateFormat:@"yyyyMMdd'T'HH':'mm':'ss'Z'"];  // Z means UTC time
    [self.dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
   
    [self setMetrics:[NSMutableArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"metrics.plist" ofType:nil]]];
    
    [self setMetricKeys:[NSMutableDictionary new]];
    
    for (NSArray *category in self.metrics) {
        for (NSArray *type in category) {
            [self.metricKeys setObject:type forKey:[type objectAtIndex:0]];
        }
    }
    
    self.window.backgroundColor = [self chartBackground];
    
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL) nightBackground {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"nightBackground"] == 1) {
        return YES;
    }
    return NO;
}

- (NSString *) titleForKey:(NSString *)key {
    
    NSArray *item = [self.metricKeys objectForKey:key];    
    if (item != nil) {
        return [item objectAtIndex:1];
    }
    return nil;
}

- (NSString *) descriptionForKey:(NSString *)key {
    NSArray *item = [self.metricKeys objectForKey:key];    
    if (item != nil) {
        return [item objectAtIndex:2];
    }
    return nil;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    
    double feedbackDate = [[NSUserDefaults standardUserDefaults] doubleForKey:@"feedbackDate"];
    
    if (feedbackDate < 372796000) {     // reset if before Oct 24 DLog(@"time since ref date %f", [[NSDate date] timeIntervalSinceReferenceDate]);
        [[NSUserDefaults standardUserDefaults] setDouble:1.0 forKey:@"feedbackDate"];
    }
    
    [[self.favoritesViewController magnifier] setHidden:YES];       // avoid a bug where long press isn't canceled on entering background
    [[[self.favoritesViewController progressIndicator] timer] invalidate];
    
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
