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

#define DEBUG 0

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
- (NSString *)consoleContent;

- (void)storeComment:(NSString *)comment forReport:(NSString *)report;
- (NSDictionary *)loadDataForCrashFiles:(NSArray *)crashReportFilenames;
- (void)storeData:(NSDictionary *)data forCrashFile:(NSString *)crashReportFilename;
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
  
  [crashReports_ release];
  crashReports_ = nil;

  [super dealloc];
}

- (void)run
{
  NSDate* lastCrashDate = [self loadLastCrashDate];
  if (![lastCrashDate isEqualToDate:[NSDate distantPast]])
  {
    NSTimeInterval interval = -24*60*60; // look 24 hours back to catch possible time zone offsets
    if ([lastCrashDate respondsToSelector:@selector(dateByAddingTimeInterval:)])
      lastCrashDate = [lastCrashDate dateByAddingTimeInterval:interval];
    else
      [lastCrashDate addTimeInterval:interval]; // NOTE: add a category interface at the top of the source file to give the signature for the method once it is really gone
  }

  NSArray* listOfAlreadyProcessedCrashFileNames = [self loadListOfAlreadyProcessedCrashFileNames];

  // test code to always find crash files
#if DEBUG
  lastCrashDate = [NSDate distantPast];
  listOfAlreadyProcessedCrashFileNames = [NSArray array];
#endif
  
  int limit = 10;
  crashReports_ = [FindNewCrashFiles(lastCrashDate, listOfAlreadyProcessedCrashFileNames, limit) retain];
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
  
  [self.interfaceDelegate presentQuincyCrashSubmitInterfaceWithCrash:crashFileContent console:[self consoleContent]];
}

- (void)finishManager:(BWQuincyStatus)status
{
  BWQuincyManager *quincy = [BWQuincyManager sharedQuincyManager];
  if ([quincy.delegate respondsToSelector:@selector(didFinishCrashReporting:)])
    [quincy.delegate didFinishCrashReporting:status];
}

- (BOOL)hasCrashesTheUserDidNotSeeYet:(NSArray *)crashFiles content:(NSString **)crashFileContent
{
  NSString* newestCrashFile = [crashFiles objectAtIndex:0];
  NSDictionary* dataForCrashFiles = [self loadDataForCrashFiles:crashFiles];
  if ([[dataForCrashFiles allKeys] containsObject:newestCrashFile])
  {
    crashFileContent = nil;
    return NO;
  }

  // get the last crash log
  NSError *error;
  NSString *crashLogs = [NSString stringWithContentsOfFile:newestCrashFile encoding:NSUTF8StringEncoding error:&error];
  *crashFileContent = [[crashLogs componentsSeparatedByString: @"**********\n\n"] lastObject];
  
  NSString *userId = @"";
  NSString *userContact = @"";
  NSData *applicationdata = nil;
  
  if ([self.delegate respondsToSelector:@selector(crashReportUserID)])
    userId = [self.delegate performSelector:@selector(crashReportUserID)];
  
  if ([self.delegate respondsToSelector:@selector(crashReportContact)])
    userContact = [self.delegate performSelector:@selector(crashReportContact)];
  
  if ([self.delegate respondsToSelector:@selector(crashReportApplicationData)])
    applicationdata = [self.delegate performSelector:@selector(crashReportApplicationData)];
  
  NSDictionary *dataForNewestCrash = [NSDictionary dictionaryWithObjectsAndKeys:
                                      @"", @"comment",
                                      [self consoleContent], @"console",
                                      userId, @"userId",
                                      userContact, @"userContact",
                                      applicationdata, @"applicationData",
                                      nil];
  
  [self storeData:dataForNewestCrash forCrashFile:newestCrashFile];

  // remember we showed it to the user (and with that all the other new ones we found, too)
  for (NSString *file in crashFiles)
  {
    if (![file isEqualToString:newestCrashFile])
      [self storeData:[NSDictionary dictionary] forCrashFile:file];
  }
  
//  NSMutableDictionary *mutableDict;
//  mutableDict = dictOfUserCommentsByCrashFile ? [dictOfUserCommentsByCrashFile mutableCopy] : [NSMutableDictionary dictionary];
//  [mutableDict setObject:@"" forKey:crashFile];
//  
//  [self storeDictOfUserCommentsByCrashFile:mutableDict];
//  [mutableDict release];
  
  return YES;
}

- (void)markReportsProcessed:(NSArray *)listOfReports
{
  [self storeLastCrashDate:[NSDate date]];
  [self storeListOfAlreadyProcessedCrashFileNames:listOfReports];
}

- (NSString *)consoleContent
{
  return @"";
}

#pragma mark -
#pragma mark callbacks for UI

- (void)sendReportWithComment:(NSString *)userComment
{
  [self storeComment:userComment forReport:[crashReports_ objectAtIndex:0]];
  
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
  NSString *crashId = @"";
  NSTimeInterval delay = 0.0;
  int status = sendCrashReportsToServerAndParseResponse(
                                                        reports,
                                                        [self loadDataForCrashFiles:reports],
                                                        self.submissionURL,
                                                        !!self.appIdentifier,
                                                        self.networkTimeoutInterval,
                                                        &crashId,
                                                        &delay);

  [self storeLastCrashDate:[NSDate date]];
  [self storeListOfAlreadyProcessedCrashFileNames:reports];
  
  NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                        [NSNumber numberWithInt:status], @"status",
                        crashId, @"crashId",
                        [NSNumber numberWithFloat:delay], @"delay",
                        nil];
  [self performSelectorOnMainThread:@selector(didFinishSendingReport:) withObject:dict waitUntilDone:NO];
}

