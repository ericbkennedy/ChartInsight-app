#import "Comparison.h"
#import "ProgressIndicator.h"

@interface RootViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

NS_ASSUME_NONNULL_BEGIN

@property (nonatomic, strong) NSCalendar *gregorian;
@property (nonatomic, strong) ProgressIndicator	*progressIndicator;
@property (nonatomic, strong) UIImageView *magnifier;   // CIAppDelegate will hide on suspend

// SettingsViewController will call reloadWhenVisible after a stock comparison is deleted
// so this controller can reload the tableView when the user switches back to this tab
- (void) reloadWhenVisible;

- (void) reloadWithSeries:(Series *)series;

// called by ChartOptionsController when chart color or type changes
- (void) redrawWithSeries:(Series *)series;

// remove the topmost iPhone UIViewController or iPad UIPopoverController
- (void) popContainer;

- (void) deleteSeries:(NSInteger)sender;

// callback after the db is moved from the bundle or upgraded
- (void) dbMoved:(NSString *)newPath;

// called by FindSeriesController when a new stock is added
- (void) insertSeries:(NSMutableArray *)newSeriesList;

NS_ASSUME_NONNULL_END
@end



