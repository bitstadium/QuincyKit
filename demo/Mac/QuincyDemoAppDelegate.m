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

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  
  // ====================
  // = Integrate Quincy =
  // ====================
  BWQuincyManager *quincy = [BWQuincyManager sharedQuincyManager];

  // see the BWQuincyManagerDelegate protocol
  [quincy setDelegate:self];
  
  // Company name that will be shown to the user (if user interaction is enabled)
  [quincy setCompanyName:@"ACME Inc."];

  // calling - setAppIdentifier: or - setSubmissionURL: will start the Quincy manager
  // For use with hockeyapp.net
  [quincy setAppIdentifier:@"af6282c7fb17ccc8da69925bf0133057"];
  
  // For your own hosted server use:
  // [quincy setSubmissionURL:@"http://yourserver.com/crash_v200.php"];

  // quincy.networkTimeoutInterval = 15.0; // = default 15.0


  // ==============
  // = UI options =
  // ==============
  
  // provide your own UI by setting this delegate, otherwise the default UI will be used
  // quincy.interfaceDelegate = self;
  
  // Quincy allows to tell the user if a bug is already fixed after the user sent in a crash report. Default is NO
  // quincy.feedbackActivated = YES;

  // if server feedback is activated specify the maximum time after sending the crashreport when the feedback will be fetched. So as to not show a message to the user more than X seconds after he sent the crash report. The server may tell the client to collect the feedback only after a certain amount of time, because it might be busy queueing a lot of crash reports
  // quincy.maxFeedbackDelay = 10.0; // = default 10.0
  
  // if you tell Quincy to show a modal UI, make sure to make your main window key in - didFinishCrashReporting:, default is YES
  // quincy.shouldPresentModalInterface = NO;

  [window makeFirstResponder:nil];
  [window makeKeyAndOrderFront:nil];
}


#pragma mark -
#pragma mark BWQuincyManagerDelegate

// this delegate method will be called when Quincy is done with its work
- (void)didFinishCrashReporting:(BWQuincyStatus)status
{
  // make sure your main window is showing
  [window makeFirstResponder:nil];
  [window makeKeyAndOrderFront:nil];
}

// Return the userid the crashreport should contain, empty by default
//- (NSString *)crashReportUserID
//{
//  // if you need to identify users, otherwise just don't implement this method
//  return @"my user id";
//}

// Return the contact value (e.g. email) the crashreport should contain, empty by default
//- (NSString *)crashReportContact
//{
//  // if you need to contact users, otherwise just don't implement this method
//  return @"username@example.com";
//}

// Invoked when the internet connection is started, e.g. to show an activity indicator
//- (void)connectionOpened
//{
//}

// Invoked when the internet connection is closed, e.g. to hide an activity indicator
//- (void)connectionClosed
//{
//}


#pragma mark -
#pragma mark BWQuincyUIDelegate

// You only need this if you want to present your own UI

- (void)presentQuincyCrashSubmitInterfaceWithCrash:(NSString *)crashFileContent
                                           console:(NSString *)consoleContent
{
  // This example does not present a UI, but just sends the crash report.
  
  // Usually here would be the place to present your own UI to inform the user about sending the crash report, or just asking the user if he/she is OK sending crash data 
  BWQuincyManager *quincy = [BWQuincyManager sharedQuincyManager];
  [quincy sendReportWithComment:nil];
}

- (void)presentQuincyServerFeedbackInterface:(CrashReportStatus)status
{
  
}


#pragma mark -
#pragma mark Crash demo

- (void)bam {
	signal(SIGBUS, SIG_DFL);
	
	*(long*)0 = 0xDEADBEEF;
}


- (IBAction)doCrash:(id)sender {
	[self bam];
}

@end