- (void) didFinishSendingReport:(NSDictionary *)response
{
  CrashReportStatus serverResponseCode = [[response objectForKey:@"status"] intValue];
  NSString *crashId                    = [response objectForKey:@"crashId"];
  NSTimeInterval delay                 = [[response objectForKey:@"delay"] floatValue];
  
  delay = delay + 1.0; // Note: add one more second to the delay to give the server time to breathe

  if ([self.delegate respondsToSelector:@selector(connectionClosed)])
    [self.delegate connectionClosed];
  
  NSString *newestCrashReport = [crashReports_ objectAtIndex:0];
  NSDictionary *crashLogContents = contentsOfCrashReportsByFileName([NSArray arrayWithObject:newestCrashReport]);
  NSString *crashLogContent = [crashLogContents objectForKey:newestCrashReport];
  
  NSString *crashedApplicationVersion = nil;
  NSString *crashedApplicationShortVersion = nil;
  parseVersionOfCrashedApplicationFromCrashLog(crashLogContent, &crashedApplicationVersion, &crashedApplicationShortVersion);
  
  BOOL shouldShowCrashStatus = NO;
  NSString *currentApplicationVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
  BOOL isCrashAppVersionIdenticalToAppVersion = [currentApplicationVersion isEqualTo:crashedApplicationVersion];

  BOOL isHockeyApp = !!self.appIdentifier;
  if (self.feedbackActivated && isCrashAppVersionIdenticalToAppVersion && self.maxFeedbackDelay > delay)
  {
    if (isHockeyApp)
    {
      // only proceed if the server did not report any problem
      if (serverResponseCode == CrashReportStatusQueued)
      {
        // the report is still in the queue
        //[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkForFeedbackStatus) object:nil];
        [self performSelector:@selector(checkForFeedbackStatusAfterDelay:) withObject:crashId afterDelay:delay];
      }
      else
      {
        // we do have a status, show it if needed
        shouldShowCrashStatus = YES;
      }
    }
    else
    {
      shouldShowCrashStatus = YES;
    }
  }
  
  if (shouldShowCrashStatus)
  {
    if ([self.interfaceDelegate respondsToSelector:@selector(presentQuincyServerFeedbackInterface:)])
      [self.interfaceDelegate presentQuincyServerFeedbackInterface:serverResponseCode];
  }
  
}

- (void)checkForFeedbackStatusAfterDelay:(NSString *)crashId
{
  [self performSelectorInBackground:@selector(checkForFeedbackStatusSynchronously:) withObject:crashId];
}

- (void)checkForFeedbackStatusSynchronously:(NSString *)crashId
{
  NSString *url = [self.submissionURL stringByAppendingFormat:@"/%@", crashId];
  int status = checkForFeedbackStatus(url, self.networkTimeoutInterval);
  [self performSelectorOnMainThread:@selector(didReceiveFeedback:) withObject:[NSNumber numberWithInt:status] waitUntilDone:NO];
}

- (void)didReceiveFeedback:(NSNumber *)status
{
  if ([self.interfaceDelegate respondsToSelector:@selector(presentQuincyServerFeedbackInterface:)])
    [self.interfaceDelegate presentQuincyServerFeedbackInterface:[status intValue]];
}

#pragma mark -
#pragma mark setter

- (void)setSubmissionURL:(NSString *)anSubmissionURL
{
    if (_submissionURL != anSubmissionURL) {
        [_submissionURL release];
        _submissionURL = [anSubmissionURL copy];
    }
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
  NSMutableDictionary* dataForThisCrash = [[[self loadDataForCrashFiles:nil] objectForKey:report] mutableCopy];
  [dataForThisCrash setObject:comment forKey:@"comment"];
  [self storeData:dataForThisCrash forCrashFile:report];
  [dataForThisCrash release];
}

- (NSDictionary *)loadDataForCrashFiles:(NSArray *)crashReportFilenames
{
  NSDictionary *dict = [[NSUserDefaults standardUserDefaults] valueForKey:@"CrashReportSender.dataForCrashFiles"];
  if (crashReportFilenames)
  {
    // TODO filter loaded data for crashes?
  }
  return dict ?: [NSDictionary dictionary];
}

- (void)storeData:(NSDictionary *)data forCrashFile:(NSString *)crashReportFilename
{
  NSMutableDictionary *dataForAllCrashes = [[self loadDataForCrashFiles:nil] mutableCopy];
  [dataForAllCrashes setObject:data forKey:crashReportFilename];
  [[NSUserDefaults standardUserDefaults] setValue:dataForAllCrashes forKey:@"CrashReportSender.dataForCrashFiles"];
  [dataForAllCrashes release];
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
  
  [mutableList addObjectsFromArray:listOfCrashReportFileNames];
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


