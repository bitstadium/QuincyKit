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

#import "BWQuincyManager.h"

#import "BWQuincyUI.h"
#import "NSData+Base64.h"
#import "BWQuincyUtilities.h"

@interface BWQuincyManager(private)
- (void)sendReport:(NSString *)xml;
- (int)parseServerResponseXML:(NSData *)xml;
- (void)finishManager:(BWQuincyStatus)status;

- (BOOL)hasCrashesTheUserDidNotSeeYet:(NSArray *)crashFiles content:(NSString **)crashFileContent;
- (void)markReportsProcessed:(NSArray *)listOfReports;

- (void)storeComment:(NSString *)comment forReport:(NSString *)report;
- (void)storeDictOfUserCommentsByCrashFile:(NSDictionary *)dict;
- (NSDictionary *)loadDictOfUserCommentsByCrashFile;
- (void)storeLastCrashDate:(NSDate *) date;
- (NSDate *)loadLastCrashDate;
- (void)storeListOfAlreadyProcessedCrashFileNames:(NSArray *)listOfCrashReportFileNames;
- (NSArray *)loadListOfAlreadyProcessedCrashFileNames;
@end

@implementation BWQuincyManager

@synthesize delegate = _delegate;
@synthesize submissionURL = _submissionURL;
@synthesize companyName = _companyName;
@synthesize appIdentifier = _appIdentifier;
@synthesize feedbackActivated = feedbackActivated_;
@synthesize maxFeedbackDelay = maxFeedbackDelay_;
@synthesize networkTimeoutInterval = networkTimeoutInterval_;
@synthesize shouldPresentModalInterface = shouldPresentModalInterface_;
@synthesize interfaceDelegate = interfaceDelegate_;

+ (BWQuincyManager *)sharedQuincyManager
{
  static BWQuincyManager *quincyManager = nil;
  
  if (quincyManager == nil)
    quincyManager = [[BWQuincyManager alloc] init];
  
  return quincyManager;
}

- (id)init
{
  if ((self = [super init]))
  {
    _serverResult = CrashReportStatusFailureDatabaseNotAvailable;

    _submissionURL = nil;
    _appIdentifier = nil;

    self.delegate                    = nil;
    self.interfaceDelegate           = nil;
    self.companyName                 = @"";
    self.networkTimeoutInterval      = 15.0;
    self.feedbackActivated           = NO;
    self.maxFeedbackDelay            = 10.0;
    self.shouldPresentModalInterface = YES;

    crashReports_ = nil;
  }
  return self;
}

- (void)dealloc
{
  _companyName = nil;
  _delegate = nil;
  _submissionURL = nil;
  _appIdentifier = nil;

  [super dealloc];
}

- (void)run
{
  // FIXME: case where the user never said to send crash reports, but still some are sent!
  NSDate* lastCrashDate = [self loadLastCrashDate];
  if (![lastCrashDate isEqualToDate:[NSDate distantPast]])
  {
    NSTimeInterval interval = -24*60*60; // look 24 hours back to catch possible time zone offsets
    if ([lastCrashDate respondsToSelector:@selector(dateByAddingTimeInterval:)])
      lastCrashDate = [lastCrashDate dateByAddingTimeInterval:interval];
    else
      [lastCrashDate addTimeInterval:interval]; // TODO: add a category interface at the top of the source file to give the signature for the method
  }

  NSArray* listOfAlreadyProcessedCrashFileNames = [self loadListOfAlreadyProcessedCrashFileNames];
  
  // FIXME: test code to always find crash files
  //  lastCrashDate = [NSDate distantPast];
  //  listOfAlreadyProcessedCrashFileNames = [NSArray array];

  int limit = 10;
  crashReports_ = FindNewCrashFiles(lastCrashDate, listOfAlreadyProcessedCrashFileNames, limit);
  
  if ([crashReports_ count] < 1)
  {
    // no new crashes found
    [self finishManager:BWQuincyStatusNoCrashFound];
    return;
  }
  
  NSString *crashFileContent;
  BOOL hasNewCrashes = [self hasCrashesTheUserDidNotSeeYet:crashReports_ content:&crashFileContent];
  
  if (!hasNewCrashes)
  {
    [self performSelectorInBackground:@selector(sendSynchronously:) withObject:crashReports_];
    return;
  }
  
  if (!self.interfaceDelegate)
  {
    BWQuincyUI *ui = [[BWQuincyUI alloc] init];
    ui.delegate           = self;
    ui.companyName        = self.companyName;
    ui.shouldPresentModal = self.shouldPresentModalInterface;
    
    self.interfaceDelegate = ui;
  }
  
  [self.interfaceDelegate presentQuincyCrashSubmitInterfaceWithCrash:crashFileContent console:consoleContent()];
}

