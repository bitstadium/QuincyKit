//
//  BWQuincyUtilities.c
//  QuincyDemo
//
//  Created by Stanley Rost on 31.07.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//
#import <sys/sysctl.h>
#import "BWQuincyUtilities.h"
#import "NSData+Base64.h"

NSArray* FindLatestCrashFilesInPath(NSString* path, NSDate *minModifyTimestamp, NSArray *listOfAlreadyProcessedCrashFileNames, NSUInteger limit);
NSArray* FindLatestCrashFiles(NSDate *minModifyTimestamp, NSArray *listOfAlreadyProcessedCrashFileNames, NSUInteger limit);

NSString* OSVersion();
NSString* applicationName();
NSString* applicationVersionString();
NSString* computerModel();
BOOL parseVersionOfCrashedApplicationFromCrashLog(NSString *crashReportContent, NSString **version, NSString **shortVersion);
NSDictionary* crashLogsContentsByFilename(NSArray *crashLogs);


NSString* generateXMLPayload(NSArray *listOfCrashReportFileNames, NSDictionary *additionalDataByCrashFile);
NSURLRequest* buildURLRequestForPostingCrashes(NSString *url, NSString* xml, NSTimeInterval networkTimeoutInterval, BOOL isHockeyApp);
int processServerResponse(NSData *data, BOOL isHockeyApp);


NSArray* FindLatestCrashFilesInPath(NSString* path, NSDate *minModifyTimestamp, NSArray *listOfAlreadyProcessedCrashFileNames, NSUInteger limit)
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

NSArray* FindLatestCrashFiles(NSDate *minModifyTimestamp, NSArray *listOfAlreadyProcessedCrashFileNames, NSUInteger limit)
{
  NSArray* libraryDirectories = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, TRUE);
  NSString* postSnowLeopardPath = [[libraryDirectories lastObject] stringByAppendingPathComponent:@"Logs/DiagnosticReports"];
  NSString* preSnowLeopardPath = [[libraryDirectories lastObject] stringByAppendingPathComponent:@"Logs/CrashReporter"];
  return
    FindLatestCrashFilesInPath(postSnowLeopardPath, minModifyTimestamp, listOfAlreadyProcessedCrashFileNames, limit) ?:
    FindLatestCrashFilesInPath(preSnowLeopardPath,  minModifyTimestamp, listOfAlreadyProcessedCrashFileNames, limit);
}

NSArray* FindNewCrashFiles(NSDate* lastCrashDate, NSArray* listOfAlreadyProcessedCrashFileNames, int limit)
{
  NSArray* crashFiles = FindLatestCrashFiles(lastCrashDate, listOfAlreadyProcessedCrashFileNames, limit);
  return crashFiles;
}

NSString* OSVersion()
{
  SInt32 versionMajor, versionMinor, versionBugFix;
  if (Gestalt(gestaltSystemVersionMajor, &versionMajor) != noErr)   versionMajor  = 0;
  if (Gestalt(gestaltSystemVersionMinor, &versionMinor) != noErr)   versionMinor  = 0;
  if (Gestalt(gestaltSystemVersionBugFix, &versionBugFix) != noErr) versionBugFix = 0;
  return [NSString stringWithFormat:@"%i.%i.%i", versionMajor, versionMinor, versionBugFix];
}

NSString* applicationName()
{
  NSString *applicationName = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleExecutable"];
  
  if (!applicationName)
    applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleExecutable"];
    
    return applicationName;
}

NSString* applicationVersionString()
{
  NSString* string = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleShortVersionString"];
  
  if (!string)
    string = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleShortVersionString"];
    
    return string;
}

