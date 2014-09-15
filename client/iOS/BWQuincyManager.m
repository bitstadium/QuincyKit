/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
 *
 * Copyright (c) 2012-2014 HockeyApp, Bit Stadium GmbH.
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

#import <CrashReporter/CrashReporter.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <UIKit/UIKit.h>

#import "BWQuincyManager.h"
#import "BWQuincyManagerDelegate.h"
#import "BWCrashReportTextFormatter.h"

#include <sys/sysctl.h>
#include <inttypes.h> //needed for PRIx64 macro

#define SDK_NAME @"Quincy"
#define SDK_VERSION @"3.0.0"

#define BWQuincyLog(fmt, ...) do { if([BWQuincyManager sharedQuincyManager].isDebugLogEnabled) { NSLog((@"[Quincy] %s/%d " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__); }} while(0)

#define kQuincyBundleName @"Quincy.bundle"

NSBundle *quincyBundle(void);
NSString *BWQuincyLocalize(NSString *stringToken);

NSString *const kBWQuincyErrorDomain = @"BWQuincyErrorDomain";

/**
 *  HockeySDK Crash Reporter error domain
 */
typedef NS_ENUM (NSInteger, BWQuincyErrorReason) {
  /**
   *  Unknown error
   */
  BWQuincyErrorUnknown,
  /**
   *  API Server rejected app version
   */
  BWQuincyAPIAppVersionRejected,
  /**
   *  API Server returned empty response
   */
  BWQuincyAPIReceivedEmptyResponse,
  /**
   *  Connection error with status code
   */
  BWQuincyAPIErrorWithStatusCode
};


// flags if the QuincyKit is activated at all
NSString *const kQuincyKitActivated = @"QuincyKitActivated";

// flags if the crashreporter should automatically send crashes without asking the user again
NSString *const kQuincyAutomaticallySendCrashReports = @"QuincyAutomaticallySendCrashReports";

// the UUID for this installation of app
NSString *const kQuincyKitAppInstallationUUID = @"QuincyKitAppInstallationUUID";

// stores the set of crashreports that have been approved but aren't sent yet
NSString *const kQuincyApprovedCrashReports = @"QuincyApprovedCrashReports";

// keys for meta information associated to each crash
NSString *const kQuincyMetaUserEmail = @"QuincyMetaUserEmail";
NSString *const kQuincyMetaUserID = @"QuincyMetaUserID";
NSString *const kQuincyMetaUserName = @"QuincyMetaUserName";
NSString *const kQuincyMetaApplicationLog = @"QuincyMetaApplicationLog";


NSBundle *quincyBundle(void) {
  static NSBundle* bundle = nil;
  if (!bundle) {
    NSString* path = [[[NSBundle mainBundle] resourcePath]
                      stringByAppendingPathComponent:kQuincyBundleName];
    bundle = [NSBundle bundleWithPath:path];
  }
  return bundle;
}

NSString *BWQuincyLocalize(NSString *stringToken) {
  if (!stringToken) return @"";
  
  NSString *appSpecificLocalizationString = NSLocalizedString(stringToken, @"");
  if (appSpecificLocalizationString && ![stringToken isEqualToString:appSpecificLocalizationString]) {
    return appSpecificLocalizationString;
  } else if (quincyBundle()) {
    NSString *bundleSpecificLocalizationString = NSLocalizedStringFromTableInBundle(stringToken, @"Quincy", quincyBundle(), @"");
    if (bundleSpecificLocalizationString)
      return bundleSpecificLocalizationString;
    return stringToken;
  } else {
    return stringToken;
  }
}


@implementation BWQuincyManager {
  NSMutableDictionary *_approvedCrashReports;
  
  NSMutableArray *_crashFiles;
  NSString       *_crashesDir;
  NSString       *_settingsFile;
  NSString       *_analyzerInProgressFile;
  NSFileManager  *_fileManager;
  
  NSUncaughtExceptionHandler *_exceptionHandler;
  PLCrashReporter *_plCrashReporter;
  PLCrashReporterCallbacks *_crashCallBacks;
  
  BOOL _crashReportActivated;
  BOOL _crashIdenticalCurrentVersion;
  
  NSMutableData *_responseData;
  NSInteger _statusCode;
  
  NSMutableURLRequest *_request;
  NSURLConnection *_urlConnection;
  
  BOOL _sendingInProgress;
  BOOL _isSetup;
}


+(BWQuincyManager *)sharedQuincyManager {
  static BWQuincyManager *sharedInstance = nil;
  static dispatch_once_t pred;
  
  dispatch_once(&pred, ^{
    sharedInstance = [BWQuincyManager alloc];
    sharedInstance = [sharedInstance init];
  });
  
  return sharedInstance;
}