- (void)finishManager:(BWQuincyStatus)status
{
  BWQuincyManager *quincy = [BWQuincyManager sharedQuincyManager];
  if ([quincy.delegate respondsToSelector:@selector(didFinishCrashReporting:)])
    [quincy.delegate didFinishCrashReporting:status];
}

- (BOOL)hasCrashesTheUserDidNotSeeYet:(NSArray *)crashFiles content:(NSString **)crashFileContent
{
  NSString* crashFile = [crashFiles objectAtIndex:0];
  NSDictionary* dictOfUserCommentsByCrashFile = [self loadDictOfUserCommentsByCrashFile];
  
  if ([[dictOfUserCommentsByCrashFile allKeys] containsObject:crashFile])
  {
    return NO;
  }
  
  // get the last crash log
  NSError *error;
  NSString *crashLogs = [NSString stringWithContentsOfFile:crashFile encoding:NSUTF8StringEncoding error:&error];
  *crashFileContent = [[crashLogs componentsSeparatedByString: @"**********\n\n"] lastObject];
  
  // remember we showed it to the user
  NSMutableDictionary *mutableDict;
  mutableDict = dictOfUserCommentsByCrashFile ? [dictOfUserCommentsByCrashFile mutableCopy] : [NSMutableDictionary dictionary];
  [mutableDict setObject:@"" forKey:crashFile];
  
  [self storeDictOfUserCommentsByCrashFile:mutableDict];
  [mutableDict release];
  
  return YES;
}

- (void)markReportsProcessed:(NSArray *)listOfReports
{
  [self storeLastCrashDate:[NSDate date]];
  [self storeListOfAlreadyProcessedCrashFileNames:listOfReports];
}

#pragma mark -
#pragma mark callbacks for UI

- (void)sendReportWithComment:(NSString *)userComment
{
  [self storeComment:userComment forReport:[crashReports_ objectAtIndex:0]];
  
  // FIXME: bring callbacks back, persist this info per crash with user comments

  //  NSString *userId = @"";
  //  NSString *userContact = @"";
  //  NSData *applicationdata = nil;
  
  //  if ([self.delegate respondsToSelector:@selector(crashReportUserID)])
  //    userId = [self.delegate performSelector:@selector(crashReportUserID)];
  //  
  //  if ([self.delegate respondsToSelector:@selector(crashReportContact)])
  //    userContact = [self.delegate performSelector:@selector(crashReportContact)];
  //  
  //  if ([self.delegate respondsToSelector:@selector(crashReportApplicationData)])
  //    applicationdata = [self.delegate performSelector:@selector(crashReportApplicationData)];


  if ([self.delegate respondsToSelector:@selector(connectionOpened)])
    [self.delegate connectionOpened];

  [self performSelectorInBackground:@selector(sendSynchronously:) withObject:crashReports_];
  [self finishManager:BWQuincyStatusSendingReport];
}

- (void)cancelReport
{
  [self markReportsProcessed:crashReports_];
  [self finishManager:BWQuincyStatusUserCancelled];
}


#pragma mark -
#pragma mark Server interaction

- (void)sendSynchronously:(NSArray *)reports
{
  NSDictionary *additionalData = [NSDictionary dictionary];
  int status = sendCrashReportsToServerAndParseResponse(reports, [self loadDictOfUserCommentsByCrashFile], self.submissionURL, additionalData, !!self.appIdentifier, self.networkTimeoutInterval);

  // TODO figure out where exactly lastCrashDate should be set
  [self storeLastCrashDate:[NSDate date]];
  [self storeListOfAlreadyProcessedCrashFileNames:reports];
  
  NSNumber *statusObj = [NSNumber numberWithInt:status];
  [self performSelectorOnMainThread:@selector(didFinishSendingReport:) withObject:statusObj waitUntilDone:NO];
}

