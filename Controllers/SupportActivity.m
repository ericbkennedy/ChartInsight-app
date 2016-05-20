#import "SupportActivity.h"

@implementation SupportActivityProvider
- (id)activityViewController:(UIActivityViewController *)activityViewController itemForActivityType:(NSString *)activityType {
    return [super activityViewController:activityViewController itemForActivityType:activityType];
}
@end


@implementation SupportActivity

- (NSString *) activityType {
    return @"chartInsight.contact.support";
}

- (NSString *) activityTitle {
    return @"Support";
}

- (UIImage *) activityImage {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return [UIImage imageNamed:@"iPadContactSupport"];      // 55pt square
    }
    return [UIImage imageNamed:@"iPhoneContactSupport"];    // 43pt square
}

- (BOOL) canPerformWithActivityItems:(NSArray *)activityItems {
    return YES;
}

// Called after the user has selected your service but before your service is asked to perform its action. Store a reference to the data items in the activityItems parameter.
- (void)prepareWithActivityItems:(NSArray *)activityItems {

    if (activityItems != nil) {
        [self setItemsToShare:activityItems];
    }
}

// Returns a view controller to present to the user. We don't need to present it ourselves
- (UIViewController *)activityViewController {    
    
    [self setMailForm: [[[MFMailComposeViewController alloc] init] autorelease]];
	self.mailForm.mailComposeDelegate = self;
	
	[self.mailForm setSubject:@"Chart Insight Support Request"];
	[self.mailForm setToRecipients:@[@"support@chartinsight.com"]];
	
    NSString *emailBody = @"\n \n ";
    
    for (NSObject *obj in self.itemsToShare) {
        
        if ([obj isKindOfClass:NSClassFromString(@"NSString")]) {
            emailBody = [emailBody stringByAppendingString:(NSString *)obj];
        } else if ([obj isKindOfClass:NSClassFromString(@"UIImage")]) {

            //Convert the image into data
            NSData *imageData = [NSData dataWithData:UIImagePNGRepresentation((UIImage *) obj)];
            [self.mailForm addAttachmentData:imageData mimeType:@"image/png" fileName:@"screenshot.png"];
        }
    }
    
    emailBody = [emailBody stringByAppendingString:@"\n \n == Support Info \nDevice: "];
        
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        emailBody = [emailBody stringByAppendingString:@"iPad"];
    } else {
        emailBody = [emailBody stringByAppendingString:@"iPhone"];
    }
    
    if (UIScreen.mainScreen.scale > 1.) {
        emailBody = [emailBody stringByAppendingString:@" retina"];
    }
    
    emailBody = [emailBody stringByAppendingFormat:@"\n iOS %@", [[UIDevice currentDevice] systemVersion]];
    emailBody = [emailBody stringByAppendingFormat:@"\n Chart Insight %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
    
	[self.mailForm setMessageBody:emailBody isHTML:NO];
    return self.mailForm;
}


// Dismisses the message composition interface when users tap Cancel or Send. Proceeds to update the
// feedback message field with the result of the operation.
- (void)mailComposeController:(MFMailComposeViewController*)controller
          didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {
	
  	[self.mailForm dismissViewControllerAnimated:YES completion:nil];
	[self activityDidFinish:YES];
}

@end