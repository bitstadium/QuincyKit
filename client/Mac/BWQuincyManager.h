/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
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

#import <Cocoa/Cocoa.h>
#import <AvailabilityMacros.h>

#import "BWQuincyServerAPI.h"

#define CRASHREPORTSENDER_MAX_CONSOLE_SIZE 50000

// TODO #define BWQuincyLocalize(StringToken) NSLocalizedStringFromTableInBundle(StringToken, @"Quincy", quincyBundle(), @"")
#define BWQuincyLocalize(StringToken) StringToken

typedef enum CrashAlertType {
	CrashAlertTypeSend = 0,
	CrashAlertTypeFeedback = 1,
} CrashAlertType;

@class BWQuincyUI;

// This protocol is used to send the image updates
@protocol BWQuincyManagerDelegate <NSObject>

@required

// Invoked once the modal sheets are gone
- (void) showMainApplicationWindow;

@optional

// Return the userid the crashreport should contain, empty by default
-(NSString *) crashReportUserID;

// Return the contact value (e.g. email) the crashreport should contain, empty by default
-(NSString *) crashReportContact;

// Invoked when the internet connection is started, to let the app enable the activity indicator
-(void) connectionOpened;

// Invoked when the internet connection is closed, to let the app disable the activity indicator
-(void) connectionClosed;

@end

// TODO: check ifdef for NSXMLParserDelegate
#if defined(MAC_OS_X_VERSION_10_6)
  #if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6
    @interface BWQuincyManager : NSObject <NSXMLParserDelegate>
  #endif
#else
  @interface BWQuincyManager : NSObject
#endif
{
  CrashReportStatus _serverResult;

  NSInteger _statusCode;

  NSMutableString *_contentOfProperty;

  id _delegate;

  NSString *_submissionURL;
  NSString *_companyName;
  NSString *_appIdentifier;

  BWQuincyUI *_quincyUI;

  NSURLConnection *urlConnection_;
  NSMutableData *responseData_;

  BOOL isCrashAppVersionIdenticalToAppVersion_;
  BOOL feedbackActivated_;
  NSString *_feedbackRequestID;
}

- (NSString*) modelVersion;

+ (BWQuincyManager *)sharedQuincyManager;

// submission URL defines where to send the crash reports to (required)
@property (nonatomic, retain) NSString *submissionURL;

// defines the company name to be shown in the crash reporting dialog
@property (nonatomic, retain) NSString *companyName;

// delegate is required
@property (nonatomic, assign) id <BWQuincyManagerDelegate> delegate;


///////////////////////////////////////////////////////////////////////////////////////////////////
// settings

// If you want to use HockeyApp instead of your own server, this is required
@property (nonatomic, retain) NSString *appIdentifier;

// if YES, the user will be presented with a status of the crash, if known
// if NO, the user will not see any feedback information (default)
@property (nonatomic, assign, getter=isFeedbackActivated) BOOL feedbackActivated;

- (NSString *)consoleContent;
- (NSString *)crashFileContent;

- (void) cancelReport;
- (void) sendReport:(NSDictionary*)info;
- (void) postXML:(NSTimer *) timer;

- (NSString *) applicationName;
- (NSString *) applicationVersionString;
- (NSString *) applicationVersion;

@end
