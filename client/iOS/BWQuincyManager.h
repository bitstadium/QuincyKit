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

#import <Foundation/Foundation.h>

#import <CrashReporter/CrashReporter.h>
#import "BWQuincyManagerDelegate.h"


// Notification message which QuincyManager is listening to, to retry sending pending crash reports to the server
#define BWQuincyNetworkBecomeReachable @"NetworkDidBecomeReachable"

/**
 Handle crash reports.
 
 Quincy provides functionality for handling crash reports, including when distributed via the App Store.
 As a foundation it is using the open source, reliable and async-safe crash reporting framework
 [PLCrashReporter](https://code.google.com/p/plcrashreporter/).
 
 This module works as a wrapper around the underlying crash reporting framework and provides functionality to
 detect new crashes, queues them if networking is not available, present a user interface to approve sending
 the reports to the HockeyApp servers and more.
 
 It also provides options to add additional meta information to each crash report, like `userName`, `userEmail`,
 and additional textual log via `BWQuincyManagerDelegate` protocol and a way to detect startup crashes so you
 can adjust your startup process to get these crash reports too and delay your app initialization.
 
 Crashes are send the next time the app starts. If `autoSubmitCrashReport` is set to `YES`, crashes will be send
 without any user interaction, otherwise an alert will appear allowing the users to decide whether they want to
 send the report or not. This module is not sending the reports right when the crash happens deliberately,
 because if is not safe to implement such a mechanism while being async-safe (any Objective-C code
 is _NOT_ async-safe!) and not causing more danger like a deadlock of the device, than helping. We found that users
 do start the app again because most don't know what happened, and you will get by far most of the reports.
 
 Sending the reports on startup is done asynchronously (non-blocking). This is the only safe way to ensure
 that the app won't be possibly killed by the iOS watchdog process, because startup could take too long
 and the app could not react to any user input when network conditions are bad or connectivity might be
 very slow.
 
 It is possible to check upon startup if the app crashed before using `didCrashInLastSession` and also how much
 time passed between the app launch and the crash using `timeintervalCrashInLastSessionOccured`. This allows you
 to add additional code to your app delaying the app start until the crash has been successfully send if the crash
 occured within a critical startup timeframe, e.g. after 10 seconds. The `BWQuincyManagerDelegate` protocol provides
 various delegates to inform the app about it's current status so you can continue the remaining app startup setup
 after sending has been completed. The documentation contains a guide
 [How to handle Crashes on startup](HowTo-Handle-Crashes-On-Startup) with an example on how to do that.
 
 More background information on this topic can be found in the following blog post by Landon Fuller, the
 developer of [PLCrashReporter](https://www.plcrashreporter.org), about writing reliable and
 safe crash reporting: [Reliable Crash Reporting](http://goo.gl/WvTBR)
 
 @warning If you start the app with the Xcode debugger attached, detecting crashes will _NOT_ be enabled!
 */
@interface BWQuincyManager : NSObject

#pragma mark - Public Methods

///-----------------------------------------------------------------------------
/// @name Initialization
///-----------------------------------------------------------------------------

+ (BWQuincyManager *)sharedQuincyManager;

/**
 Starts the manager and runs all modules
 
 Call this after configuring the manager and setting up all modules.
 
 @see submissionURL:
 */
- (void)startManager;


#pragma mark - Public Properties

///-----------------------------------------------------------------------------
/// @name Configuration
///-----------------------------------------------------------------------------


/**
 Configure the URL to the QuincyKit Server
 
 @see appIdentifier;
 */
@property (nonatomic, strong) NSString *submissionURL;

/**
 Define the appIdentifier when using HockeyApp.net as a backend

 @see submissionURL;
 */
@property (nonatomic, strong) NSString *appIdentifier;


/**
 Sets the optional `BWQuincyManagerDelegate` delegate.
 */
@property (nonatomic, unsafe_unretained) id <BWQuincyManagerDelegate> delegate;

/**
 Defines if crash reports should be submitted without asking the user
 
 Default: _NO_
 */
@property (nonatomic, assign, getter=shouldAutoSubmitCrashReport) BOOL autoSubmitCrashReport;


/**
 *  Trap fatal signals via a Mach exception server.
 *
 *  By default the SDK is using the safe and proven in-process BSD Signals for catching crashes.
 *  This option provides an option to enable catching fatal signals via a Mach exception server
 *  instead.
 *
 *  We strongly advice _NOT_ to enable Mach exception handler in release versions of your apps!
 *
 *  Default: _NO_
 *
 * @warning The Mach exception handler executes in-process, and will interfere with debuggers when
 *  they attempt to suspend all active threads (which will include the Mach exception handler).
 *  Mach-based handling should _NOT_ be used when a debugger is attached. The SDK will not
 *  enabled catching exceptions if the app is started with the debugger running. If you attach
 *  the debugger during runtime, this may cause issues the Mach exception handler is enabled!
 * @see isDebuggerAttached
 */
@property (nonatomic, assign, getter=isMachExceptionHandlerEnabled) BOOL enableMachExceptionHandler;