- (id) init {
  if ((self = [super init])) {
    _submissionURL = nil;
    _appIdentifier = nil;
    _delegate = nil;
    _showAlwaysButton = YES;
    _autoSubmitCrashReport = NO;
    _debugLogEnabled = NO;
    _isSetup = NO;
    
    _plCrashReporter = nil;
    _exceptionHandler = nil;
    _crashCallBacks = nil;
    
    _crashIdenticalCurrentVersion = YES;
    _request = nil;
    _urlConnection = nil;
    _responseData = nil;
    _sendingInProgress = NO;
    
    _didCrashInLastSession = NO;
    _timeintervalCrashInLastSessionOccured = -1;
    
    _approvedCrashReports = [[NSMutableDictionary alloc] init];
    
    _fileManager = [[NSFileManager alloc] init];
    _crashFiles = [[NSMutableArray alloc] init];
    
    _appStoreEnvironment = NO;
#if !TARGET_IPHONE_SIMULATOR
    // check if we are really in an app store environment
    if (![[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"]) {
      _appStoreEnvironment = YES;
    }
#endif
    
    NSString *testValue = [[NSUserDefaults standardUserDefaults] stringForKey:kQuincyKitActivated];
    if (testValue) {
      _crashReportActivated = [[NSUserDefaults standardUserDefaults] boolForKey:kQuincyKitActivated];
    } else {
      _crashReportActivated = YES;
      [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:YES] forKey:kQuincyKitActivated];
    }
    
    // temporary directory for crashes grabbed from PLCrashReporter
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    _crashesDir = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"/crashes/"];
    
    if (![_fileManager fileExistsAtPath:_crashesDir]) {
      NSDictionary *attributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0755] forKey: NSFilePosixPermissions];
      NSError *theError = NULL;
      
      [_fileManager createDirectoryAtPath:_crashesDir withIntermediateDirectories: YES attributes: attributes error: &theError];
    }
    
    _settingsFile = [_crashesDir stringByAppendingPathComponent:@"quincykit.settings"];
    _analyzerInProgressFile = [_crashesDir stringByAppendingPathComponent:@"quincykit.analyzer"];
    
    if ([_fileManager fileExistsAtPath:_analyzerInProgressFile]) {
      NSError *error = nil;
      [_fileManager removeItemAtPath:_analyzerInProgressFile error:&error];
    }
    
    if (!quincyBundle()) {
      NSLog(@"WARNING: Quincy.bundle is missing, will send reports automatically!");
    }
  }
  return self;
}


- (void) dealloc {
  [self unregisterObservers];
  
  [_urlConnection cancel];
}


#pragma mark - Private methods

/**
 * Save all settings
 *
 * This saves the list of approved crash reports
 */
- (void)saveSettings {
  NSString *errorString = nil;
  
  NSMutableDictionary *rootObj = [NSMutableDictionary dictionaryWithCapacity:2];
  if (_approvedCrashReports && [_approvedCrashReports count] > 0)
    [rootObj setObject:_approvedCrashReports forKey:kQuincyApprovedCrashReports];
  
  if (self.userID)
    [rootObj setObject:self.userID forKey:kQuincyMetaUserID];
  
  if (self.userName)
    [rootObj setObject:self.userName forKey:kQuincyMetaUserName];
  
  if (self.userEmail)
    [rootObj setObject:self.userEmail forKey:kQuincyMetaUserEmail];

  NSData *plist = [NSPropertyListSerialization dataFromPropertyList:(id)rootObj
                                                             format:NSPropertyListBinaryFormat_v1_0
                                                   errorDescription:&errorString];
  if (plist) {
    [plist writeToFile:_settingsFile atomically:YES];
  } else {
    BWQuincyLog(@"ERROR: Writing settings. %@", errorString);
  }
}

/**
 * Load all settings
 *
 * This contains the list of approved crash reports
 */
- (void)loadSettings {
  NSString *errorString = nil;
  NSPropertyListFormat format;
  
  if (![_fileManager fileExistsAtPath:_settingsFile])
    return;
  
  NSData *plist = [NSData dataWithContentsOfFile:_settingsFile];
  if (plist) {
    NSDictionary *rootObj = (NSDictionary *)[NSPropertyListSerialization
                                             propertyListFromData:plist
                                             mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                             format:&format
                                             errorDescription:&errorString];
    
    if ([rootObj objectForKey:kQuincyApprovedCrashReports])
      [_approvedCrashReports setDictionary:[rootObj objectForKey:kQuincyApprovedCrashReports]];

    if ([rootObj objectForKey:kQuincyMetaUserID])
      _userID = [rootObj objectForKey:kQuincyMetaUserID];
    
    if ([rootObj objectForKey:kQuincyMetaUserName])
      _userName = [rootObj objectForKey:kQuincyMetaUserName];
    
    if ([rootObj objectForKey:kQuincyMetaUserEmail])
      _userEmail = [rootObj objectForKey:kQuincyMetaUserEmail];

  } else {
    BWQuincyLog(@"ERROR: Reading crash manager settings.");
  }
}

/**
 *	 Remove all crash reports and stored meta data for each from the file system and keychain
 */
