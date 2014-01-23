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

#import "BWQuincyManager.h"
#import "BWQuincyManagerPrivate.h"
#import "BWCrashReportTextFormatter.h"
#import "BWQuincyUI.h"
#import <sys/sysctl.h>
#import <CrashReporter/CrashReporter.h>

#define SDK_NAME @"Quincy"
#define SDK_VERSION @"3.0"

#define BWQuincyLog(fmt, ...) do { if([BWQuincyManager sharedQuincyManager].isDebugLogEnabled) { NSLog((@"[Quincy] %s/%d " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__); }} while(0)

// flags if the QuincyKit is activated at all
NSString *const kQuincyActivated = @"QuincyActivated";

// flags if the crashreporter should automatically send crashes without asking the user again
NSString *const kQuincyAutomaticallySendCrashReports = @"QuincyAutomaticallySendCrashReports";

// stores the set of crashreports that have been approved but aren't sent yet
NSString *const kQuincyApprovedCrashReports = @"QuincyApprovedCrashReports";

// keys for meta information associated to each crash
NSString *const kQuincyMetaUserEmail = @"QuincyMetaUserEmail";
NSString *const kQuincyMetaUserID = @"QuincyMetaUserID";
NSString *const kQuincyMetaUserName = @"QuincyMetaUserName";
NSString *const kQuincyMetaApplicationLog = @"QuincyMetaApplicationLog";
NSString *const kQuincyMetaDescription = @"QuincyMetaDescription";

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


@implementation BWQuincyManager

@synthesize delegate = _delegate;
@synthesize submissionURL = _submissionURL;
@synthesize companyName = _companyName;
@synthesize appIdentifier = _appIdentifier;
@synthesize autoSubmitCrashReport = _autoSubmitCrashReport;
@synthesize userID = _userID;
@synthesize userName = _userName;
@synthesize userEmail = _userEmail;
@synthesize askUserDetails = _askUserDetails;
@synthesize timeintervalCrashInLastSessionOccured = _timeintervalCrashInLastSessionOccured;
@synthesize maxTimeIntervalOfCrashForReturnMainApplicationDelay = _maxTimeIntervalOfCrashForReturnMainApplicationDelay;
@synthesize enableMachExceptionHandler = _enableMachExceptionHandler;
@synthesize didCrashInLastSession = _didCrashInLastSession;
@synthesize plcrExceptionHandler = _plcrExceptionHandler;
@synthesize debugLogEnabled = _debugLogEnabled;

+ (BWQuincyManager *)sharedQuincyManager {
  static BWQuincyManager *quincyManager = nil;
  
  if (quincyManager == nil) {
    quincyManager = [[BWQuincyManager alloc] init];
  }
  
  return quincyManager;
}

