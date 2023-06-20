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
@property (strong, nonatomic) UITabBarController *tabBarController;
@property (strong, nonatomic) UINavigationController *favoritesNavigationController;
@property (strong, nonatomic) UINavigationController *settingsNavigationController;
@property (strong, nonatomic) RootViewController *favoritesViewController;
@end

@implementation CIAppDelegate

- (void)nightModeOn:(BOOL)on
{
    if (on) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"nightBackground"];
    } else {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"nightBackground"];
    }
    
    // Override system light or dark setting based on nightModeOn toggle
        _window.overrideUserInterfaceStyle = on ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        self.tabBarController.tabBar.backgroundColor = UIColor.systemBackgroundColor;
        self.window.backgroundColor = UIColor.systemBackgroundColor;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [self setWindow:[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]]];

    self.tabBarController = [[UITabBarController alloc] init];
    
    self.favoritesViewController = [[RootViewController alloc] init];

    self.favoritesNavigationController = [[UINavigationController alloc] initWithRootViewController:self.favoritesViewController];
    self.favoritesNavigationController.title = @"Watchlist";
    
    SettingsViewController *settingsViewController = [[SettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    settingsViewController.delegate = self.favoritesViewController; // Reload list of stocks after one is deleted (but not on viewDidAppear)
    
    self.settingsNavigationController = [[UINavigationController alloc] initWithRootViewController:settingsViewController];
    self.settingsNavigationController.title = @"Settings";
    
    self.tabBarController.viewControllers = @[self.favoritesNavigationController, self.settingsNavigationController];
    
    self.window.rootViewController = self.tabBarController;

    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"nightBackground"] == YES) {
        [self nightModeOn:YES];
    } else {
        [self nightModeOn:NO];
    }
   
    [self setMetrics:[NSMutableArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"metrics.plist" ofType:nil]]];
    
    [self setMetricKeys:[NSMutableDictionary new]];
    
    for (NSArray *category in self.metrics) {
        for (NSArray *type in category) {
            [self.metricKeys setObject:type forKey:[type objectAtIndex:0]];
        }
    }
    
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL) nightBackground {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"nightBackground"] == YES) {
        return YES;
    }
    return NO;
}

- (void) showFavoritesTab {
    self.tabBarController.selectedIndex = 0;
}

- (nullable NSString *) titleForKey:(NSString *)key {
    
    NSArray *item = [self.metricKeys objectForKey:key];    
    if (item != nil) {
        return [item objectAtIndex:1];
    }
    return nil;
}

- (nullable NSString *) descriptionForKey:(NSString *)key {
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