- (void)cleanCrashReports {
  NSError *error = NULL;
  
  for (NSUInteger i=0; i < [_crashFiles count]; i++) {
    [_fileManager removeItemAtPath:[_crashFiles objectAtIndex:i] error:&error];
    [_fileManager removeItemAtPath:[[_crashFiles objectAtIndex:i] stringByAppendingString:@".meta"] error:&error];
  }
  [_crashFiles removeAllObjects];

  [[NSUserDefaults standardUserDefaults] setObject:nil forKey:kQuincyApprovedCrashReports];
}

/**
 *	 Extract all app sepcific UUIDs from the crash reports
 *
 * This allows us to send the UUIDs in the XML construct to the server, so the server does not need to parse the crash report for this data.
 * The app specific UUIDs help to identify which dSYMs are needed to symbolicate this crash report.
 *
 *	@param	report The crash report from PLCrashReporter
 *
 *	@return XML structure with the app sepcific UUIDs
 */
- (NSString *) extractAppUUIDs:(PLCrashReport *)report {
  NSMutableString *uuidString = [NSMutableString string];
  NSArray *uuidArray = [BWCrashReportTextFormatter arrayOfAppUUIDsForCrashReport:report];
  
  for (NSDictionary *element in uuidArray) {
    if ([element objectForKey:kBWBinaryImageKeyUUID] && [element objectForKey:kBWBinaryImageKeyArch] && [element objectForKey:kBWBinaryImageKeyUUID]) {
      [uuidString appendFormat:@"<uuid type=\"%@\" arch=\"%@\">%@</uuid>",
       [element objectForKey:kBWBinaryImageKeyType],
       [element objectForKey:kBWBinaryImageKeyArch],
       [element objectForKey:kBWBinaryImageKeyUUID]
       ];
    }
  }
  
  return uuidString;
}

- (void)registerObservers {
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(triggerDelayedProcessing)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(triggerDelayedProcessing)
                                               name:BWQuincyNetworkBecomeReachable
                                             object:nil];
}

- (void)unregisterObservers {
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:BWQuincyNetworkBecomeReachable object:nil];
}


- (void)setUserID:(NSString *)userID {
  _userID = userID;
  [self saveSettings];
}

- (void)setUserName:(NSString *)userName {
  _userName = userName;
  [self saveSettings];
}

- (void)setUserEmail:(NSString *)userEmail {
  _userEmail = userEmail;
  [self saveSettings];
}

- (NSString *)appName:(NSString *)placeHolderString {
  NSString *appName = [[[NSBundle mainBundle] localizedInfoDictionary] objectForKey:@"CFBundleDisplayName"];
  if (!appName)
    appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: placeHolderString;
  
  return appName;
}

- (NSString *)generateUUID {
  NSString *resultUUID = nil;
  
  id uuidClass = NSClassFromString(@"NSUUID");
  if (uuidClass) {
    resultUUID = [[NSUUID UUID] UUIDString];
  } else {
    // Create a new UUID
    CFUUIDRef uuidObj = CFUUIDCreate(nil);
    
    // Get the string representation of the UUID
    resultUUID = (NSString*)CFBridgingRelease(CFUUIDCreateString(nil, uuidObj));
    CFRelease(uuidObj);
  }
  
  return resultUUID;
}

- (NSString *)appAnonID {
  static NSString *appAnonID = nil;
  static dispatch_once_t predAppAnonID;
  
  dispatch_once(&predAppAnonID, ^{
    NSString *testValue = [[NSUserDefaults standardUserDefaults] stringForKey:kQuincyKitAppInstallationUUID];
    if (testValue) {
      appAnonID = testValue;
    } else {
      appAnonID = [self generateUUID];
    }
  });
  
  return appAnonID;
}

- (NSString *)devicePlatform {
  size_t size;
  sysctlbyname("hw.machine", NULL, &size, NULL, 0);
  char *answer = (char*)malloc(size);
  if (answer == NULL)
    return @"";
  sysctlbyname("hw.machine", answer, &size, NULL, 0);
  NSString *platform = [NSString stringWithCString:answer encoding: NSUTF8StringEncoding];
  free(answer);
  return platform;
}

- (NSString *)urlEncodedString:(NSString *)inputString {
  return CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                   (__bridge CFStringRef)inputString,
                                                                   NULL,
                                                                   CFSTR("!*'();:@&=+$,/?%#[]"),
                                                                   kCFStringEncodingUTF8)
                           );
}

- (NSString *)encodeAppIdentifier {
  return (_appIdentifier ? [self urlEncodedString:_appIdentifier] : [self urlEncodedString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"]]);
}


- (BOOL)autoSendCrashReports {
  BOOL result = NO;
  
  if (!self.autoSubmitCrashReport) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey: kQuincyAutomaticallySendCrashReports]) {
      result = YES;
    }
  } else {
    result = YES;
  }
  
  return result;
}


#pragma mark - Public

- (void)submissionURL:(NSString *)submissionURL {
  if (_submissionURL != submissionURL) {
    _submissionURL = [submissionURL copy];
  }
}

