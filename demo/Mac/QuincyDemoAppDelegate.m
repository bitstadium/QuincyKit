/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
 *
 * Copyright (c) 2011 Andreas Linde & Kent Sutherland. All rights reserved.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "QuincyDemoAppDelegate.h"

@implementation QuincyDemoAppDelegate

// set the main nibs window to hidden on startup
// this delegate method is required to be implemented!
- (void) showMainApplicationWindow {
	[window makeFirstResponder: nil];
	[window makeKeyAndOrderFront:nil];
}


- (void)applicationDidFinishLaunching:(NSNotification *)note {
  
  BWQuincyManager *quincy = [BWQuincyManager sharedQuincyManager];

  // see the BWQuincyManagerDelegate protocol
  [quincy setDelegate:self];
  
  // For use with hockeyapp.net
  [quincy setAppIdentifier:@"af6282c7fb17ccc8da69925bf0133057"];
  
  // For your own hosted server
  // [quincy setSubmissionURL:@"http://yourserver.com/crash_v200.php"];

  // company name will be shown to the user (if user interaction is configured)
  [quincy setCompanyName:@"serenity.de"];

  // TODO: UI options
  quincy.feedbackActivated = YES; 
}


- (void)bam {
	signal(SIGBUS, SIG_DFL);
	
	*(long*)0 = 0xDEADBEEF;
}


- (IBAction)doCrash:(id)sender {
	[self bam];
}

@end
