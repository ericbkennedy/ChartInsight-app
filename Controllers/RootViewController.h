#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@class Comparison;
@class ProgressIndicator;
@class Stock; // forward declaration because this header is included in Bridging Header

@interface RootViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

NS_ASSUME_NONNULL_BEGIN

@property (nonatomic, strong) NSCalendar *gregorian;
@property (nonatomic, strong) ProgressIndicator	*progressIndicator;
@property (nonatomic, strong) UIImageView *magnifier;   // SceneDelegate will hide on suspend

// SettingsViewController will call reloadWhenVisible after a stock comparison is deleted
// so this controller can reload the tableView when the user switches back to this tab
- (void) reloadWhenVisible;

- (void) reloadWithStock:(Stock *)stock;

// called by ChartOptionsController when chart color or type changes
- (void) redrawWithStock:(Stock *)stock;

// remove the topmost iPhone UIViewController or iPad UIPopoverController
- (void) popContainer;

- (void) deleteStock:(NSInteger)sender;

/// Callback after async comparisonList reload
- (void) updateList:(NSArray <Comparison *>*)newList;

/// called by AddStockController when a new stock is added
- (void) insertStock:(Stock *)stock isNewComparison:(BOOL)isNewComparison;

NS_ASSUME_NONNULL_END
@end



