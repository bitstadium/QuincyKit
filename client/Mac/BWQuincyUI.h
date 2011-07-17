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

#import "BWQuincyUIDelegate.h"

#define BWQuincyLocalize(StringToken) NSLocalizedStringFromTable(StringToken, @"Quincy", @"")

@interface BWQuincyUI : NSWindowController <BWQuincyUIDelegate>
{
  IBOutlet NSTextField *descriptionTextField;
  IBOutlet NSTextView *crashLogTextView;
  
  IBOutlet NSTextField *noteText;
  
  IBOutlet NSButton *showButton;
  IBOutlet NSButton *hideButton;
  IBOutlet NSButton *cancelButton;
  IBOutlet NSButton *submitButton;
  
  id delegate_;
  
  BOOL showComments;
  BOOL showDetails;
  
  NSString *companyName_;
  NSString *applicationName_;
  BOOL shouldPresentModal_;
}

- (IBAction)cancelReport:(id)sender;
- (IBAction)submitReport:(id)sender;
- (IBAction)showDetails:(id)sender;
- (IBAction)hideDetails:(id)sender;
- (IBAction)showComments:(id)sender;

- (BOOL)showComments;
- (void)setShowComments:(BOOL)value;

- (BOOL)showDetails;
- (void)setShowDetails:(BOOL)value;

@property (nonatomic, assign) id delegate;
@property (nonatomic, retain) NSString *companyName;
@property (nonatomic, retain) NSString *applicationName;
@property (nonatomic, assign) BOOL shouldPresentModal;

@end