- (void)setAppIdentifier:(NSString *)appIdentifier {
  if (_appIdentifier != appIdentifier) {
    _appIdentifier = [appIdentifier copy];
  }
  
  [self setSubmissionURL:@"https://sdk.hockeyapp.net/"];
}

- (void)setCrashCallbacks: (PLCrashReporterCallbacks *) callbacks {
  _crashCallBacks = callbacks;
}

/**
 * Check if the debugger is attached
 *
 * Taken from https://github.com/plausiblelabs/plcrashreporter/blob/2dd862ce049e6f43feb355308dfc710f3af54c4d/Source/Crash%20Demo/main.m#L96
 *
 * @return `YES` if the debugger is attached to the current process, `NO` otherwise
 */
- (BOOL)isDebuggerAttached {
  static BOOL debuggerIsAttached = NO;
  
  static dispatch_once_t debuggerPredicate;
  dispatch_once(&debuggerPredicate, ^{
    struct kinfo_proc info;
    size_t info_size = sizeof(info);
    int name[4];
    
    name[0] = CTL_KERN;
    name[1] = KERN_PROC;
    name[2] = KERN_PROC_PID;
    name[3] = getpid();
    
    if (sysctl(name, 4, &info, &info_size, NULL, 0) == -1) {
      NSLog(@"[HockeySDK] ERROR: Checking for a running debugger via sysctl() failed: %s", strerror(errno));
      debuggerIsAttached = false;
    }
    
    if (!debuggerIsAttached && (info.kp_proc.p_flag & P_TRACED) != 0)
      debuggerIsAttached = true;
  });
  
  return debuggerIsAttached;
}


- (void)generateTestCrash {
  if (![self isAppStoreEnvironment]) {
    
    if ([self isDebuggerAttached]) {
      NSLog(@"[HockeySDK] WARNING: The debugger is attached. The following crash cannot be detected by the SDK!");
    }
    
    __builtin_trap();
  }
}


#pragma mark - PLCrashReporter

/**
 *	 Process new crash reports provided by PLCrashReporter
 *
 * Parse the new crash report and gather additional meta data from the app which will be stored along the crash report
 */
- (void) handleCrashReport {
  NSError *error = NULL;
	
  if (!_plCrashReporter) return;
  
  [self loadSettings];
  
  // check if the next call ran successfully the last time
  if (![_fileManager fileExistsAtPath:_analyzerInProgressFile]) {
    // mark the start of the routine
    [_fileManager createFileAtPath:_analyzerInProgressFile contents:nil attributes:nil];
    
    [self saveSettings];
    
    // Try loading the crash report
    NSData *crashData = [[NSData alloc] initWithData:[_plCrashReporter loadPendingCrashReportDataAndReturnError: &error]];
    
    NSString *cacheFilename = [NSString stringWithFormat: @"%.0f", [NSDate timeIntervalSinceReferenceDate]];
    
    if (crashData == nil) {
      BWQuincyLog(@"ERROR: Could not load crash report: %@", error);
    } else {
      // get the startup timestamp from the crash report, and the file timestamp to calculate the timeinterval when the crash happened after startup
      PLCrashReport *report = [[PLCrashReport alloc] initWithData:crashData error:&error];
      
      if (report == nil) {
        BWQuincyLog(@"WARNING: Could not parse crash report");
      } else {
        if ([report.processInfo respondsToSelector:@selector(processStartTime)]) {
          if (report.systemInfo.timestamp && report.processInfo.processStartTime) {
            _timeintervalCrashInLastSessionOccured = [report.systemInfo.timestamp timeIntervalSinceDate:report.processInfo.processStartTime];
          }
        }
        
        [crashData writeToFile:[_crashesDir stringByAppendingPathComponent: cacheFilename] atomically:YES];
        
        // write the meta file
        NSMutableDictionary *metaDict = [NSMutableDictionary dictionaryWithCapacity:4];
        NSString *applicationLog = @"";
        NSString *errorString = nil;
        
        [metaDict setObject:(self.userID ?: @"") forKey:kQuincyMetaUserID];
        [metaDict setObject:(self.userName ?: @"") forKey:kQuincyMetaUserName];
        [metaDict setObject:(self.userEmail ?: @"") forKey:kQuincyMetaUserEmail];
        
          if (self.delegate != nil && [self.delegate respondsToSelector:@selector(applicationLogForQuincyManager:)]) {
          applicationLog = [self.delegate applicationLogForQuincyManager:self] ?: @"";
        }
        [metaDict setObject:applicationLog forKey:kQuincyMetaApplicationLog];
        
        NSData *plist = [NSPropertyListSerialization dataFromPropertyList:(id)metaDict
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                         errorDescription:&errorString];
        if (plist) {
          [plist writeToFile:[NSString stringWithFormat:@"%@.meta", [_crashesDir stringByAppendingPathComponent: cacheFilename]] atomically:YES];
        } else {
          BWQuincyLog(@"ERROR: Writing crash meta data failed. %@", error);
        }
      }
    }
  }
	
  // Purge the report
  // mark the end of the routine
  if ([_fileManager fileExistsAtPath:_analyzerInProgressFile]) {
    [_fileManager removeItemAtPath:_analyzerInProgressFile error:&error];
  }
  
  [self saveSettings];
  
  [_plCrashReporter purgePendingCrashReport];
}