- (id) init {
  if ((self = [super init])) {
    _quincyUI = nil;
    
    _submissionURL = nil;
    _appIdentifier = nil;
    
    _delegate = nil;
    _companyName = nil;
    _request = nil;
    
    _fileManager = [[NSFileManager alloc] init];
    _askUserDetails = YES;
    
    _userEmail = nil;
    _userName = nil;
    
    _plcrExceptionHandler = nil;
    _crashIdenticalCurrentVersion = YES;
    
    _timeintervalCrashInLastSessionOccured = -1;
    _maxTimeIntervalOfCrashForReturnMainApplicationDelay = 5;
    
    _approvedCrashReports = [[NSMutableDictionary alloc] init];
    _dictOfLastSessionCrash = [[NSMutableDictionary alloc] init];
    _didCrashInLastSession = NO;
    
    _crashFiles = [[NSMutableArray alloc] init];
    _crashesDir = nil;
    
    _invokedReturnToMainApplication = NO;
    
    NSString *testValue = nil;
    testValue = [[NSUserDefaults standardUserDefaults] stringForKey:kQuincyActivated];
    if (testValue) {
      _quincyActivated = [[NSUserDefaults standardUserDefaults] boolForKey:kQuincyActivated];
    } else {
      _quincyActivated = YES;
      [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:YES] forKey:kQuincyActivated];
    }
    
    testValue = [[NSUserDefaults standardUserDefaults] stringForKey:kQuincyAutomaticallySendCrashReports];
    if (testValue) {
      _autoSubmitCrashReport = [[NSUserDefaults standardUserDefaults] boolForKey:kQuincyAutomaticallySendCrashReports];
    } else {
      _autoSubmitCrashReport = NO;
      [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:NO] forKey:kQuincyAutomaticallySendCrashReports];
    }
    
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    
    // temporary directory for crashes grabbed from PLCrashReporter
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDir = [paths objectAtIndex: 0];
    _crashesDir = [[[cacheDir stringByAppendingPathComponent:bundleIdentifier] stringByAppendingPathComponent:@"de.buzzworks.Quincy"] retain];
    
    if (![_fileManager fileExistsAtPath:_crashesDir]) {
      NSDictionary *attributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0755] forKey: NSFilePosixPermissions];
      NSError *theError = NULL;
      
      [_fileManager createDirectoryAtPath:_crashesDir withIntermediateDirectories: YES attributes: attributes error: &theError];
    }
    
    _settingsFile = [[_crashesDir stringByAppendingPathComponent:@"quincykit.settings"] retain];
    _analyzerInProgressFile = [[_crashesDir stringByAppendingPathComponent:@"quincykit.analyzer"] retain];
    
    if ([_fileManager fileExistsAtPath:_analyzerInProgressFile]) {
      NSError *theError = nil;
      [_fileManager removeItemAtPath:_analyzerInProgressFile error:&theError];
    }
  }
  return self;
}

- (void)dealloc {
  [_responseData release]; _responseData = nil;
  
  [_appIdentifier release]; _appIdentifier = nil;
  [_submissionURL release]; _submissionURL = nil;
  [_companyName release]; _companyName = nil;
  [_userName release]; _userName = nil;
  [_userEmail release]; _userEmail = nil;
  
  [_fileManager release]; _fileManager = nil;
  
  [_crashFiles release]; _crashFiles = nil;
  [_crashesDir release]; _crashesDir = nil;
  [_settingsFile release]; _settingsFile = nil;
  [_analyzerInProgressFile release]; _analyzerInProgressFile = nil;
  
  [_quincyUI release], _quincyUI = nil;
  
  [_approvedCrashReports release]; _approvedCrashReports = nil;
  [_dictOfLastSessionCrash release]; _dictOfLastSessionCrash = nil;
  
  [super dealloc];
}


#pragma mark - Private

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

- (void)cleanCrashReports {
  NSError *error = NULL;
  
  for (NSUInteger i=0; i < [_crashFiles count]; i++) {
    [_fileManager removeItemAtPath:[_crashFiles objectAtIndex:i] error:&error];
    [_fileManager removeItemAtPath:[[_crashFiles objectAtIndex:i] stringByAppendingString:@".meta"] error:&error];
  }
  [_crashFiles removeAllObjects];
  [_approvedCrashReports removeAllObjects];
  
  [self saveSettings];
}

- (NSString *)extractAppUUIDs:(PLCrashReport *)report {
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

- (void)returnToMainApplication {
  if (_invokedReturnToMainApplication) {
    return;
  }
  
  _invokedReturnToMainApplication = YES;
  
  if (self.delegate != nil && [self.delegate respondsToSelector:@selector(showMainApplicationWindowForCrashManager:)]) {
    [self.delegate showMainApplicationWindowForCrashManager:self];
  }
}

- (NSString *)urlEncodedString:(NSString *)inputString {
  return CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                   (CFStringRef)inputString,
                                                                   NULL,
                                                                   CFSTR("!*'();:@&=+$,/?%#[]"),
                                                                   kCFStringEncodingUTF8)
                           );
}

