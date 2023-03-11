#import "Comparison.h"
#import "ProgressIndicator.h"

@interface RootViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (strong, nonatomic) NSCalendar *gregorian;
@property (nonatomic, strong) ProgressIndicator	*progressIndicator;
@property (nonatomic, strong) UIImageView                    *magnifier;        // AppDelegate will hide on suspend

- (void) reloadList:(Comparison *)comparison;

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

- (void) nightDayToggle;

@end