/**
 *	Check if there are any crash reports available which the user did not approve yet
 *
 *	@return `YES` if there are crash reports pending that are not approved, `NO` otherwise
 */
- (BOOL)hasNonApprovedCrashReports {
  if ((!_approvedCrashReports || [_approvedCrashReports count] == 0) && [_crashFiles count] > 0) return YES;
  
  for (NSUInteger i=0; i < [_crashFiles count]; i++) {
    NSString *filename = [_crashFiles objectAtIndex:i];
    
    if (![_approvedCrashReports objectForKey:filename]) return YES;
  }
  
  return NO;
}

/**
 *	Check if there are any new crash reports that are not yet processed
 *
 *	@return	`YES` if ther eis at least one new crash report found, `NO` otherwise
 */
- (BOOL)hasPendingCrashReport {
  if (!_crashReportActivated) return NO;
  
  if ([_fileManager fileExistsAtPath:_crashesDir]) {
    NSString *file = nil;
    NSError *error = NULL;
    
    NSDirectoryEnumerator *dirEnum = [_fileManager enumeratorAtPath: _crashesDir];
    
    while ((file = [dirEnum nextObject])) {
      NSDictionary *fileAttributes = [_fileManager attributesOfItemAtPath:[_crashesDir stringByAppendingPathComponent:file] error:&error];
      if ([[fileAttributes objectForKey:NSFileSize] intValue] > 0 &&
          ![file hasSuffix:@".DS_Store"] &&
          ![file hasSuffix:@".analyzer"] &&
          ![file hasSuffix:@".plist"] &&
          ![file hasSuffix:@".settings"] &&
          ![file hasSuffix:@".meta"]) {
        [_crashFiles addObject:[_crashesDir stringByAppendingPathComponent: file]];
      }
    }
  }
  
  if ([_crashFiles count] > 0) {
    BWQuincyLog(@"INFO: %lu pending crash reports found.", (unsigned long)[_crashFiles count]);
    return YES;
  } else {
    if (_didCrashInLastSession) {
      if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashManagerWillCancelSendingCrashReport:)]) {
        [self.delegate crashManagerWillCancelSendingCrashReport:self];
      }
      
      _didCrashInLastSession = NO;
    }
    
    return NO;
  }
}


#pragma mark - Crash Report Processing

- (void)triggerDelayedProcessing {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(invokeDelayedProcessing) object:nil];
  [self performSelector:@selector(invokeDelayedProcessing) withObject:nil afterDelay:0.5];
}

/**
 * Delayed startup processing for everything that does not to be done in the app startup runloop
 *
 * - Checks if there is another exception handler installed that may block ours
 * - Present UI if the user has to approve new crash reports
 * - Send pending approved crash reports
 */
- (void)invokeDelayedProcessing {
  if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) return;
  
  BWQuincyLog(@"INFO: Start delayed CrashManager processing");
  
  // was our own exception handler successfully added?
  if (_exceptionHandler) {
    // get the current top level error handler
    NSUncaughtExceptionHandler *currentHandler = NSGetUncaughtExceptionHandler();
    
    // If the top level error handler differs from our own, then at least another one was added.
    // This could cause exception crashes not to be reported to HockeyApp. See log message for details.
    if (_exceptionHandler != currentHandler) {
      BWQuincyLog(@"[HockeySDK] WARNING: Another exception handler was added. If this invokes any kind exit() after processing the exception, which causes any subsequent error handler not to be invoked, these crashes will NOT be reported to HockeyApp!");
    }
  }
  
  if (!_sendingInProgress && [self hasPendingCrashReport]) {
    _sendingInProgress = YES;
    if (!quincyBundle()) {
      [self sendCrashReports];
    } else if (![self autoSendCrashReports] && [self hasNonApprovedCrashReports]) {
      
      if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashManagerWillShowSubmitCrashReportAlert:)]) {
        [self.delegate crashManagerWillShowSubmitCrashReportAlert:self];
      }
      
      NSString *appName = [self appName:BWQuincyLocalize(@"CrashAppNamePlaceholder")];
      NSString *alertDescription = [NSString stringWithFormat:BWQuincyLocalize(@"CrashDataFoundAnonymousDescription"), appName];
      
      // the crash report is not anynomous any more if username or useremail are not nil
      if ((self.userID && [self.userID length] > 0) ||
          (self.userName && [self.userName length] > 0) ||
          (self.userEmail && [self.userEmail length] > 0)) {
        alertDescription = [NSString stringWithFormat:BWQuincyLocalize(@"CrashDataFoundDescription"), appName];
      }
      
      UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:BWQuincyLocalize(@"CrashDataFoundTitle"), appName]
                                                          message:alertDescription
                                                         delegate:self
                                                cancelButtonTitle:BWQuincyLocalize(@"CrashDontSendReport")
                                                otherButtonTitles:BWQuincyLocalize(@"CrashSendReport"), nil];
      
      if (self.shouldShowAlwaysButton) {
        [alertView addButtonWithTitle:BWQuincyLocalize(@"CrashSendReportAlways")];
      }
      [alertView show];
    } else {
      [self sendCrashReports];
    }
  }
}

