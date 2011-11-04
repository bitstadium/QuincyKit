/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
 *         Stanley Rost
 *
 * Copyright (c) 2011 Andreas Linde & Kent Sutherland.
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

#import "BWQuincyUI.h"

@interface BWQuincyUI(private)
- (void)dismissUI;
@end

@implementation BWQuincyUI

const CGFloat kCommentsHeight = 105;
const CGFloat kDetailsHeight = 285;

@synthesize delegate=delegate_, companyName = companyName_, applicationName = applicationName_, shouldPresentModal = shouldPresentModal_;

- (id)init
{
  self = [super initWithWindowNibName:@"BWQuincyMain"];
  
  if (self != nil)
  {
    [self setShowComments:YES];
    [self setShowDetails:NO];
    
    self.shouldPresentModal = YES;
    
    NSString *bundleName = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleName"];
    self.applicationName = bundleName ?: [[NSProcessInfo processInfo] processName];
  }
  return self;
}


- (void)dismissUI
{
  [self close];
  [NSApp stopModal];
}


- (IBAction)showComments:(id)sender
{
  NSRect windowFrame = [[self window] frame];
  
  if ([sender intValue])
  {
    [self setShowComments: NO];
    
    windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height + kCommentsHeight);
    windowFrame.origin.y -= kCommentsHeight;
    [[self window] setFrame:windowFrame
                    display:YES
                    animate:YES];
    
    [self setShowComments: YES];
  }
  else
  {
    [self setShowComments: NO];
    
    windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height - kCommentsHeight);
    windowFrame.origin.y += kCommentsHeight;
    [[self window] setFrame: windowFrame
                    display: YES
                    animate: YES];
  }
}


- (IBAction)showDetails:(id)sender
{
  NSRect windowFrame = [[self window] frame];
  
  windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height + kDetailsHeight);
  windowFrame.origin.y -= kDetailsHeight;
  [[self window] setFrame: windowFrame
                  display: YES
                  animate: YES];
  
  [self setShowDetails:YES];
  
}


- (IBAction)hideDetails:(id)sender
{
  NSRect windowFrame = [[self window] frame];
  
  [self setShowDetails:NO];
  
  windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height - kDetailsHeight);
  windowFrame.origin.y += kDetailsHeight;
  [[self window] setFrame: windowFrame
                  display: YES
                  animate: YES];
}


- (IBAction)cancelReport:(id)sender
{
  [self dismissUI];
  
  if ([delegate_ respondsToSelector:@selector(cancelReport)])
    [delegate_ performSelector:@selector(cancelReport)];
}


- (IBAction)submitReport:(id)sender
{
  [self dismissUI];
  NSString *comment = [descriptionTextField stringValue];
  
  if ([delegate_ respondsToSelector:@selector(sendReportWithComment:)])
    [delegate_ performSelector:@selector(sendReportWithComment:) withObject:comment];
}

- (void)presentQuincyCrashSubmitInterfaceWithCrash:(NSString *)crashFileContent
                                           console:(NSString *)consoleContent
{
  [[self window] setTitle:[NSString stringWithFormat:BWQuincyLocalize(@"Problem Report for %@"), self.applicationName]];
  
  [[descriptionTextField cell] setPlaceholderString:BWQuincyLocalize(@"Please describe any steps needed to trigger the problem")];
  [noteText setStringValue:BWQuincyLocalize(@"No personal information will be sent with this report.")];
  
  [crashLogTextView setString:[NSString stringWithFormat:@"%@\n\n%@", crashFileContent, consoleContent]];
  
  if (self.shouldPresentModal)
    [NSApp runModalForWindow:self.window];
  else
    [self.window makeKeyAndOrderFront:nil];
}

- (void)presentQuincyServerFeedbackInterface:(CrashReportStatus)status
{
  NSString *messageTitle = [NSString stringWithFormat:BWQuincyLocalize(@"CrashResponseTitle"), self.applicationName];
  NSString *defaultButtonTitle = BWQuincyLocalize(@"OK");;
  NSString *alternateButtonTitle = nil;
  NSString *otherButtonTitle = nil;
  NSString *informativeText = nil;
  
  switch (status)
  {
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


- (BOOL)showComments
{
  return showComments;
}


- (void)setShowComments:(BOOL)value
{
  showComments = value;
}


- (BOOL)showDetails
{
  return showDetails;
}


- (void)setShowDetails:(BOOL)value
{
  showDetails = value;
}

@end