NSString* computerModel()
{
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

BOOL parseVersionOfCrashedApplicationFromCrashLog(NSString *crashReportContent, NSString **version, NSString **shortVersion)
{
  NSScanner *scanner = [NSScanner scannerWithString:crashReportContent];
  
  [scanner scanUpToString:@"Version:" intoString:NULL];
  [scanner scanUpToString:@"(" intoString:shortVersion];
  [scanner setScanLocation:[scanner scanLocation] + 1];
  [scanner scanUpToString:@")" intoString:version];
  
  NSString *trimmed = [*shortVersion stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  shortVersion = &trimmed;
  
  return YES;
}

NSDictionary* contentsOfCrashReportsByFileName(NSArray *crashLogs)
{
  NSMutableDictionary *contentsOfCrashReportsByFileName = [NSMutableDictionary dictionary];
  
  NSError *error;
  for (NSString *crashFile in crashLogs)
  {
    NSString *crashLogs = [NSString stringWithContentsOfFile:crashFile encoding:NSUTF8StringEncoding error:&error];
    NSString *content = [[crashLogs componentsSeparatedByString: @"**********\n\n"] lastObject];
    
    [contentsOfCrashReportsByFileName setObject:content forKey:crashFile];
  }
  
  return contentsOfCrashReportsByFileName;
}

int sendCrashReportsToServerAndParseResponse(
  NSArray *listOfCrashReportFileNames,
  NSDictionary* additionalDataByCrashFile,
  NSString *submissionURL,
  BOOL isHockeyApp,
  NSTimeInterval networkTimeoutInterval
)
{
  NSString *payload = generateXMLPayload(listOfCrashReportFileNames, additionalDataByCrashFile);
  NSLog(@"%@", payload); // FIXME remove test code
  
  NSURLRequest *request = buildURLRequestForPostingCrashes(submissionURL, payload, networkTimeoutInterval, isHockeyApp);  
  NSURLResponse *response;
  NSError *error;
  NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
  
  NSUInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
  if (statusCode < 200 || statusCode >= 400)
  {
    NSLog(@"WARNING: Server returned HTTP code: %ld", statusCode);
    // server down? ignore, will try later
    return 0; // CrashReportStatusUnknown;
  }
  
  NSString *x = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSLog(@"Server returned HTTP code %@", x); // FIXME remove test code

  int serverResponseCode = processServerResponse(data, isHockeyApp);
  return serverResponseCode;
}

NSString* generateXMLPayload(NSArray *listOfCrashReportFileNames, NSDictionary *additionalDataByCrashFile)
{
  NSString *bundleIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
  NSString *currentApplicationVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
  NSString *shortVersion = applicationVersionString();
  
  NSDictionary *crashLogsByFile = contentsOfCrashReportsByFileName(listOfCrashReportFileNames);

  NSMutableString *payload = [[NSMutableString alloc] initWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><crashes>"];
  for (NSString *crashFile in crashLogsByFile)
  {
    NSString *crashLogContent = [crashLogsByFile objectForKey:crashFile];

    NSString *crashedApplicationVersion;
    NSString *crashedApplicationShortVersion;
    parseVersionOfCrashedApplicationFromCrashLog(crashLogContent, &crashedApplicationVersion, &crashedApplicationShortVersion);
    
    NSDictionary *dataForCrash = [additionalDataByCrashFile objectForKey:crashFile];
    
    NSString *comment       = [dataForCrash objectForKey:@"comment"];
    NSString *console       = [dataForCrash objectForKey:@"console"];
    NSString *userId        = [dataForCrash objectForKey:@"userId"];
    NSString *userContact   = [dataForCrash objectForKey:@"userContact"];
    NSData *applicationData = [dataForCrash objectForKey:@"applicationData"];

    // legacy format
    NSString *description = [NSString stringWithFormat:@"Comments:\n%@\n\nConsole:\n%@", comment, console];
    
    [payload appendString:@"\n<crash>"];
    [payload appendFormat:@"<applicationname>%@</applicationname>", applicationName()];
    [payload appendFormat:@"<bundleidentifier>%@</bundleidentifier>", bundleIdentifier];
    [payload appendFormat:@"<systemversion>%@</systemversion>", OSVersion()];
    [payload appendFormat:@"<senderversion>%@</senderversion>", currentApplicationVersion];
    [payload appendFormat:@"<version>%@</version>", crashedApplicationVersion];
    [payload appendFormat:@"<bundleshortversion>%@</bundleshortversion>", shortVersion];
    [payload appendFormat:@"<platform>%@</platform>", computerModel()];
    [payload appendFormat:@"<userid>%@</userid>", userId];
    [payload appendFormat:@"<contact>%@</contact>", userContact];
    [payload appendFormat:@"<description><![CDATA[%@]]></description>", description];
    [payload appendFormat:@"<usercomment><![CDATA[%@]]></usercomment>", comment];
    [payload appendFormat:@"<console><![CDATA[%@]]></console>", console];
    [payload appendFormat:@"<applicationdata><![CDATA[%@]]></applicationdata>", [applicationData base64EncodedString]];
    [payload appendFormat:@"<log><![CDATA[%@]]></log>", crashLogContent];
    [payload appendString:@"</crash>"];
  }
  
  [payload appendString:@"</crashes>"];
  
  return payload;
}

NSURLRequest* buildURLRequestForPostingCrashes(NSString *url, NSString* xml, NSTimeInterval networkTimeoutInterval, BOOL isHockeyApp)
{
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
  NSString *boundary = @"----FOO";
  
  [request setValue:@"Quincy/Mac" forHTTPHeaderField:@"User-Agent"];
  [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
  [request setTimeoutInterval:networkTimeoutInterval];
  [request setHTTPMethod:@"POST"];
  NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
  [request setValue:contentType forHTTPHeaderField:@"Content-type"];
  
  NSMutableString *postBody =  [[NSMutableString alloc] init];  
  [postBody appendFormat:@"--%@\r\n", boundary];
  if (isHockeyApp)
  {
    [postBody appendString:@"Content-Disposition: form-data; name=\"xml\"; filename=\"crash.xml\"\r\n"];
    [postBody appendString:@"Content-Type: text/xml\r\n\r\n"];
  }
  else
  {
    [postBody appendString:@"Content-Disposition: form-data; name=\"xmlstring\"\r\n\r\n"];
  }
  [postBody appendString:xml];
  [postBody appendFormat:@"\r\n--%@--\r\n", boundary];
  
  [request setHTTPBody:[postBody dataUsingEncoding:NSUTF8StringEncoding]];
  
  return request;
}

int processServerResponse(NSData *data, BOOL isHockeyApp)
{
  int serverResponseCode = 0; // CrashReportStatusUnknown;
  // NSTimeInterval feedbackDelayInterval = 1.0;
  // NSString *crashId = nil;
  if (isHockeyApp)
  {
    // HockeyApp uses PList XML format
    
    NSMutableDictionary *response = [NSPropertyListSerialization propertyListFromData:data
                                                                     mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                                                               format:nil
                                                                     errorDescription:NULL];
    serverResponseCode = [[response objectForKey:@"status"] intValue];
    
    // TODO: bring back feedback feature
    // if (serverResponseCode == CrashReportStatusQueued)
    // {
    //   crashId = [[NSString alloc] initWithString:[response objectForKey:@"id"]];
    //   feedbackDelayInterval = [[response objectForKey:@"delay"] floatValue];
    //   // NOTE: it did not work with 0, the server responded with another delay
    //   feedbackDelayInterval = feedbackDelayInterval > 0 ? feedbackDelayInterval / 1000 : 1.0;
    // }
  }
  else
  {
    // using the HockeyKit open source server
    serverResponseCode = 0; // FIXME parse open source server response w/o xml parser
  }
  return serverResponseCode;
}

// - (void)checkForFeedbackStatus
// {
//   NSMutableURLRequest *request = nil;
//   
//   NSString *url = [self.submissionURL stringByAppendingFormat:@"/%@", _feedbackRequestID];
//   request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
//   
//   [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
//   [request setValue:@"Quincy/Mac" forHTTPHeaderField:@"User-Agent"];
//   [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
//   [request setTimeoutInterval:self.networkTimeoutInterval];
//   [request setHTTPMethod:@"GET"];
//   
//   _serverResult = CrashReportStatusUnknown;
//   statusCode_ = 200;
//   
//   // Release when done in the delegate method
//   responseData_ = [[NSMutableData alloc] init];
//   
//   if ([self.delegate respondsToSelector:@selector(connectionOpened)])
//     [self.delegate connectionOpened];
//   
//   urlConnection_ = [[NSURLConnection alloc] initWithRequest:request delegate:self];    
// }


// - (void) showCrashStatusMessage
// {
//   if ([self.interfaceDelegate respondsToSelector:@selector(presentQuincyServerFeedbackInterface:)])
//     [self.interfaceDelegate presentQuincyServerFeedbackInterface:_serverResult];
// }