- (NSString *)encodeAppIdentifier {
  return (_appIdentifier ? [self urlEncodedString:_appIdentifier] : [self urlEncodedString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"]]);
}

- (NSString *)deviceIdentifier {
  char buffer[128];
  
  io_registry_entry_t registry = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/");
  CFStringRef uuid = (CFStringRef)IORegistryEntryCreateCFProperty(registry, CFSTR(kIOPlatformUUIDKey), kCFAllocatorDefault, 0);
  IOObjectRelease(registry);
  CFStringGetCString(uuid, buffer, 128, kCFStringEncodingMacRoman);
  CFRelease(uuid);
  
  return [NSString stringWithCString:buffer encoding:NSUTF8StringEncoding];
}

- (NSString *)deviceModel {
  NSString *model = nil;
  
  int error = 0;
  int value = 0;
	size_t length = sizeof(value);
  
  error = sysctlbyname("hw.model", NULL, &length, NULL, 0);
  if (error == 0) {
    char *cpuModel = (char *)malloc(sizeof(char) * length);
    if (cpuModel != NULL) {
      error = sysctlbyname("hw.model", cpuModel, &length, NULL, 0);
      if (error == 0) {
        model = [NSString stringWithUTF8String:cpuModel];
      }
      free(cpuModel);
    }
  }
  
  return model;
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
  
  [self setSubmissionURL:@"https://rink.hockeyapp.net/"];
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
  static BOOL debuggerIsChecked = NO;
  if (debuggerIsChecked) return debuggerIsAttached;
  
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
  
  debuggerIsChecked = YES;
  
  return debuggerIsAttached;
}


#pragma mark - PLCrashReporter

// Called to handle a pending crash report.
- (void)handleCrashReport {
  NSError *error = NULL;
	
  [self loadSettings];
  
  // check if the next call ran successfully the last time
  if (![_fileManager fileExistsAtPath:_analyzerInProgressFile]) {
    // mark the start of the routine
    [_fileManager createFileAtPath:_analyzerInProgressFile contents:nil attributes:nil];
    
    [self saveSettings];
    
    // Try loading the crash report
    NSData *crashData = [[[NSData alloc] initWithData:[_plCrashReporter loadPendingCrashReportDataAndReturnError: &error]] autorelease];
    
    NSString *cacheFilename = [NSString stringWithFormat: @"%.0f", [NSDate timeIntervalSinceReferenceDate]];
    
    if (crashData == nil) {
      BWQuincyLog(@"Warning: Could not load crash report: %@", error);
    } else {
      [crashData writeToFile:[_crashesDir stringByAppendingPathComponent: cacheFilename] atomically:YES];
      
      // get the startup timestamp from the crash report, and the file timestamp to calculate the timeinterval when the crash happened after startup
      PLCrashReport *report = [[[PLCrashReport alloc] initWithData:crashData error:&error] autorelease];
      
      if ([report.processInfo respondsToSelector:@selector(processStartTime)]) {
        if (report.systemInfo.timestamp && report.processInfo.processStartTime) {
          _timeintervalCrashInLastSessionOccured = [report.systemInfo.timestamp timeIntervalSinceDate:report.processInfo.processStartTime];
        }
      }
      
      [crashData writeToFile:[_crashesDir stringByAppendingPathComponent: cacheFilename] atomically:YES];
      
      // write the meta file
      NSString *applicationLog = @"";
      NSString *errorString = nil;
      
      [_dictOfLastSessionCrash setObject:(self.userID ?: @"") forKey:[NSString stringWithFormat:@"%@.%@", cacheFilename, kQuincyMetaUserID]];
      [_dictOfLastSessionCrash setObject:(self.userName ?: @"") forKey:[NSString stringWithFormat:@"%@.%@", cacheFilename, kQuincyMetaUserName]];
      [_dictOfLastSessionCrash setObject:(self.userEmail ?: @"") forKey:[NSString stringWithFormat:@"%@.%@", cacheFilename, kQuincyMetaUserEmail]];
      
      if (self.delegate != nil && [self.delegate respondsToSelector:@selector(applicationLogForCrashManager:)]) {
        applicationLog = [self.delegate applicationLogForCrashManager:self] ?: @"";
      }
      [_dictOfLastSessionCrash setObject:applicationLog forKey:kQuincyMetaApplicationLog];
      
      NSData *plist = [NSPropertyListSerialization dataFromPropertyList:(id)_dictOfLastSessionCrash
                                                                 format:NSPropertyListBinaryFormat_v1_0
                                                       errorDescription:&errorString];
      if (plist) {
        [plist writeToFile:[NSString stringWithFormat:@"%@.meta", [_crashesDir stringByAppendingPathComponent: cacheFilename]] atomically:YES];
      } else {
        BWQuincyLog(@"ERROR: Writing crash meta data failed. %@", error);
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

- (BOOL)hasNonApprovedCrashReports {
  if (!_approvedCrashReports || [_approvedCrashReports count] == 0) return YES;
  
  for (NSUInteger i=0; i < [_crashFiles count]; i++) {
    NSString *filename = [_crashFiles objectAtIndex:i];
    
    if (![_approvedCrashReports objectForKey:filename]) return YES;
  }
  
  return NO;
}

- (BOOL)hasPendingCrashReport {
  if (!_quincyActivated) return NO;
  
  if ([_fileManager fileExistsAtPath: _crashesDir]) {
    NSString *file = nil;
    NSError *error = NULL;
    
    NSDirectoryEnumerator *dirEnum = [_fileManager enumeratorAtPath: _crashesDir];
    
    while ((file = [dirEnum nextObject])) {
      NSDictionary *fileAttributes = [_fileManager attributesOfItemAtPath:[_crashesDir stringByAppendingPathComponent:file] error:&error];
      if ([[fileAttributes objectForKey:NSFileSize] intValue] > 0 &&
          ![file hasSuffix:@".DS_Store"] &&
          ![file hasSuffix:@".analyzer"] &&
          ![file hasSuffix:@".meta"] &&
          ![file hasSuffix:@".settings"] &&
          ![file hasSuffix:@".plist"]) {
        [_crashFiles addObject:[_crashesDir stringByAppendingPathComponent: file]];
      }
    }
  }
  
  if ([_crashFiles count] > 0) {
    BWQuincyLog(@"INFO: %li pending crash reports found.", (unsigned long)[_crashFiles count]);
    return YES;
  } else {
    if (_didCrashInLastSession) {
      _didCrashInLastSession = NO;
    }
    
    return NO;
  }
}


#pragma mark - Crash Report Processing

- (void)invokeProcessing {
  BWQuincyLog(@"INFO: Start QuincyManager processing");
  BOOL returnToApp = NO;
  
  if ([self hasPendingCrashReport]) {
    BWQuincyLog(@"INFO: Pending crash reports found.");
    
    [self loadSettings];
    
    NSError* error = nil;
    NSString *crashReport = nil;
    
    NSString *crashFile = [_crashFiles lastObject];
    NSData *crashData = [NSData dataWithContentsOfFile: crashFile];
    PLCrashReport *report = [[[PLCrashReport alloc] initWithData:crashData error:&error] autorelease];
    NSString *installString = [self deviceIdentifier] ?: @"";
    crashReport = [BWCrashReportTextFormatter stringValueForCrashReport:report crashReporterKey:installString];
    
    if (crashReport && !error) {
      NSString *log = [_dictOfLastSessionCrash valueForKey:kQuincyMetaApplicationLog] ?: @"";
      
      if (!self.autoSubmitCrashReport && [self hasNonApprovedCrashReports]) {
        
        if (self.delegate != nil && [self.delegate respondsToSelector:@selector(quincyManagerWillShowSubmitCrashReportAlert:)]) {
          [self.delegate quincyManagerWillShowSubmitCrashReportAlert:self];
        }
        
        _quincyUI = [[BWQuincyUI alloc] initWithManager:self
                                        crashReportFile:crashFile
                                            crashReport:crashReport
                                             logContent:log
                                            companyName:_companyName ?: @"the developer"
                                        applicationName:[self applicationName]
                                         askUserDetails:_askUserDetails];
        
        [_quincyUI setUserName:(self.userName ?: @"")];
        [_quincyUI setUserEmail:(self.userEmail ?: @"")];
        
        [_quincyUI askCrashReportDetails];
      } else {
        [self sendReportWithCrash:crashFile crashDescription:nil];
      }
    } else {
      if (![self hasNonApprovedCrashReports]) {
        [self performSendingCrashReports];
      } else {
        returnToApp = YES;
      }
    }
  } else {
    returnToApp = YES;
  }
  
  if (returnToApp)
    [self returnToMainApplication];
  
  [self performSelector:@selector(invokeDelayedProcessing) withObject:nil afterDelay:0.5];
}

- (void)startManager {
  if (!_quincyActivated) {
    [self returnToMainApplication];
    return;
  }
  
  BWQuincyLog(@"INFO: Start CrashManager startManager");
  
  if (!_plCrashReporter) {
    /* Configure our reporter */
    
    PLCrashReporterSignalHandlerType signalHandlerType = PLCrashReporterSignalHandlerTypeBSD;
    if (self.isMachExceptionHandlerEnabled) {
      signalHandlerType = PLCrashReporterSignalHandlerTypeMach;
    }
    PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc] initWithSignalHandlerType: signalHandlerType
                                                                             symbolicationStrategy: PLCrashReporterSymbolicationStrategySymbolTable];
    _plCrashReporter = [[PLCrashReporter alloc] initWithConfiguration: config];
    NSError *error = NULL;
    
    // Check if we previously crashed
    if ([_plCrashReporter hasPendingCrashReport]) {
      _didCrashInLastSession = YES;
      [self handleCrashReport];
    }
    
    // The actual signal and mach handlers are only registered when invoking `enableCrashReporterAndReturnError`
    // So it is safe enough to only disable the following part when a debugger is attached no matter which
    // signal handler type is set
    if (![self isDebuggerAttached]) {
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
      
      // set any user defined callbacks, hopefully the users knows what they do
      if (_crashCallBacks) {
        [_plCrashReporter setCrashCallbacks:_crashCallBacks];
      }
      
      // Enable the Crash Reporter
      BOOL crashReporterEnabled = [_plCrashReporter enableCrashReporterAndReturnError:&error];
      if (!crashReporterEnabled)
        NSLog(@"[HockeySDK] WARNING: Could not enable crash reporter: %@", error);
      
      // get the new current top level error handler, which should now be the one from PLCrashReporter
      NSUncaughtExceptionHandler *currentHandler = NSGetUncaughtExceptionHandler();
      
      // do we have a new top level error handler? then we were successful
      if (currentHandler && currentHandler != initialHandler) {
        self.plcrExceptionHandler = currentHandler;
        
        BWQuincyLog(@"INFO: Exception handler successfully initialized.");
      } else {
        // this should never happen, theoretically only if NSSetUncaugtExceptionHandler() has some internal issues
        NSLog(@"[HockeySDK] ERROR: Exception handler could not be set. Make sure there is no other exception handler set up!");
      }
    } else {
      NSLog(@"[HockeySDK] WARNING: Detecting crashes is NOT enabled due to running the app with a debugger attached.");
    }
  }
  
  [self invokeProcessing];
}

// slightly delayed startup processing, so we don't keep the first runloop on startup busy for too long
- (void)invokeDelayedProcessing {
  BWQuincyLog(@"INFO: Start delayed CrashManager processing");
  
  // was our own exception handler successfully added?
  if (self.plcrExceptionHandler) {
    // get the current top level error handler
    NSUncaughtExceptionHandler *currentHandler = NSGetUncaughtExceptionHandler();
    
    // If the top level error handler differs from our own, then at least another one was added.
    // This could cause exception crashes not to be reported to HockeyApp. See log message for details.
    if (self.plcrExceptionHandler != currentHandler) {
      BWQuincyLog(@"WARNING: Another exception handler was added. If this invokes any kind exit() after processing the exception, which causes any subsequent error handler not to be invoked, these crashes will NOT be reported to HockeyApp!");
    }
  }
}

- (void)cancelReport {
  if (self.delegate != nil && [self.delegate respondsToSelector:@selector(quincyManagerWillCancelSendingCrashReport:)]) {
    [self.delegate quincyManagerWillCancelSendingCrashReport:self];
  }
  
  [self cleanCrashReports];
  [self returnToMainApplication];
}

- (void)sendReportWithCrash:(NSString*)crashFile crashDescription:(NSString *)crashDescription {
  // add notes and delegate results to the latest crash report
  
  [self saveSettings];
  
  [_dictOfLastSessionCrash setObject:self.userName forKey:kQuincyMetaUserName];
  [_dictOfLastSessionCrash setObject:self.userEmail forKey:kQuincyMetaUserEmail];
  
  NSString *metaFilename = [NSString stringWithFormat:@"%@.meta", crashFile];
  NSString *errorString = nil;
  NSData *plist = nil;
  
  // if we don't have an application log in the cache dict and do have a meta file, read it from there
  // this might happen if the app got killed while the crash dialog was open and then restarted later again
  if (![_dictOfLastSessionCrash objectForKey:kQuincyMetaApplicationLog] || [(NSString *)[_dictOfLastSessionCrash objectForKey:kQuincyMetaApplicationLog] length] == 0) {
    NSPropertyListFormat format;
    plist = [NSData dataWithContentsOfFile:metaFilename];
    if (plist) {
      NSDictionary *metaDict = (NSDictionary *)[NSPropertyListSerialization
                                                propertyListFromData:plist
                                                mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                                format:&format
                                                errorDescription:&errorString];
      [_dictOfLastSessionCrash setObject:([metaDict objectForKey:kQuincyMetaApplicationLog] ?: @"") forKey:kQuincyMetaApplicationLog];
      if (!crashDescription || [crashDescription length] == 0) {
        crashDescription = [metaDict objectForKey:kQuincyMetaDescription] ?: @"";
      }
    }
  }
  
  [_dictOfLastSessionCrash setObject:(crashDescription ?: @"") forKey:kQuincyMetaDescription];
  
  plist = [NSPropertyListSerialization dataFromPropertyList:(id)_dictOfLastSessionCrash
                                                     format:NSPropertyListBinaryFormat_v1_0
                                           errorDescription:&errorString];
  if (plist) {
    [plist writeToFile:metaFilename atomically:YES];
  } else {
    BWQuincyLog(@"ERROR: Writing crash meta data. %@", errorString);
  }
  
  [self performSendingCrashReports];
}

- (void)performSendingCrashReports {
  NSError *error = NULL;
  
  NSMutableString *crashes = nil;
  _crashIdenticalCurrentVersion = NO;
  
  for (NSUInteger i=0; i < [_crashFiles count]; i++) {
    NSString *filename = [_crashFiles objectAtIndex:i];
    NSData *crashData = [NSData dataWithContentsOfFile:filename];
		
    if ([crashData length] > 0) {
      PLCrashReport *report = [[[PLCrashReport alloc] initWithData:crashData error:&error] autorelease];
			
      if (report == nil) {
        BWQuincyLog(@"ERROR: Could not parse crash report");
        // we cannot do anything with this report, so delete it
        [_fileManager removeItemAtPath:filename error:&error];
        [_fileManager removeItemAtPath:[NSString stringWithFormat:@"%@.meta", filename] error:&error];
        continue;
      }
      
      NSString *crashUUID = @"";
      if (report.uuidRef != NULL) {
        crashUUID = [(NSString *) CFUUIDCreateString(NULL, report.uuidRef) autorelease];
      }
      NSString *installString = [self deviceIdentifier] ?: @"";
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
        NSDictionary *metaDict = nil;
        
        if (i == 0 && _dictOfLastSessionCrash && [_dictOfLastSessionCrash count] > 0) {
          metaDict = _dictOfLastSessionCrash;
        } else {
          metaDict = (NSDictionary *)[NSPropertyListSerialization
                                      propertyListFromData:plist
                                      mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                      format:&format
                                      errorDescription:&errorString];
        }
        
        username = [metaDict objectForKey:kQuincyMetaUserName] ?: @"";
        useremail = [metaDict objectForKey:kQuincyMetaUserEmail] ?: @"";
        userid = [metaDict objectForKey:kQuincyMetaUserID] ?: @"";
        applicationLog = [metaDict objectForKey:kQuincyMetaApplicationLog] ?: @"";
        description = [metaDict objectForKey:kQuincyMetaDescription] ?: @"";
      } else {
        BWQuincyLog(@"ERROR: Reading crash meta data. %@", error);
      }
      
      if ([applicationLog length] > 0) {
        if ([description length] > 0) {
          description = [NSString stringWithFormat:@"%@\n\nLog:\n%@", description, applicationLog];
        } else {
          description = [NSString stringWithFormat:@"Log:\n%@", applicationLog];
        }
      }
      
      [crashes appendFormat:@"<crash><applicationname>%s</applicationname><uuids>%@</uuids><bundleidentifier>%@</bundleidentifier><systemversion>%@</systemversion><senderversion>%@</senderversion><version>%@</version><uuid>%@</uuid><platform>%@</platform><log><![CDATA[%@]]></log><userid>%@</userid><username>%@</username><contact>%@</contact><description><![CDATA[%@]]></description></crash>",
       [[self applicationName] UTF8String],
       [self extractAppUUIDs:report],
       report.applicationInfo.applicationIdentifier,
       report.systemInfo.operatingSystemVersion,
       [self applicationVersion],
       report.applicationInfo.applicationVersion,
       crashUUID,
       [self deviceModel],
       [crashLogString stringByReplacingOccurrencesOfString:@"]]>" withString:@"]]" @"]]><![CDATA[" @">" options:NSLiteralSearch range:NSMakeRange(0,crashLogString.length)],
       userid,
       username,
       useremail,
       [description stringByReplacingOccurrencesOfString:@"]]>" withString:@"]]" @"]]><![CDATA[" @">" options:NSLiteralSearch range:NSMakeRange(0,description.length)]
       ];
      
      // store this crash report as user approved, so if it fails it will retry automatically
      [_approvedCrashReports setObject:[NSNumber numberWithBool:YES] forKey:filename];
    } else {
      // we cannot do anything with this report, so delete it
      [_fileManager removeItemAtPath:filename error:&error];
      [_fileManager removeItemAtPath:[NSString stringWithFormat:@"%@.meta", filename] error:&error];
    }
  }
	
  [self saveSettings];
  // clear cache
  [_dictOfLastSessionCrash removeAllObjects];
  
  if (crashes != nil) {
    [self postXML:[NSString stringWithFormat:@"<crashes>%@</crashes>", crashes]];
  } else {
    [self returnToMainApplication];
  }
}


#pragma mark - Networking

- (void)postXML:(NSString*)xml {
  NSString *boundary = @"----FOO";
  
  if (self.appIdentifier) {
    _request = [[NSMutableURLRequest requestWithURL:
                 [NSURL URLWithString:[NSString stringWithFormat:@"%@api/2/apps/%@/crashes?sdk=%@&sdk_version=%@&feedbackEnabled=no",
                                       self.submissionURL,
                                       [self encodeAppIdentifier],
                                       SDK_NAME,
                                       SDK_VERSION
                                       ]
                  ]] retain];
  } else {
    _request = [[NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.submissionURL]] retain];
  }
  
  [_request setValue:@"Quincy/Mac" forHTTPHeaderField:@"User-Agent"];
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
  
  if (_timeintervalCrashInLastSessionOccured > -1 &&
      _timeintervalCrashInLastSessionOccured <= _maxTimeIntervalOfCrashForReturnMainApplicationDelay) {
    // send synchronously, so any code in applicationDidFinishLaunching after initialization that might have caused the crash, won't be executed before the crash was successfully send.
    BWQuincyLog(@"INFO: Sending crash reports synchronously.");
    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(quincyManagerWillSendCrashReport:)]) {
      [self.delegate quincyManagerWillSendCrashReport:self];
    }
    
    NSData *synchronousResponseData = [NSURLConnection sendSynchronousRequest:_request returningResponse:&response error:&error];
    
    _responseData = [[NSMutableData alloc] initWithData:synchronousResponseData];
    _statusCode = [response statusCode];
    
    [self processServerResult];
  } else {
    
    _responseData = [[NSMutableData alloc] init];
    
    _urlConnection = [[NSURLConnection alloc] initWithRequest:_request delegate:self];
    
    if (!_urlConnection) {
      BWQuincyLog(@"INFO: Sending crash reports could not start!");
      [self returnToMainApplication];
    } else {
      if (self.delegate != nil && [self.delegate respondsToSelector:@selector(quincyManagerWillSendCrashReport:)]) {
        [self.delegate quincyManagerWillSendCrashReport:self];
      }
      
      BWQuincyLog(@"INFO: Returning to main application while sending.");
      [self returnToMainApplication];
    }
  }
}


