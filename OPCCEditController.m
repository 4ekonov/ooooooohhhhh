#import "OPCCEditController.h"
#import "OPCCActions.h"

@implementation OPCCEditController {
    NSMutableArray *_active, *_available;
}
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.title = @"Edit buttons";
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    _active = [[OPCCActions activeIDs] mutableCopy];
    _available = [NSMutableArray array];
    for (NSString *i in [OPCCActions allIDs]) if (![_active containsObject:i]) [_available addObject:i];
    [self.tableView setEditing:YES animated:NO];
}
- (void)done { [OPCCActions saveActiveIDs:_active]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return s == 0 ? @"Shown (drag to reorder)" : @"Available"; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return s == 0 ? _active.count : _available.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSString *i = (p.section == 0 ? _active : _available)[p.row];
    c.textLabel.text = [[OPCCActions titleFor:i] stringByReplacingOccurrencesOfString:@" ▾" withString:@""];
    c.imageView.image = [UIImage systemImageNamed:[OPCCActions symbolFor:i]];
    c.imageView.tintColor = UIColor.whiteColor;
    c.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
    return c;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)t editingStyleForRowAtIndexPath:(NSIndexPath *)p {
    return p.section == 0 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleInsert;
}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)s forRowAtIndexPath:(NSIndexPath *)p {
    if (p.section == 0) { NSString *i = _active[p.row]; [_active removeObjectAtIndex:p.row]; [_available addObject:i]; }
    else { NSString *i = _available[p.row]; [_available removeObjectAtIndex:p.row]; [_active addObject:i]; }
    [t reloadData];
}
- (BOOL)tableView:(UITableView *)t canMoveRowAtIndexPath:(NSIndexPath *)p { return p.section == 0; }
- (NSIndexPath *)tableView:(UITableView *)t targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)a toProposedIndexPath:(NSIndexPath *)b {
    return b.section == 0 ? b : [NSIndexPath indexPathForRow:_active.count - 1 inSection:0];
}
- (void)tableView:(UITableView *)t moveRowAtIndexPath:(NSIndexPath *)a toIndexPath:(NSIndexPath *)b {
    NSString *i = _active[a.row]; [_active removeObjectAtIndex:a.row]; [_active insertObject:i atIndex:b.row];
}
@end
