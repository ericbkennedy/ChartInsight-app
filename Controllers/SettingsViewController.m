//
//  SettingsViewController.m
//  ChartInsight
//
//  Created by Eric Kennedy on 5/15/16.
//  Copyright © 2016 Chart Insight LLC. All rights reserved.
//

#import "CIAppDelegate.h"
#import "Comparison.h"
#import "RootViewController.h"
#import "SettingsViewController.h"

enum sectionType { NIGHT_MODE_SECTION, STOCK_LIST_SECTION };

@interface SettingsViewController ()
@property (strong, nonatomic) NSMutableArray *list;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title  = @"Settings";

    NSString *dbPath = [NSString stringWithFormat:@"%@/Documents/charts.db", NSHomeDirectory()];

    [self setList:[Comparison listAll:dbPath]];

    self.view.backgroundColor = [(CIAppDelegate *)UIApplication.sharedApplication.delegate chartBackground];
    self.tableView.editing = YES;

    UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismiss)];
 
     self.navigationItem.rightBarButtonItem = barButtonItem;
}

- (void)dismiss {        
    [(CIAppDelegate *)UIApplication.sharedApplication.delegate showFavoritesTab];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (void)toggleNightDay {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"nightBackground"] == YES) {
        // user wants day/light mode
        [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightModeOn:NO];
    } else {
        [(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightModeOn:YES];
    }
    
    self.view.backgroundColor = [(CIAppDelegate *)UIApplication.sharedApplication.delegate tableViewBackground];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == NIGHT_MODE_SECTION) {
        if (@available(iOS 13, *)) {
            return 1;
        } else {
            return 0;
        }
    }
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
    
    if (indexPath.section == NIGHT_MODE_SECTION) {
        
        cell.textLabel.text = @"Night mode";
        
        UISwitch *onOff = [UISwitch new];
        [onOff addTarget:self action:@selector(toggleNightDay) forControlEvents:UIControlEventTouchUpInside];
        [cell setAccessoryView:onOff];
        
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"nightBackground"] == YES) {
            onOff.on = TRUE;
        } else {
            onOff.on = FALSE;
        }
        
    } else {
        Comparison *comparison = [self.list objectAtIndex:indexPath.row];
     
        cell.textLabel.text = [comparison title];
        cell.textLabel.font = [UIFont systemFontOfSize:13];
    }
    
    if ([(CIAppDelegate *)[[UIApplication sharedApplication] delegate] nightBackground] != NO) {
        cell.textLabel.textColor = [UIColor lightGrayColor];
    } else {
        cell.textLabel.textColor = [UIColor colorWithRed:.490 green:.479 blue:0.432 alpha:1.0];
    }
    
    return cell;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == STOCK_LIST_SECTION ? YES : NO;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == STOCK_LIST_SECTION && editingStyle == UITableViewCellEditingStyleDelete) {

        Comparison *comparison = self.list[indexPath.row];

        [comparison deleteFromDb];

        [self.list removeObjectAtIndex:indexPath.row];
        
        [(RootViewController *)self.delegate reloadList:nil];
        
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}

// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == STOCK_LIST_SECTION) {
        return YES;
    } else {
        return NO;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == STOCK_LIST_SECTION) {
        return @"Watchlist stocks";
    }
    return @"";
}

@end
