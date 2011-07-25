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
#import <sys/sysctl.h>

#import "BWQuincyUI.h"
#import "NSData+Base64.h"

static NSArray* FindLatestCrashFilesInPath(NSString* path, NSDate *minModifyTimestamp, NSArray *listOfAlreadyProcessedCrashFileNames, NSUInteger limit)
{
  NSString *processName = [[NSProcessInfo processInfo] processName];
  
  NSFileManager* fman = [NSFileManager defaultManager];

  NSError* error = nil;
  NSMutableArray* filteredFiles = [NSMutableArray array];
  NSArray* crashLogFiles = [fman contentsOfDirectoryAtPath:path error:&error];

  NSEnumerator* filesEnumerator = [crashLogFiles objectEnumerator];
  NSString* crashFile;
  while((crashFile = [filesEnumerator nextObject]))
  {
    NSString* crashLogPath = [path stringByAppendingPathComponent:crashFile];
    NSDate* modDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:crashLogPath error:&error] fileModificationDate];

    if (
        [modDate compare:minModifyTimestamp] == NSOrderedDescending &&
        ![listOfAlreadyProcessedCrashFileNames containsObject:crashFile] &&
        [crashFile hasPrefix:processName]
      )
    {
      [filteredFiles addObject:[NSDictionary dictionaryWithObjectsAndKeys:crashFile,@"name",crashLogPath,@"path",modDate,@"modDate",nil]];
    }
  }

  if ([filteredFiles count] < 1)
  {
    return [NSArray array];
  }

  NSSortDescriptor* dateSortDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"modDate" ascending:NO] autorelease];
  NSArray* sortedFiles = [filteredFiles sortedArrayUsingDescriptors:[NSArray arrayWithObject:dateSortDescriptor]];
  
  NSRange range;
  range.location = 0;
  range.length = [sortedFiles count] < limit ? [sortedFiles count] : limit;
  
  return [[sortedFiles valueForKeyPath:@"path"] subarrayWithRange:range];
}

static NSArray* FindLatestCrashFiles(NSDate *minModifyTimestamp, NSArray *listOfAlreadyProcessedCrashFileNames, NSUInteger limit)
{
  NSArray* libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, TRUE);
  NSString* postSnowLeopardPath = [[libraryDirectories lastObject] stringByAppendingPathComponent:@"Logs/DiagnosticReports"];
  NSString* preSnowLeopardPath = [[libraryDirectories lastObject] stringByAppendingPathComponent:@"Logs/CrashReporter"];
  return
    FindLatestCrashFilesInPath(postSnowLeopardPath, minModifyTimestamp, listOfAlreadyProcessedCrashFileNames, limit) ?:
    FindLatestCrashFilesInPath(preSnowLeopardPath,  minModifyTimestamp, listOfAlreadyProcessedCrashFileNames, limit);
}

