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

/// Non-alphabetical order of metrics achieved with array of categories which contains array of metric details
@property (strong, nonatomic) NSArray <NSArray <NSArray <NSString *> *> *> *metrics;

- (nullable NSString *) titleForKey:(nonnull NSString *)key;

- (nullable NSString *) descriptionForKey:(nonnull NSString *)key;

- (BOOL) nightBackground;

- (void)nightModeOn:(BOOL)on;

- (void)showFavoritesTab;

NS_ASSUME_NONNULL_END
@end
