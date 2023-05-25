//
//  CIAppDelegate.h
//  ChartInsight
//
//  Created by Eric Kennedy on 11/19/13.
//  Copyright (c) 2013 Chart Insight LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface CIAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (strong, nonatomic) NSArray *chartTypes;
@property (strong, nonatomic) NSMutableArray *colors;

- (NSArray *) metrics;

- (NSString *) titleForKey:(NSString *)key;

- (NSString *) descriptionForKey:(NSString *)key;

- (BOOL) nightBackground;

- (void)nightModeOn:(BOOL)on;

- (void)showFavoritesTab;

@end