- (void) didFinishSendingReport:(NSNumber *)status
{
  NSLog(@"%@", status);

  if ([self.delegate respondsToSelector:@selector(connectionClosed)])
    [self.delegate connectionClosed];
  
  
    // FIXME bring back feedback feature
//  BOOL shouldShowCrashStatus = NO;
//  BOOL isCrashAppVersionIdenticalToAppVersion = NO; // FIXME isCrashAppVersionIdenticalToAppVersion
//  if (isFeedbackActivated && isCrashAppVersionIdenticalToAppVersion && maxFeedbackDelay > feedbackDelayInterval)
//  {
//    if (isHockeyApp)
//    {
//      // only proceed if the server did not report any problem
//      if (serverResponseCode == CrashReportStatusQueued)
//      {
//        // the report is still in the queue
//        [NSObject cancelPreviousPerformRequestsWithTarget:quincy selector:@selector(checkForFeedbackStatus) object:nil];
//        [quincy performSelector:@selector(checkForFeedbackStatus) withObject:nil afterDelay:feedbackDelayInterval];
//      }
//      else
//      {
//        // we do have a status, show it if needed
//        shouldShowCrashStatus = YES;
//      }
//    }
//    else
//    {
//      shouldShowCrashStatus = YES;
//    }
//  }
//  
//  if (shouldShowCrashStatus)
//  {
//    if ([quincy.interfaceDelegate respondsToSelector:@selector(presentQuincyServerFeedbackInterface:)])
//      [quincy.interfaceDelegate presentQuincyServerFeedbackInterface:_serverResult];
//  }
//  
}

#pragma mark -
#pragma mark setter

- (void)setSubmissionURL:(NSString *)anSubmissionURL
{
    if (_submissionURL != anSubmissionURL) {
        [_submissionURL release];
        _submissionURL = [anSubmissionURL copy];
    }
    
//    [self performSelector:@selector(startManager) withObject:nil afterDelay:0.1f];
}

- (void)setAppIdentifier:(NSString *)anAppIdentifier
{
    if (_appIdentifier != anAppIdentifier)
    {
        [_appIdentifier release];
        _appIdentifier = [anAppIdentifier copy];
    }
    
    [self setSubmissionURL:[NSString stringWithFormat:@"https://beta.hockeyapp.net/api/2/apps/%@/crashes", anAppIdentifier]];
}

#pragma mark -
#pragma mark persistence

- (void)storeComment:(NSString *)comment forReport:(NSString *)report
{
  NSMutableDictionary* mutableDict = [[self loadDictOfUserCommentsByCrashFile] mutableCopy];
  [mutableDict setObject:comment forKey:report];
  [self storeDictOfUserCommentsByCrashFile:mutableDict];
  [mutableDict release];
}


- (void)storeDictOfUserCommentsByCrashFile:(NSDictionary *)dict
{
  // TODO prune dictOfUserCommentsByCrashFile to only contain the last X entries, can do this by sorting keys and removing oldest keys (filenames containing date)
  [[NSUserDefaults standardUserDefaults] setValue:dict forKey:@"CrashReportSender.dictOfUserCommentsByCrashFile"];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSDictionary*)loadDictOfUserCommentsByCrashFile
{
  // TODO use #define or make static for these keys
  return [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.dictOfUserCommentsByCrashFile"];
}


- (void)storeLastCrashDate:(NSDate *) date
{
  [[NSUserDefaults standardUserDefaults] setValue:date forKey:@"CrashReportSender.lastCrashDate"];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSDate *)loadLastCrashDate
{
  NSDate *date = [[NSUserDefaults standardUserDefaults] valueForKey:@"CrashReportSender.lastCrashDate"];
  return date ?: [NSDate distantPast];
}


- (void)storeListOfAlreadyProcessedCrashFileNames:(NSArray *)listOfCrashReportFileNames
{
  NSArray* list = [self loadListOfAlreadyProcessedCrashFileNames];
  
  NSMutableArray* mutableList = list ?
    [list mutableCopy] :
    [[NSMutableArray alloc] init];
  
  [mutableList addObjectsFromArray:listOfCrashReportFileNames]; // TODO: test for duplicates in listOfCrashReportFileNames
  [[NSUserDefaults standardUserDefaults] setValue:mutableList forKey:@"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [mutableList release];
}

- (NSArray *)loadListOfAlreadyProcessedCrashFileNames
{
  NSArray *list = [[NSUserDefaults standardUserDefaults] valueForKey:@"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  return list ?: [NSArray array];
}




@end