/**
 * Set the callbacks that will be executed prior to program termination after a crash has occurred
 *
 * PLCrashReporter provides support for executing an application specified function in the context
 * of the crash reporter's signal handler, after the crash report has been written to disk.
 *
 * Writing code intended for execution inside of a signal handler is exceptionally difficult, and is _NOT_ recommended!
 *
 * _Program Flow and Signal Handlers_
 *
 * When the signal handler is called the normal flow of the program is interrupted, and your program is an unknown state. Locks may be held, the heap may be corrupt (or in the process of being updated), and your signal handler may invoke a function that was being executed at the time of the signal. This may result in deadlocks, data corruption, and program termination.
 *
 * _Async-Safe Functions_
 *
 * A subset of functions are defined to be async-safe by the OS, and are safely callable from within a signal handler. If you do implement a custom post-crash handler, it must be async-safe. A table of POSIX-defined async-safe functions and additional information is available from the CERT programming guide - SIG30-C, see https://www.securecoding.cert.org/confluence/display/seccode/SIG30-C.+Call+only+asynchronous-safe+functions+within+signal+handlers
 *
 * Most notably, the Objective-C runtime itself is not async-safe, and Objective-C may not be used within a signal handler.
 *
 * Documentation taken from PLCrashReporter: https://www.plcrashreporter.org/documentation/api/v1.2-rc2/async_safety.html
 *
 * @param callbacks A pointer to an initialized PLCrashReporterCallback structure, see https://www.plcrashreporter.org/documentation/api/v1.2-rc2/struct_p_l_crash_reporter_callbacks.html
 */
- (void)setCrashCallbacks: (PLCrashReporterCallbacks *) callbacks;


/**
 Flag that determines if an "Always" option should be shown
 
 If enabled the crash reporting alert will also present an "Always" option, so
 the user doesn't have to approve every single crash over and over again.
 
 If If `crashManagerStatus` is set to `BITCrashManagerStatusAutoSend`, this property
 has no effect, since no alert will be presented.
 
 Default: _YES_
 
 @see crashManagerStatus
 */
@property (nonatomic, assign, getter=shouldShowAlwaysButton) BOOL showAlwaysButton;


///-----------------------------------------------------------------------------
/// @name Crash Meta Information
///-----------------------------------------------------------------------------

/** Set the userid that should used in the SDK components
 
 The value is attach to a crash report.
 
 @see userName
 @see userEmail
 */
@property (nonatomic, retain) NSString *userID;


/** Set the user name that should used in the SDK components
 
 The value is attach to a crash report.
 
 @see userID
 @see userEmail
 */
@property (nonatomic, retain) NSString *userName;


/** Set the users email address that should used in the SDK components
 
 The value is attach to a crash report.
 
 @see userID
 @see userName
 */
@property (nonatomic, retain) NSString *userEmail;


/**
 Indicates if the app crash in the previous session
 
 Use this on startup, to check if the app starts the first time after it crashed
 previously. You can use this also to disable specific events, like asking
 the user to rate your app.
 
 @warning This property only has a correct value, once `[BITHockeyManager startManager]` was
 invoked!
 */
@property (nonatomic, readonly) BOOL didCrashInLastSession;


/**
 Provides the time between startup and crash in seconds
 
 Use this in together with `didCrashInLastSession` to detect if the app crashed very
 early after startup. This can be used to delay app initialization until the crash
 report has been sent to the server or if you want to do any other actions like
 cleaning up some cache data etc.
 
 Note that sending a crash reports starts as early as 1.5 seconds after the application
 did finish launching!
 
 The `BITCrashManagerDelegate` protocol provides some delegates to inform if sending
 a crash report was finished successfully, ended in error or was cancelled by the user.
 
 *Default*: _-1_
 @see didCrashInLastSession
 @see BITCrashManagerDelegate
 */
@property (nonatomic, readonly) NSTimeInterval timeintervalCrashInLastSessionOccured;


///-----------------------------------------------------------------------------
/// @name Debug Logging
///-----------------------------------------------------------------------------

/**
 Flag that determines whether additional logging output should be generated
 by the manager and all modules.
 
 This is ignored if the app is running in the App Store and reverts to the
 default value in that case.
 
 *Default*: _NO_
 */
@property (nonatomic, assign, getter=isDebugLogEnabled) BOOL debugLogEnabled;


///-----------------------------------------------------------------------------
/// @name Helper
///-----------------------------------------------------------------------------


/**
 Flag that determines whether the application is installed and running
 from an App Store installation.
 
 Returns _YES_ if the app is installed and running from the App Store
 Returns _NO_ if the app is installed via debug, ad-hoc or enterprise distribution
 */
@property (nonatomic, readonly, getter=isAppStoreEnvironment) BOOL appStoreEnvironment;


/**
 *  Detect if a debugger is attached to the app process
 *
 *  This is only invoked once on app startup and can not detect if the debugger is being
 *  attached during runtime!
 *
 *  @return BOOL if the debugger is attached on app startup
 */
- (BOOL)isDebuggerAttached;


/**
 * Lets the app crash for easy testing of the SDK
 *
 * The best way to use this is to trigger the crash with a button action.
 *
 * Make sure not to let the app crash in `applicationDidFinishLaunching` or any other
 * startup method! Since otherwise the app would crash before the SDK could process it.
 *
 * Note that our SDK provides support for handling crashes that happen early on startup.
 * Check the documentation for more information on how to use this.
 *
 * If the SDK detects an App Store environment, it will _NOT_ cause the app to crash!
 */
- (void)generateTestCrash;


@end
