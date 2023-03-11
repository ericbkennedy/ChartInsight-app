
@interface FindSeriesController : UITableViewController <UISearchBarDelegate>

@property (strong, nonatomic) UISearchBar *searchBar;
@property (nonatomic, assign) id delegate;

@property (strong, nonatomic) NSMutableArray *list;

@end
