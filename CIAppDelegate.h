//
//  CIAppDelegate.h
//  ChartInsight
//
//  Created by Eric Kennedy on 11/19/13.
//  Copyright (c) 2013 Chart Insight LLC. All rights reserved.
//

#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface CIAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (strong, nonatomic) NSArray<NSString *> *chartTypes;
@property (strong, nonatomic) NSMutableArray<NSString *> *colors;

- (nonnull NSArray *) metrics;

- (nullable NSString *) titleForKey:(nonnull NSString *)key;

- (nullable NSString *) descriptionForKey:(nonnull NSString *)key;

- (BOOL) nightBackground;

- (void)nightModeOn:(BOOL)on;

- (void)showFavoritesTab;

NS_ASSUME_NONNULL_END
@end
