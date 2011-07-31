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

NSArray* FindNewCrashFiles()
{
  NSDate* lastCrashDate = [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.lastCrashDate"];
  if (!lastCrashDate)
  {
    lastCrashDate = [NSDate distantPast];
  }
  else
  {
    NSTimeInterval interval = -24*60*60; // look 24 hours back to catch possible time zone offsets
    if ([lastCrashDate respondsToSelector:@selector(dateByAddingTimeInterval:)])
      lastCrashDate = [lastCrashDate dateByAddingTimeInterval:interval];
    else
      [lastCrashDate addTimeInterval:interval]; // TODO: you can just add a category interface at the top of the source file to give the signature for the method
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

BOOL hasCrashesTheUserDidNotSeeYet(NSArray *crashFiles, NSString **crashFileContent)
{
  NSString* crashFile = [crashFiles objectAtIndex:0];
  NSDictionary* dictOfUserCommentsByCrashFile = [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.dictOfUserCommentsByCrashFile"];
  
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
  
  // TODO prune dictOfUserCommentsByCrashFile to only contain the last X entries, can do this by sorting keys and removing oldest keys (filenames containing date)
  
  [[NSUserDefaults standardUserDefaults] setValue:mutableDict forKey:@"CrashReportSender.dictOfUserCommentsByCrashFile"];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [mutableDict release];
  
  return YES;
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

NSString* consoleContent()
{
  return @"";
}

// FIXME: refactor and split this function
int sendCrashReports(NSArray *listOfCrashReportFileNames, NSString *submissionURL, NSDictionary *additionalData, BOOL isHockeyApp, NSTimeInterval networkTimeoutInterval)
{
  // BWQuincyManager *quincy = [BWQuincyManager sharedQuincyManager];

  NSString *bundleIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
  NSString *currentApplicationVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
  NSString *shortVersion = applicationVersionString();
  
  NSMutableString *xml = [[NSMutableString alloc] initWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><crashes>"];
  NSDictionary *crashLogsByFile = contentsOfCrashReportsByFileName(listOfCrashReportFileNames);
  
  NSDictionary* dictOfUserCommentsByCrashFile = [[NSUserDefaults standardUserDefaults] valueForKey:@"CrashReportSender.dictOfUserCommentsByCrashFile"];
  for (NSString *crashFile in crashLogsByFile)
  {
    NSString *crashLogContent = [crashLogsByFile objectForKey:crashFile];
    NSString *comment = [dictOfUserCommentsByCrashFile objectForKey:crashFile];

    NSString *crashedApplicationVersion;
    NSString *crashedApplicationShortVersion;
    parseVersionOfCrashedApplicationFromCrashLog(crashLogContent, &crashedApplicationVersion, &crashedApplicationShortVersion);
    
    NSString *console = consoleContent();
    NSString *description = [NSString stringWithFormat:@"Comments:\n%@\n\nConsole:\n%@", comment, console];
//    NSString *base64EncodedApplicationData = applicationData && [crashFile isEqualToString:[listOfCrashReportFileNames objectAtIndex:0]] ? [applicationData base64EncodedString] : @"";
    
    
    // TODO callback data, maybe like this, with a dictionary of additionalData
    NSString *userId = @"";
    NSString *userContact = @"";
    NSData *applicationData = [NSData data];
    
    NSString *key = [crashFile stringByAppendingString:@"_userId"];
    [additionalData objectForKey:key];
    
    NSString *base64EncodedApplicationData = [applicationData base64EncodedString];
    
    NSString *xml1 = [NSString stringWithFormat:@"\n"
                      "<crash>"
                      "<applicationname>%@</applicationname>"
                      "<bundleidentifier>%@</bundleidentifier>"
                      "<systemversion>%@</systemversion>"
                      "<senderversion>%@</senderversion>"
                      "<version>%@</version>"
                      "<bundleshortversion>%@</bundleshortversion>"
                      "<platform>%@</platform>"
                      "<userid>%@</userid>"
                      "<contact>%@</contact>"
                      "<description><![CDATA[%@]]></description>" // legacy
                      "<usercomment><![CDATA[%@]]></usercomment>"
                      "<console><![CDATA[%@]]></console>"
                      "<applicationdata><![CDATA[%@]]></applicationdata>"
                      "<log><![CDATA[%@]]></log>"
                      "</crash>",
                      applicationName(),
                      bundleIdentifier,
                      OSVersion(),
                      currentApplicationVersion,
                      crashedApplicationVersion,
                      shortVersion,
                      computerModel(),
                      userId,
                      userContact,
                      description,
                      comment,
                      console,
                      base64EncodedApplicationData,
                      crashLogContent];
    [xml appendString:xml1];
  }
  
  [xml appendString:@"</crashes>"];
  
  NSLog(@"%@", xml); // FIXME test code
  
  
  
  
  
  
  
  
  
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:submissionURL]];
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
  
  // _serverResult = CrashReportStatusUnknown;
  // statusCode_ = 200;
  
  NSURLResponse *response;
  NSError *error;
  NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
  
  NSUInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
  
// void processServerResponse(NSUInteger statusCode, NSData* payload, NSArray *crashReports)

  if (statusCode < 200 || statusCode >= 400)
  {
    NSLog(@"WARNING: Server returned HTTP code: %ld", statusCode);
    // server down? ignore, will try later
    return 0; // CrashReportStatusUnknown;
  }
  
  NSString *x = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSLog(@"Server returned HTTP code %@", x); // FIXME test code
  
  [[NSUserDefaults standardUserDefaults] setValue:[NSDate date]
                                           forKey:@"CrashReportSender.lastCrashDate"];
  
  // TODO: all defaults access should be in separate functions, so storage can be changed
  NSArray* listOfAlreadyProcessedCrashFileNames = [[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  
  NSMutableArray* mutableList = listOfAlreadyProcessedCrashFileNames ?
  [listOfAlreadyProcessedCrashFileNames mutableCopy] :
  [[NSMutableArray alloc] init];
  
  [mutableList addObjectsFromArray:listOfCrashReportFileNames];
  [[NSUserDefaults standardUserDefaults] setValue:mutableList
                                           forKey:@"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  [mutableList release];
  [[NSUserDefaults standardUserDefaults] synchronize];
  
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

void storeCommentForReport(NSString *comment, NSString *report)
{
  NSMutableDictionary* dictOfUserCommentsByCrashFile = [[[NSUserDefaults standardUserDefaults] valueForKey: @"CrashReportSender.dictOfUserCommentsByCrashFile"] mutableCopy];
  [dictOfUserCommentsByCrashFile setObject:comment forKey:report];
  [[NSUserDefaults standardUserDefaults] setValue:dictOfUserCommentsByCrashFile forKey:@"CrashReportSender.dictOfUserCommentsByCrashFile"];
  [[NSUserDefaults standardUserDefaults] synchronize]; 
}

void markReportsProcessed(NSArray *listOfReports)
{
  [[NSUserDefaults standardUserDefaults] setValue:[NSDate date]
                                           forKey:@"CrashReportSender.lastCrashDate"];
  
  NSArray* listOfAlreadyProcessedCrashFileNames = [[NSUserDefaults standardUserDefaults]
                                                   valueForKey: @"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  
  NSMutableArray* mutableList = listOfAlreadyProcessedCrashFileNames ?
  [listOfAlreadyProcessedCrashFileNames mutableCopy] :
  [NSMutableArray array];
  
  [mutableList addObjectsFromArray:listOfReports];
  [[NSUserDefaults standardUserDefaults] setValue:mutableList
                                           forKey:@"CrashReportSender.listOfAlreadyProcessedCrashFileNames"];
  [mutableList release];
  [[NSUserDefaults standardUserDefaults] synchronize];
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