/**
 *	 Main startup sequence initializing PLCrashReporter if it wasn't disabled
 */
- (void)startManager {
  if (!_crashReportActivated) return;
  
  [self registerObservers];
  
  if (!_isSetup) {
    static dispatch_once_t plcrPredicate;
    dispatch_once(&plcrPredicate, ^{
      /* Configure our reporter */
      
      PLCrashReporterSignalHandlerType signalHandlerType = PLCrashReporterSignalHandlerTypeBSD;
      if (self.isMachExceptionHandlerEnabled) {
        signalHandlerType = PLCrashReporterSignalHandlerTypeMach;
      }
      PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc] initWithSignalHandlerType: signalHandlerType
                                                                         symbolicationStrategy: PLCrashReporterSymbolicationStrategyAll];
      _plCrashReporter = [[PLCrashReporter alloc] initWithConfiguration: config];
      
      // Check if we previously crashed
      if ([_plCrashReporter hasPendingCrashReport]) {
        _didCrashInLastSession = YES;
        [self handleCrashReport];
      }
      
      // The actual signal and mach handlers are only registered when invoking `enableCrashReporterAndReturnError`
      // So it is safe enough to only disable the following part when a debugger is attached no matter which
      // signal handler type is set
      // We only check for this if we are not in the App Store environment
      
      BOOL debuggerIsAttached = NO;
      if (![self isAppStoreEnvironment]) {
        if ([self isDebuggerAttached]) {
          debuggerIsAttached = YES;
          NSLog(@"[Quincy] WARNING: Detecting crashes is NOT enabled due to running the app with a debugger attached.");
        }
      }
      
      if (!debuggerIsAttached) {
        // Multiple exception handlers can be set, but we can only query the top level error handler (uncaught exception handler).
        //
        // To check if PLCrashReporter's error handler is successfully added, we compare the top
        // level one that is set before and the one after PLCrashReporter sets up its own.
        //
        // With delayed processing we can then check if another error handler was set up afterwards
        // and can show a debug warning log message, that the dev has to make sure the "newer" error handler
        // doesn't exit the process itself, because then all subsequent handlers would never be invoked.
        //
        // Note: ANY error handler setup BEFORE HockeySDK initialization will not be processed!
        
        // get the current top level error handler
        NSUncaughtExceptionHandler *initialHandler = NSGetUncaughtExceptionHandler();
        
        // PLCrashReporter may only be initialized once. So make sure the developer
        // can't break this
        NSError *error = NULL;
        
        // set any user defined callbacks, hopefully the users knows what they do
        if (_crashCallBacks) {
          [_plCrashReporter setCrashCallbacks:_crashCallBacks];
        }
        
        // Enable the Crash Reporter
        if (![_plCrashReporter enableCrashReporterAndReturnError: &error])
          NSLog(@"[Quincy] WARNING: Could not enable crash reporter: %@", [error localizedDescription]);
        
        // get the new current top level error handler, which should now be the one from PLCrashReporter
        NSUncaughtExceptionHandler *currentHandler = NSGetUncaughtExceptionHandler();
        
        // do we have a new top level error handler? then we were successful
        if (currentHandler && currentHandler != initialHandler) {
          _exceptionHandler = currentHandler;
          
          BWQuincyLog(@"INFO: Exception handler successfully initialized.");
        } else {
          // this should never happen, theoretically only if NSSetUncaugtExceptionHandler() has some internal issues
          NSLog(@"[Quincy] ERROR: Exception handler could not be set. Make sure there is no other exception handler set up!");
        }
      }
      _isSetup = YES;
    });
  }
  
  [self triggerDelayedProcessing];
}

/**
 *	 Send all approved crash reports
 *
 * Gathers all collected data and constructs the XML structure and starts the sending process
 */