- (void)processServerResult {
  NSError *error = nil;
  
  if (_statusCode >= 200 && _statusCode < 400 && _responseData != nil && [_responseData length] > 0) {
    [self cleanCrashReports];
    
    // HockeyApp uses PList XML format
    NSMutableDictionary *response = [NSPropertyListSerialization propertyListFromData:_responseData
                                                                     mutabilityOption:NSPropertyListMutableContainersAndLeaves
                                                                               format:nil
                                                                     errorDescription:NULL];
    BWQuincyLog(@"INFO: Received API response: %@", response);
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(quincyManagerDidFinishSendingCrashReport:)]) {
      [self.delegate quincyManagerDidFinishSendingCrashReport:self];
    }
  } else if (_statusCode == 400) {
    [self cleanCrashReports];
    
    error = [NSError errorWithDomain:kBWQuincyErrorDomain
                                code:BWQuincyAPIAppVersionRejected
                            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"The server rejected receiving crash reports for this app version!", NSLocalizedDescriptionKey, nil]];
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(quincyManager:didFailWithError:)]) {
      [self.delegate quincyManager:self didFailWithError:error];
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
                              userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"Sending failed with status code: %i", (int)_statusCode], NSLocalizedDescriptionKey, nil]];
    }
    
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(quincyManager:didFailWithError:)]) {
      [self.delegate quincyManager:self didFailWithError:error];
    }
    
    BWQuincyLog(@"ERROR: %@", [error localizedDescription]);
  }
  
  [_responseData release];
  _responseData = nil;
  
  [self returnToMainApplication];
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
    NSMutableURLRequest *r = [[_request mutableCopy] autorelease];
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
  if (self.delegate != nil && [self.delegate respondsToSelector:@selector(quincyManager:didFailWithError:)]) {
    [self.delegate quincyManager:self didFailWithError:error];
  }
  
  BWQuincyLog(@"ERROR: %@", [error localizedDescription]);
  
  [_responseData release];
  _responseData = nil;
  [_urlConnection release];
  _urlConnection = nil;
  
  [self returnToMainApplication];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  [_urlConnection release];
  _urlConnection = nil;
  
  [self processServerResult];
}


#pragma mark - GetterSetter

- (NSString *)applicationName {
  NSString *applicationName = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleExecutable"];
  
  if (!applicationName)
    applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleExecutable"];
  
  return applicationName;
}


- (NSString *)applicationVersion {
  NSString *string = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleVersion"];
  
  if (!string)
    string = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleVersion"];
  
  return string;
}

@end
