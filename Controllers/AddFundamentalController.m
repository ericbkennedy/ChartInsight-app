#import "AddFundamentalController.h"
#import "ChartOptionsController.h"

@implementation AddFundamentalController

- (void)viewDidLoad {
    [super viewDidLoad];
        
    self.tableView.delegate = self;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self.metrics count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [[self.metrics objectAtIndex:section] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    
    switch (section) {
        case 0:
            return @"Ratios";
        case 1:
            return @"Balance Sheet";
        case 2:
            return @"Income Statement";
        case 3:
            return @"Cash Flow";
        default:
            return @"";
    }
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 70;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier] autorelease];
    }
    
    NSArray *item = [[self.metrics objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];
    
    cell.textLabel.text = [item objectAtIndex:1];
    cell.detailTextLabel.text = [item objectAtIndex:2];
    cell.detailTextLabel.numberOfLines  = 2;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;

    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
        
    NSArray *item = [[self.metrics objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];
    
    [[self navigationController] popViewControllerAnimated:NO];
    
    [self.delegate performSelector:@selector(addedFundamental:) withObject:[item objectAtIndex:0]];
}

@end