- (void)sendCrashReports {
  NSError *error = NULL;
  
  NSMutableString *crashes = nil;
  _crashIdenticalCurrentVersion = NO;
  
  for (NSUInteger i=0; i < [_crashFiles count]; i++) {
    NSString *filename = [_crashFiles objectAtIndex:i];
    NSData *crashData = [NSData dataWithContentsOfFile:filename];
		
    if ([crashData length] > 0) {
      PLCrashReport *report = [[PLCrashReport alloc] initWithData:crashData error:&error];
			
      if (report == nil) {
        BWQuincyLog(@"WARNING: Could not parse crash report");
        // we cannot do anything with this report, so delete it
        [_fileManager removeItemAtPath:filename error:&error];
        [_fileManager removeItemAtPath:[NSString stringWithFormat:@"%@.meta", filename] error:&error];
        
        continue;
      }
      
      NSString *crashUUID = @"";
      if (report.uuidRef != NULL) {
        crashUUID = (NSString *) CFBridgingRelease(CFUUIDCreateString(NULL, report.uuidRef));
      }
      NSString *installString = [self appAnonID] ?: @"";
      NSString *crashLogString = [BWCrashReportTextFormatter stringValueForCrashReport:report crashReporterKey:installString];
      
      if ([report.applicationInfo.applicationVersion compare:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]] == NSOrderedSame) {
        _crashIdenticalCurrentVersion = YES;
      }
			
      if (crashes == nil) {
        crashes = [NSMutableString string];
      }
      
      NSString *username = @"";
      NSString *useremail = @"";
      NSString *userid = @"";
      NSString *applicationLog = @"";
      NSString *description = @"";
      
      NSString *errorString = nil;
      NSPropertyListFormat format;
      
      NSData *plist = [NSData dataWithContentsOfFile:[filename stringByAppendingString:@".meta"]];
      if (plist) {
        NSDictionary *metaDict = (NSDictionary *)[NSPropertyListSerialization
                                                  propertyListFromData:plist
                                                  mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                                  format:&format
                                                  errorDescription:&errorString];
        
        username = [metaDict objectForKey:kQuincyMetaUserName] ?: @"";
        useremail = [metaDict objectForKey:kQuincyMetaUserEmail] ?: @"";
        userid = [metaDict objectForKey:kQuincyMetaUserID] ?: @"";
        applicationLog = [metaDict objectForKey:kQuincyMetaApplicationLog] ?: @"";
      } else {
        BWQuincyLog(@"ERROR: Reading crash meta data. %@", error);
      }
      
      if ([applicationLog length] > 0) {
        description = [NSString stringWithFormat:@"%@", applicationLog];
      }
      
      [crashes appendFormat:@"<crash><applicationname>%s</applicationname><uuids>%@</uuids><bundleidentifier>%@</bundleidentifier><systemversion>%@</systemversion><platform>%@</platform><senderversion>%@</senderversion><version>%@</version><uuid>%@</uuid><log><![CDATA[%@]]></log><userid>%@</userid><username>%@</username><contact>%@</contact><installstring>%@</installstring><description><![CDATA[%@]]></description></crash>",
       [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] UTF8String],
       [self extractAppUUIDs:report],
       report.applicationInfo.applicationIdentifier,
       report.systemInfo.operatingSystemVersion,
       [self devicePlatform],
       [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
       report.applicationInfo.applicationVersion,
       crashUUID,
       [crashLogString stringByReplacingOccurrencesOfString:@"]]>" withString:@"]]" @"]]><![CDATA[" @">" options:NSLiteralSearch range:NSMakeRange(0,crashLogString.length)],
       userid,
       username,
       useremail,
       installString,
       [description stringByReplacingOccurrencesOfString:@"]]>" withString:@"]]" @"]]><![CDATA[" @">" options:NSLiteralSearch range:NSMakeRange(0,description.length)]];
      
      
      // store this crash report as user approved, so if it fails it will retry automatically
      [_approvedCrashReports setObject:[NSNumber numberWithBool:YES] forKey:filename];
    } else {
      // we cannot do anything with this report, so delete it
      [_fileManager removeItemAtPath:filename error:&error];
      [_fileManager removeItemAtPath:[NSString stringWithFormat:@"%@.meta", filename] error:&error];
    }
  }
	
  [self saveSettings];
  
  if (crashes != nil) {
    BWQuincyLog(@"INFO: Sending crash reports:\n%@", crashes);
    [self postXML:[NSString stringWithFormat:@"<crashes>%@</crashes>", crashes]];
  }
}


#pragma mark - UIAlertView Delegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
  switch (buttonIndex) {
    case 0:
      if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashManagerWillCancelSendingCrashReport:)]) {
        [self.delegate crashManagerWillCancelSendingCrashReport:self];
      }
      
      _sendingInProgress = NO;
      [self cleanCrashReports];
      break;
    case 1:
      [self sendCrashReports];
      break;
    case 2: {
      _autoSubmitCrashReport = YES;
      [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kQuincyAutomaticallySendCrashReports];
      if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashManagerWillSendCrashReportsAlways:)]) {
        [self.delegate crashManagerWillSendCrashReportsAlways:self];
      }
      
      [self sendCrashReports];
      break;
    }
    default:
      _sendingInProgress = NO;
      [self cleanCrashReports];
      break;
  }
}


#pragma mark - Networking

/**
 *	 Send the XML data to the server
 *
 * Wraps the XML structure into a POST body and starts sending the data asynchronously
 *
 *	@param	xml	The XML data that needs to be send to the server
 */
