
#import "BWQuincyUI.h"

@interface BWQuincyUI(private)
- (void) askCrashReportDetails;
- (void) endCrashReporter;
@end

@implementation BWQuincyUI

const CGFloat kCommentsHeight = 105;
const CGFloat kDetailsHeight = 285;

@synthesize delegate=delegate_, companyName, applicationName, crashFileContent, consoleContent;

- (id)init:(id)delegate
{
	self = [super initWithWindowNibName:@"BWQuincyMain"];
	
	if (self != nil) {
		delegate_ = delegate;
		[self setShowComments: YES];
		[self setShowDetails: NO];
	}
	return self;
}


- (void) endCrashReporter {
	[[self window] close];
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
	[self endCrashReporter];
  
	if ([delegate_ respondsToSelector:@selector(cancelReport)])
		[delegate_ performSelector:@selector(cancelReport)];
	
	[NSApp abortModal];
}


- (IBAction) submitReport:(id)sender {
	[submitButton setEnabled:NO];
	[[self window] makeFirstResponder:nil];
	
  NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                        @"", @"userid",
                        @"", @"contact",
                        [descriptionTextField stringValue], @"comment",
                        nil];
	
	if ([delegate_ respondsToSelector:@selector(sendReport:)])
		[delegate_ performSelector:@selector(sendReport:) withObject:info];
  
	[self endCrashReporter];
	[NSApp abortModal];
}


- (void)presentInterface
{
	[[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Problem Report for %@", @"Window title"), self.applicationName]];
  
	[[descriptionTextField cell] setPlaceholderString:NSLocalizedString(@"Please describe any steps needed to trigger the problem", @"User description placeholder")];
	[noteText setStringValue:NSLocalizedString(@"No personal information will be sent with this report.", @"Note text")];
  
  [crashLogTextView setString:[NSString stringWithFormat:@"%@\n\n%@", self.crashFileContent, self.consoleContent]];
	[NSApp runModalForWindow:self.window];
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
