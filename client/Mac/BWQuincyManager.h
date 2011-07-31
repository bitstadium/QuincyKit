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
#import "BWQuincyUIDelegate.h"

#define CRASHREPORTSENDER_MAX_CONSOLE_SIZE 50000

typedef enum BWQuincyStatus {
  BWQuincyStatusNoCrashFound = 0,
  BWQuincyStatusUserCancelled,
  BWQuincyStatusSendingReport,
} BWQuincyStatus;

// This protocol is used to send the image updates
@protocol BWQuincyManagerDelegate <NSObject>

@required

// Callback when the crash reporter is done
- (void)didFinishCrashReporting:(BWQuincyStatus)status;

@optional

// Return the userid the crashreport should contain, empty by default
- (NSString *)crashReportUserID;

// Return the contact value (e.g. email) the crashreport should contain, empty by default
- (NSString *)crashReportContact;

// Invoked when the internet connection is started, to let the app enable the activity indicator
- (void)connectionOpened;

// Invoked when the internet connection is closed, to let the app disable the activity indicator
- (void)connectionClosed;

@end

@interface BWQuincyManager : NSObject
{
  CrashReportStatus _serverResult;

  NSInteger statusCode_;

  NSMutableString *_contentOfProperty;

  id _delegate;
  id<BWQuincyUIDelegate> interfaceDelegate_;

  NSString *_submissionURL;
  NSString *_companyName;
  NSString *_appIdentifier;

  BOOL isCrashAppVersionIdenticalToAppVersion_;
  BOOL feedbackActivated_;
  BOOL shouldPresentModalInterface_;
  NSString *_feedbackRequestID;
  NSTimeInterval maxFeedbackDelay_;
  NSTimeInterval networkTimeoutInterval_;
  NSArray *crashReports_;
}

+ (BWQuincyManager *)sharedQuincyManager;

- (void)run;
- (void)cancelReport;
- (void)sendReportWithComment:(NSString*)comment;

///////////////////////////////////////////////////////////////////////////////////////////////////
// settings

// delegate is required
@property (nonatomic, assign) id<BWQuincyManagerDelegate> delegate;

// defines the company name to be shown in the crash reporting dialog
@property (nonatomic, retain) NSString *companyName;

// submission URL defines where to send the crash reports to (required)
@property (nonatomic, retain) NSString *submissionURL;

// If you want to use HockeyApp instead of your own server, this is required
@property (nonatomic, retain) NSString *appIdentifier;

// interface delegate to override the standard UI
@property (nonatomic, assign) id<BWQuincyUIDelegate> interfaceDelegate;

// whether or not the built-in UI should present a modal or non-modal interface
@property (nonatomic, assign) BOOL shouldPresentModalInterface;

// if YES, the user will be presented with a status of the crash, if known
// if NO, the user will not see any feedback information (default)
@property (nonatomic, assign, getter=isFeedbackActivated) BOOL feedbackActivated;

// time in seconds to wait for the server for feedback on a crash report, defaults to 10 seconds
@property (nonatomic, assign) NSTimeInterval maxFeedbackDelay;

// network timeout
@property (nonatomic, assign) NSTimeInterval networkTimeoutInterval;

@end