- (void)postXML:(NSString*)xml {
  NSString *boundary = @"----FOO";
  
  if (self.appIdentifier) {
    _request = [NSMutableURLRequest requestWithURL:
                [NSURL URLWithString:[NSString stringWithFormat:@"%@api/2/apps/%@/crashes?sdk=%@&sdk_version=%@&feedbackEnabled=no",
                                      self.submissionURL,
                                      [self encodeAppIdentifier],
                                      SDK_NAME,
                                      SDK_VERSION
                                      ]
                 ]];
  } else {
    _request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.submissionURL]];
  }
  
  [_request setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
  [_request setValue:@"Quincy/iOS" forHTTPHeaderField:@"User-Agent"];
  [_request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
  [_request setTimeoutInterval: 15];
  [_request setHTTPMethod:@"POST"];
  NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
  [_request setValue:contentType forHTTPHeaderField:@"Content-type"];
	
  NSMutableData *postBody =  [NSMutableData data];
  [postBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
  if (self.appIdentifier) {
    [postBody appendData:[@"Content-Disposition: form-data; name=\"xml\"; filename=\"crash.xml\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [postBody appendData:[[NSString stringWithFormat:@"Content-Type: text/xml\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
  } else {
    [postBody appendData:[@"Content-Disposition: form-data; name=\"xmlstring\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  }
  [postBody appendData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
  [postBody appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
  
  [_request setHTTPBody:postBody];
	
  _statusCode = 200;
	
  //Release when done in the delegate method
  _responseData = [[NSMutableData alloc] init];
	
  _urlConnection = [[NSURLConnection alloc] initWithRequest:_request delegate:self];
  
  if (!_urlConnection) {
    BWQuincyLog(@"INFO: Sending crash reports could not start!");
    _sendingInProgress = NO;
  } else {
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashManagerWillSendCrashReport:)]) {
      [self.delegate crashManagerWillSendCrashReport:self];
    }
    
    BWQuincyLog(@"INFO: Sending crash reports started.");
  }
}

#pragma mark - NSURLConnection Delegate

-(NSURLRequest *)connection:(NSURLConnection *)connection
            willSendRequest:(NSURLRequest *)request
           redirectResponse:(NSURLResponse *)redirectResponse
{
  if (redirectResponse) {
    // via Steven Fisher: http://stackoverflow.com/a/10787143/474794
    // The request you initialized the connection with should be kept as _request.
    // Instead of trying to merge the pieces of _request into Cocoa
    // touch's proposed redirect request, we make a mutable copy of the
    // original request, change the URL to match that of the proposed
    // request, and return it as the request to use.
    //
    NSMutableURLRequest *r = [_request mutableCopy];
    [r setURL: [request URL]];
    return r;
  } else {
    return request;
  }
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    _statusCode = [(NSHTTPURLResponse *)response statusCode];
  }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
  [_responseData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
  if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashManager:didFailWithError:)]) {
    [self.delegate crashManager:self didFailWithError:error];
  }
  
  BWQuincyLog(@"ERROR: %@", [error localizedDescription]);
  
  _sendingInProgress = NO;
	
  _responseData = nil;
  _urlConnection = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  NSError *error = nil;
  
  if (_statusCode >= 200 && _statusCode < 400 && _responseData != nil && [_responseData length] > 0) {
    [self cleanCrashReports];
    
    if (self.appIdentifier) {
      // HockeyApp uses PList XML format
      NSMutableDictionary *response = [NSPropertyListSerialization propertyListFromData:_responseData
                                                                       mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                                                                 format:nil
                                                                       errorDescription:NULL];
      BWQuincyLog(@"INFO: Received API response: %@", response);
    } else {
      BWQuincyLog(@"Received API response: %@", [[NSString alloc] initWithBytes:[_responseData bytes] length:[_responseData length] encoding: NSUTF8StringEncoding]);
    }
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashManagerDidFinishSendingCrashReport:)]) {
      [self.delegate crashManagerDidFinishSendingCrashReport:self];
    }
  } else if (_statusCode == 400 && self.appIdentifier) {
    [self cleanCrashReports];
    
    error = [NSError errorWithDomain:kBWQuincyErrorDomain
                                code:BWQuincyAPIAppVersionRejected
                            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"The server rejected receiving crash reports for this app version!", NSLocalizedDescriptionKey, nil]];
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashManager:didFailWithError:)]) {
      [self.delegate crashManager:self didFailWithError:error];
    }
    
    BWQuincyLog(@"ERROR: %@", [error localizedDescription]);
  } else {
    if (_responseData == nil || [_responseData length] == 0) {
      error = [NSError errorWithDomain:kBWQuincyErrorDomain
                                  code:BWQuincyAPIReceivedEmptyResponse
                              userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"Sending failed with an empty response!", NSLocalizedDescriptionKey, nil]];
    } else {
      error = [NSError errorWithDomain:kBWQuincyErrorDomain
                                  code:BWQuincyAPIErrorWithStatusCode
                              userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"Sending failed with status code: %li", (long)_statusCode], NSLocalizedDescriptionKey, nil]];
    }
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(crashManager:didFailWithError:)]) {
      [self.delegate crashManager:self didFailWithError:error];
    }
    
    BWQuincyLog(@"ERROR: %@", [error localizedDescription]);
  }
  
  _sendingInProgress = NO;
	
  _responseData = nil;
  _urlConnection = nil;
}


@end
