
@interface FindSeriesController : UITableViewController <UISearchBarDelegate>


// setting the first responder view of the table but we don't know its type (cell/header/footer)

// @property (strong, nonatomic) UITableView *tableView;   // add as property instead of setting view type
@property (strong, nonatomic) UISearchBar *searchBar;
@property (nonatomic, assign) id delegate;

@property (strong, nonatomic) NSMutableArray *list;

@end
