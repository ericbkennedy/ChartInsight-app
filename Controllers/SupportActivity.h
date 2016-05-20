#import <MessageUI/MFMailComposeViewController.h>

@interface SupportActivityProvider : UIActivityItemProvider

@end

@interface SupportActivity : UIActivity <MFMailComposeViewControllerDelegate>

@property (nonatomic, strong) NSArray *itemsToShare;
@property (nonatomic, strong) MFMailComposeViewController *mailForm;

@end