#include <CoreGraphics/CGColor.h>
#include "ChartInsight-Swift.h"

@interface ChartOptionsController : UITableViewController <UIActionSheetDelegate>

@property (nonatomic, assign) id delegate;
@property (strong, nonatomic) Stock *stock;
@property (strong, nonatomic) NSCalendar *gregorian;
@property (strong, nonatomic) NSDateFormatter *dateFormatter;
@property (strong, nonatomic) NSArray *sparklineKeys;

- (void) addedFundamental:(NSString *)key;

@end