static NSArray* FindNewCrashFiles()
{
  NSDate* lastCrashDate = [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.lastCrashDate"];
  if (!lastCrashDate)
  {
    lastCrashDate = [NSDate distantPast];
  }
  else
  {
    // FIXME: dateByAddingTimeInterval not available on 10.5
    lastCrashDate = [lastCrashDate dateByAddingTimeInterval:-24*60*60]; // look 24 hours back to catch possible time zone offsets
  }

  NSArray* listOfAlreadyProcessedCrashFileNames = [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  if (!listOfAlreadyProcessedCrashFileNames)
  {
    listOfAlreadyProcessedCrashFileNames = [NSArray array];
  }

//  lastCrashDate = [NSDate distantPast]; // FIXME: test code
//  listOfAlreadyProcessedCrashFileNames = [NSArray array]; // FIXME: test code
  
  NSArray* crashFiles = FindLatestCrashFiles(lastCrashDate, listOfAlreadyProcessedCrashFileNames, 10);
  return crashFiles;
}

@interface BWQuincyManager(private)
- (void)startManager;
- (void)finishManager:(BWQuincyStatus)status;
- (void)showCrashStatusMessage;
- (void)checkForFeedbackStatus;
- (NSString *)parseVersionOfCrashedApplicationFromCrashLog:report;
- (void)sendReportWithTimer:(NSTimer *)timer;
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

NSArray *foundCrashFiles_;

+ (BWQuincyManager *)sharedQuincyManager
{
  static BWQuincyManager *quincyManager = nil;
  
#if defined(MAC_OS_X_VERSION_10_6) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    quincyManager = [[BWQuincyManager alloc] init];
  });
#else
  if (quincyManager == nil)
    quincyManager = [[BWQuincyManager alloc] init];
#endif
  
  foundCrashFiles_ = nil;
  
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

    urlConnection_ = nil;
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

#pragma mark -
#pragma mark setter
- (void)setSubmissionURL:(NSString *)anSubmissionURL
{
    if (_submissionURL != anSubmissionURL) {
        [_submissionURL release];
        _submissionURL = [anSubmissionURL copy];
    }
    
    [self performSelector:@selector(startManager) withObject:nil afterDelay:0.1f];
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

- (NSString *)contentsOfMostRecentCrashFile
{
  NSString* crashFile = [foundCrashFiles_ objectAtIndex:0];
  NSDictionary* dictOfUserCommentsByCrashFile = [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.dictOfUserCommentsByCrashFile"];
  
  if ([[dictOfUserCommentsByCrashFile allKeys] containsObject:crashFile])
  {
    return nil;
  }

  // get the last crash log
  NSError *error;
  NSString *crashLogs = [NSString stringWithContentsOfFile:crashFile encoding:NSUTF8StringEncoding error:&error];
  NSString *content = [[crashLogs componentsSeparatedByString: @"**********\n\n"] lastObject];
  
  // remember we showed it to the user
  NSMutableDictionary *mutableDict;
  mutableDict = dictOfUserCommentsByCrashFile ? [dictOfUserCommentsByCrashFile mutableCopy] : [NSMutableDictionary dictionary];
  [mutableDict setObject:@"" forKey:crashFile];
  
  // TODO prune dictOfUserCommentsByCrashFile to only contain the last X entries, can do this by sorting keys and removing oldest keys (filenames containing date)
  
  [[NSUserDefaults standardUserDefaults] setValue:mutableDict forKey:@"CrashReportSender.dictOfUserCommentsByCrashFile"];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [mutableDict release];
  
  return content;
}

- (NSDictionary *)crashLogsByFile
{
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  
  NSError *error;
  for (NSString *crashFile in foundCrashFiles_)
  {
    NSString *crashLogs = [NSString stringWithContentsOfFile:crashFile encoding:NSUTF8StringEncoding error:&error];
    NSString *content = [[crashLogs componentsSeparatedByString: @"**********\n\n"] lastObject];
    
    [result setObject:content forKey:crashFile];
  }
  
  return result;
}


- (NSString *)consoleContent
{
  // TODO: console log, maybe cache console content, the UI (BWQuincyUI) wants it and we send it to the server
  NSMutableString *console = [NSMutableString string];
  return console;
}

#pragma mark -
#pragma mark GetCrashData

- (void)finishManager:(BWQuincyStatus)status
{
  if ([self.delegate respondsToSelector:@selector(didFinishCrashReporting:)])
    [self.delegate didFinishCrashReporting:status];
}

- (void)startManager
{
  foundCrashFiles_ = [FindNewCrashFiles() retain];
  
  if ([foundCrashFiles_ count] < 1)
  {
    // no new crashes found
    [self finishManager:BWQuincyStatusNoCrashFound];
    return;
  }
  
  NSString *crashFileContent = [self contentsOfMostRecentCrashFile];
  if (!crashFileContent)
  {
    // we found new crashes but the user already saw and commented on them
    [self sendReportWithComment:@""];
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
  
  [self.interfaceDelegate presentQuincyCrashSubmitInterfaceWithCrash:crashFileContent
                                                             console:[self consoleContent]];
}

- (NSString*) modelVersion {
    NSString * modelString  = nil;
    int        modelInfo[2] = { CTL_HW, HW_MODEL };
    size_t     modelSize;
  
    if (sysctl(modelInfo,
               2,
               NULL,
               &modelSize,
               NULL, 0) == 0) {
        void * modelData = malloc(modelSize);
        
        if (modelData) {
            if (sysctl(modelInfo,
                       2,
                       modelData,
                       &modelSize,
                       NULL, 0) == 0) {
                modelString = [NSString stringWithUTF8String:modelData];
            }
            
            free(modelData);
        }
    }
    
    return modelString;
}



- (void) cancelReport
{
  [[NSUserDefaults standardUserDefaults] setValue:[NSDate date]
                                           forKey:@"CrashReportSender.lastCrashDate"];
  
  NSArray* listOfAlreadyProcessedCrashFileNames = [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  
  NSMutableArray* mutableList = listOfAlreadyProcessedCrashFileNames ?
    [listOfAlreadyProcessedCrashFileNames mutableCopy] :
    [NSMutableArray array];
  
  [mutableList addObjectsFromArray:foundCrashFiles_];
  [[NSUserDefaults standardUserDefaults] setValue:mutableList
                                           forKey:@"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  [mutableList release];
  [[NSUserDefaults standardUserDefaults] synchronize];

  [self finishManager:BWQuincyStatusUserCancelled];
}


- (void)sendReportWithComment:(NSString*)userComment
{
  NSMutableDictionary* dictOfUserCommentsByCrashFile = [[[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.dictOfUserCommentsByCrashFile"] mutableCopy];
  [dictOfUserCommentsByCrashFile setObject:userComment forKey:[foundCrashFiles_ objectAtIndex:0]];
  [[NSUserDefaults standardUserDefaults] setValue:dictOfUserCommentsByCrashFile forKey:@"CrashReportSender.dictOfUserCommentsByCrashFile"];
  [[NSUserDefaults standardUserDefaults] synchronize];

  SInt32 versionMajor, versionMinor, versionBugFix;
  if (Gestalt(gestaltSystemVersionMajor, &versionMajor) != noErr)   versionMajor  = 0;
  if (Gestalt(gestaltSystemVersionMinor, &versionMinor) != noErr)   versionMinor  = 0;
  if (Gestalt(gestaltSystemVersionBugFix, &versionBugFix) != noErr) versionBugFix = 0;
  NSString *osVersion = [NSString stringWithFormat:@"%i.%i.%i", versionMajor, versionMinor, versionBugFix];
  
  NSString *userId = @"";
  NSString *userContact = @"";
  NSData *applicationdata = nil;
  
  if ([_delegate respondsToSelector:@selector(crashReportUserID)])
    userId = [_delegate performSelector:@selector(crashReportUserID)];
  
  if ([_delegate respondsToSelector:@selector(crashReportContact)])
    userContact = [_delegate performSelector:@selector(crashReportContact)];

  if ([_delegate respondsToSelector:@selector(crashReportApplicationData)])
   applicationdata = [_delegate performSelector:@selector(crashReportApplicationData)];

  NSString *bundleIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
  NSString *applicationVersion = [self applicationVersion];

  NSString *thisVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

  NSMutableString *xml = [[NSMutableString alloc] initWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><crashes>"];
  NSDictionary *crashLogsByFile = [self crashLogsByFile];
  
  for (NSString *crashFile in crashLogsByFile)
  {
    NSString *crashLogContent = [crashLogsByFile objectForKey:crashFile];
    NSString *crashVersion = [self parseVersionOfCrashedApplicationFromCrashLog:crashLogContent];
    isCrashAppVersionIdenticalToAppVersion_ = [thisVersion isEqualToString:crashVersion];
    
    NSString *comment = [dictOfUserCommentsByCrashFile objectForKey:crashFile];
    NSString *consoleContent = [self consoleContent];
    NSString *description = [NSString stringWithFormat:@"Comments:\n%@\n\nConsole:\n%@", comment, consoleContent];
    
    NSString *xml1 = [NSString stringWithFormat:@"\n"
                      "<crash>"
                      "<applicationname>%@</applicationname>"
                      "<bundleidentifier>%@</bundleidentifier>"
                      "<systemversion>%@</systemversion>"
                      "<senderversion>%@</senderversion>"
                      "<version>%@</version>"
                      "<platform>%@</platform>"
                      "<userid>%@</userid>"
                      "<contact>%@</contact>"
                      "<description><![CDATA[%@]]></description>" // legacy
                      "<usercomment><![CDATA[%@]]></usercomment>"
                      "<console><![CDATA[%@]]></console>"
                      "<applicationdata><![CDATA[%@]]></applicationdata>"
                      "<log><![CDATA[%@]]></log>"
                      "</crash>",
                      [self applicationName],
                      bundleIdentifier,
                      osVersion,
                      applicationVersion,
                      applicationVersion,
                      [self modelVersion],
                      userId,
                      userContact,
                      description,
                      comment,
                      consoleContent,
                      applicationdata && [crashFile isEqualToString:[foundCrashFiles_ objectAtIndex:0]] ? [applicationdata base64EncodedString] : @"",
                      crashLogContent];
    [xml appendString:xml1];
  }
  
  [xml appendString:@"</crashes>"];

//NSLog(@"%@", xml); // FIXME test code

  // TODO: Why is this call sent by a timer and not with performSelector:withObject:afterDelay:
  // both should be on the current thread
  [NSTimer scheduledTimerWithTimeInterval:0.0 target:self selector:@selector(sendReportWithTimer:) userInfo:xml repeats:NO];
  
  [self finishManager:BWQuincyStatusSendingReport];
}

- (NSString *)parseVersionOfCrashedApplicationFromCrashLog:(NSString *)report
{
  NSScanner *scanner = [NSScanner scannerWithString:report];

  NSString *crashVersion = nil;

  [scanner scanUpToString:@"Version:" intoString: NULL];
  [scanner scanUpToString:@"(" intoString:NULL];
  [scanner setScanLocation:[scanner scanLocation] + 1];
  [scanner scanUpToString:@")" intoString:&crashVersion];
  
  return crashVersion;
}

- (void)sendReportWithTimer:(NSTimer *)timer
{
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_submissionURL]];
  NSString *boundary = @"----FOO";
  
  [request setValue:@"Quincy/Mac" forHTTPHeaderField:@"User-Agent"];
  [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
  [request setTimeoutInterval:self.networkTimeoutInterval];
  [request setHTTPMethod:@"POST"];
  NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
  [request setValue:contentType forHTTPHeaderField:@"Content-type"];
  
  NSMutableString *postBody =  [[NSMutableString alloc] init];  
  [postBody appendFormat:@"--%@\r\n", boundary];
  if (self.appIdentifier)
  {
    [postBody appendString:@"Content-Disposition: form-data; name=\"xml\"; filename=\"crash.xml\"\r\n"];
    [postBody appendString:@"Content-Type: text/xml\r\n\r\n"];
  }
  else
  {
    [postBody appendString:@"Content-Disposition: form-data; name=\"xmlstring\"\r\n\r\n"];
  }
  [postBody appendString:[timer userInfo]];
  [postBody appendFormat:@"\r\n--%@--\r\n", boundary];

  [request setHTTPBody:[postBody dataUsingEncoding:NSUTF8StringEncoding]];
  
  _serverResult = CrashReportStatusUnknown;
  _statusCode = 200;
  
  [urlConnection_ cancel];
  [urlConnection_ release];
  urlConnection_ = [[NSURLConnection alloc] initWithRequest:request delegate:self];
  if (!urlConnection_)
  {
    NSLog(@"TODO: connection could not be established");
    return;
  }
  
  if ([self.delegate respondsToSelector:@selector(connectionOpened)])
    [self.delegate connectionOpened];

  responseData_ = [[NSMutableData data] retain];
  [urlConnection_ start];
}

- (void)processServerResponse
{
  if (_statusCode < 200 || _statusCode >= 400)
  {
    NSLog(@"bad server status: %ld", _statusCode);
    // server down? ignore, will try later
    return;
  }

//NSString *x = [[NSString alloc] initWithData:responseData_ encoding:NSUTF8StringEncoding];
//NSLog(@"%@", x); // FIXME test code

  [[NSUserDefaults standardUserDefaults] setValue:[NSDate date]
                                           forKey:@"CrashReportSender.lastCrashDate"];
  
  NSArray* listOfAlreadyProcessedCrashFileNames = [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  
  NSMutableArray* mutableList = listOfAlreadyProcessedCrashFileNames ?
    [listOfAlreadyProcessedCrashFileNames mutableCopy] :
    [[NSMutableArray alloc] init];
  
  [mutableList addObjectsFromArray:foundCrashFiles_];
  [[NSUserDefaults standardUserDefaults] setValue:mutableList
                                           forKey:@"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  [mutableList release];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [foundCrashFiles_ release];
  
  NSTimeInterval feedbackDelayInterval = 1.0;
  if (self.appIdentifier)
  {
    // HockeyApp uses PList XML format
    
    NSMutableDictionary *response = [NSPropertyListSerialization propertyListFromData:responseData_
                                                                     mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                                                               format:nil
                                                                     errorDescription:NULL];
    _serverResult = (CrashReportStatus)[[response objectForKey:@"status"] intValue];
    
    if (_serverResult == CrashReportStatusQueued)
    {
      _feedbackRequestID = [[NSString alloc] initWithString:[response objectForKey:@"id"]];
      feedbackDelayInterval = [[response objectForKey:@"delay"] floatValue];
      // NOTE: it did not work with 0, the server responded with another delay
      feedbackDelayInterval = feedbackDelayInterval > 0 ? feedbackDelayInterval / 1000 : 1.0;
    }
  }
  else
  {
    // using the HockeyKit open source server
    
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:responseData_];
    [parser setDelegate:self];
    
    [parser setShouldProcessNamespaces:NO];
    [parser setShouldReportNamespacePrefixes:NO];
    [parser setShouldResolveExternalEntities:NO];
    
    [parser parse];
    [parser release];
  }

  if (self.feedbackActivated && isCrashAppVersionIdenticalToAppVersion_ && self.maxFeedbackDelay > feedbackDelayInterval)
  {
    if (self.appIdentifier)
    {
      // only proceed if the server did not report any problem
      if (_serverResult == CrashReportStatusQueued)
      {
        // the report is still in the queue
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkForFeedbackStatus) object:nil];
        [self performSelector:@selector(checkForFeedbackStatus) withObject:nil afterDelay:feedbackDelayInterval];
      }
      else
      {
        // we do have a status, show it if needed
        [self showCrashStatusMessage];
      }
    }
    else
    {
      [self showCrashStatusMessage];
    }
  }
  
  [responseData_ release];
  responseData_ = nil;
  [urlConnection_ autorelease];
  
  if ([self.delegate respondsToSelector:@selector(connectionClosed)])
    [self.delegate connectionClosed];
}

- (void)checkForFeedbackStatus
{
  NSMutableURLRequest *request = nil;
  
  NSString *url = [self.submissionURL stringByAppendingFormat:@"/%@", _feedbackRequestID];
  request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
  
  [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
  [request setValue:@"Quincy/Mac" forHTTPHeaderField:@"User-Agent"];
  [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
  [request setTimeoutInterval:self.networkTimeoutInterval];
  [request setHTTPMethod:@"GET"];
  
  _serverResult = CrashReportStatusUnknown;
  _statusCode = 200;
  
  // Release when done in the delegate method
  responseData_ = [[NSMutableData alloc] init];
  
  if ([self.delegate respondsToSelector:@selector(connectionOpened)])
    [self.delegate connectionOpened];
  
  urlConnection_ = [[NSURLConnection alloc] initWithRequest:request delegate:self];    
}


- (void) showCrashStatusMessage
{
  if ([self.interfaceDelegate respondsToSelector:@selector(presentQuincyServerFeedbackInterface:)])
    [self.interfaceDelegate presentQuincyServerFeedbackInterface:_serverResult];
}

- (void)didFinishParsingServerResponse
{
  // TODO didFinishParsingServerResponse (open source server)
}

#pragma mark NSURLConnection

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
  _statusCode = [(NSHTTPURLResponse *)response statusCode];
  [responseData_ setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
  [responseData_ appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
  [self processServerResponse];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
  [connection autorelease];
  urlConnection_ = nil;
  [responseData_ release];
  responseData_ = nil;
  
  if ([self.delegate respondsToSelector:@selector(connectionClosed)])
  {
    [self.delegate connectionClosed];
  }
}

#pragma mark NSXMLParser

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
  if (qName)
    elementName = qName;

  if ([elementName isEqualToString:@"result"])
    _contentOfProperty = [NSMutableString string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
  if (qName)
    elementName = qName;
  
  if ([elementName isEqualToString:@"result"] && [_contentOfProperty intValue] > _serverResult)
    _serverResult = [_contentOfProperty intValue];
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
  if (_contentOfProperty && string != nil)
    [_contentOfProperty appendString:string];
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
  [self didFinishParsingServerResponse];
}

#pragma mark GetterSetter

- (NSString *) applicationName
{
  NSString *applicationName = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleExecutable"];
  
  if (!applicationName)
    applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleExecutable"];
  
  return applicationName;
}


- (NSString*) applicationVersionString
{
  NSString* string = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleShortVersionString"];
  
  if (!string)
    string = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleShortVersionString"];
  
  return string;
}

- (NSString *) applicationVersion
{
  return [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleVersion"];
}

@end


