
#import "BWQuincyUI.h"

@interface BWQuincyUI(private)
- (void)dismissUI;
@end

@implementation BWQuincyUI

const CGFloat kCommentsHeight = 105;
const CGFloat kDetailsHeight = 285;

@synthesize delegate=delegate_, companyName, applicationName, crashFileContent, consoleContent;

- (id)init
{
	self = [super initWithWindowNibName:@"BWQuincyMain"];
	
	if (self != nil)
  {
		[self setShowComments:YES];
		[self setShowDetails:NO];
	}
	return self;
}


- (void)dismissUI
{
	[[self window] close];
	[NSApp abortModal];
}


- (IBAction) showComments: (id) sender {
	NSRect windowFrame = [[self window] frame];
	
	if ([sender intValue]) {
		[self setShowComments: NO];
		
		windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height + kCommentsHeight);
    windowFrame.origin.y -= kCommentsHeight;
		[[self window] setFrame: windowFrame
                    display: YES
                    animate: YES];
		
		[self setShowComments: YES];
	} else {
		[self setShowComments: NO];
		
		windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height - kCommentsHeight);
    windowFrame.origin.y += kCommentsHeight;
		[[self window] setFrame: windowFrame
                    display: YES
                    animate: YES];
	}
}


- (IBAction) showDetails:(id)sender {
	NSRect windowFrame = [[self window] frame];
  
	windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height + kDetailsHeight);
  windowFrame.origin.y -= kDetailsHeight;
	[[self window] setFrame: windowFrame
                  display: YES
                  animate: YES];
	
	[self setShowDetails:YES];
  
}


- (IBAction) hideDetails:(id)sender {
	NSRect windowFrame = [[self window] frame];
  
	[self setShowDetails:NO];
  
	windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height - kDetailsHeight);
  windowFrame.origin.y += kDetailsHeight;
	[[self window] setFrame: windowFrame
                  display: YES
                  animate: YES];
}


- (IBAction) cancelReport:(id)sender {
	[self dismissUI];
  
	if ([delegate_ respondsToSelector:@selector(cancelReport)])
		[delegate_ performSelector:@selector(cancelReport)];
}


- (IBAction) submitReport:(id)sender
{
	[self dismissUI];
	NSString *comment = [descriptionTextField stringValue];
  
	if ([delegate_ respondsToSelector:@selector(sendReportWithComment:)])
		[delegate_ performSelector:@selector(sendReportWithComment:) withObject:comment];
}


- (void)presentUserFeedbackInterface
{
	[[self window] setTitle:[NSString stringWithFormat:BWQuincyLocalize(@"Problem Report for %@"), self.applicationName]];
  
	[[descriptionTextField cell] setPlaceholderString:BWQuincyLocalize(@"Please describe any steps needed to trigger the problem")];
	[noteText setStringValue:BWQuincyLocalize(@"No personal information will be sent with this report.")];
  
  [crashLogTextView setString:[NSString stringWithFormat:@"%@\n\n%@", self.crashFileContent, self.consoleContent]];
	[NSApp runModalForWindow:self.window];
}

- (void)presentServerFeedbackInterface:(CrashReportStatus)status
{
  NSString *messageTitle = [NSString stringWithFormat:BWQuincyLocalize(@"CrashResponseTitle"), self.applicationName];
  NSString *defaultButtonTitle = BWQuincyLocalize(@"OK");;
  NSString *alternateButtonTitle = nil;
  NSString *otherButtonTitle = nil;
  NSString *informativeText = nil;
  
  switch (status) {
    case CrashReportStatusAssigned:
      informativeText = [NSString stringWithFormat:BWQuincyLocalize(@"CrashResponseNextRelease"), self.applicationName];
      break;
    case CrashReportStatusSubmitted:
      informativeText = [NSString stringWithFormat:BWQuincyLocalize(@"CrashResponseWaitingApple"), self.applicationName];
      break;
    case CrashReportStatusAvailable:
      informativeText = [NSString stringWithFormat:BWQuincyLocalize(@"CrashResponseAvailable"), self.applicationName];
      break;
    default:
      break;
  }
  
  if (informativeText)
  {
    NSAlert *alert = [NSAlert alertWithMessageText:messageTitle
                                     defaultButton:defaultButtonTitle
                                   alternateButton:alternateButtonTitle
                                       otherButton:otherButtonTitle
                         informativeTextWithFormat:informativeText];
    //alert.tag = QuincyKitAlertTypeFeedback;
    [alert runModal];
  }
}

- (void)dealloc
{
  self.companyName = nil;
  self.applicationName = nil;
  self.delegate = nil;

  [super dealloc];
}


- (BOOL)showComments {
	return showComments;
}


- (void)setShowComments:(BOOL)value {
	showComments = value;
}


- (BOOL)showDetails {
	return showDetails;
}


- (void)setShowDetails:(BOOL)value {
	showDetails = value;
}

@end
