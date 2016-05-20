#import "FindSeriesController.h"
#import "Series.h"

@implementation FindSeriesController

- (void)dealloc {
    _delegate = nil;
    [super dealloc];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toOrientation duration:(NSTimeInterval)duration {
        
    [self.searchBar setFrame:CGRectMake(0., 0., self.tableView.bounds.size.width, 44.)];
}

- (BOOL)prefersStatusBarHidden {
    return (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone) ? YES: NO;
}

- (id)initWithStyle:(UITableViewStyle)style {

    self = [super initWithStyle:style];
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0., 0., self.tableView.bounds.size.width, 44.)];
    self.searchBar.delegate = self;
    
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.showsCancelButton   = NO;
    self.searchBar.barStyle = UIBarStyleBlack;
    [self.tableView setTableHeaderView:self.searchBar];
    [self setTitle:@"Company or Symbols"];

    [self setList:[NSMutableArray arrayWithCapacity:50]];
    return self;
}

-(void) viewWillAppear:(BOOL)animated {
    [self.searchBar becomeFirstResponder];
}

- (void) viewWillDisappear:(BOOL)animated {
    [self.searchBar resignFirstResponder];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
     return self.list.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
	static NSString *kCellID = @"cellID";
	
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kCellID] autorelease];
	}
    
	if ([self.list count] > indexPath.row) {
        
        NSString *label = @"";
        
        NSArray *matches = [self.list objectAtIndex:indexPath.row];
        
        for (NSInteger i= 0; i < matches.count; i++) {
            Series *s = [matches objectAtIndex:i];
            
            if (matches.count > 1) {    // multiple matches
                if (i < matches.count - 1) {
                    label = [label stringByAppendingFormat:@" %@, ", s.symbol]; 
                }
            }
            if (i == matches.count - 1) {
                label = [label stringByAppendingFormat:@"%@ - %@", s.symbol, s.name];                
            }
        }
        cell.textLabel.text = label;
		return cell;
	}
	return nil;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    
	if ([searchText length] > 1) {			
		//	Don't clear results -- let seriesFound do it when data is returned	

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{
            
            NSMutableArray *localList = [Series findSeries:searchText];
            if (localList != nil) {
                [self performSelectorOnMainThread:@selector(seriesFound:) withObject:localList waitUntilDone:YES];
            }
        });
	}	
}

- (void)seriesFound:(NSArray *)seriesList {    
    [seriesList retain];
    [self.list removeAllObjects];
    
	if ([seriesList count] > 0) {
		
        [self.list setArray:seriesList];
	} 
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {    
	
	if (self.list.count > indexPath.row) {
		 NSMutableArray *seriesList = [self.list objectAtIndex:indexPath.row];
            
        [seriesList retain];     // only thing retaining it so far is the list returned by FCC which will be released
                
        [[self delegate] performSelector:@selector(insertSeries:) withObject:seriesList];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;    
}


@end
