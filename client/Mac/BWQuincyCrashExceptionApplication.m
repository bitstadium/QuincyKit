/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *
 * Copyright (c) 2012-2014 HockeyApp, Bit Stadium GmbH.
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

#import "BWQuincyCrashExceptionApplication.h"

#import <sys/sysctl.h>

#import "BWQuincyManager.h"
#import "BWQuincyManagerPrivate.h"


@implementation BWQuincyCrashExceptionApplication

/*
 * Solution for Scenario 2
 *
 * Catch all exceptions that are being logged to the console and forward them to our
 * custom UncaughtExceptionHandler
 */
- (void)reportException:(NSException *)exception {
  [super reportException: exception];
  
  // Don't invoke the registered UncaughtExceptionHandler if we are currently debugging this app!
  if (![[BWQuincyManager sharedQuincyManager] isDebuggerAttached]) {
    // We forward this exception to PLCrashReporters UncaughtExceptionHandler
    // If the developer has implemented their own exception handler and that one is
    // invoked before PLCrashReporters exception handler and the developers
    // exception handler is invoking this method it will not finish it's tasks after this
    // call but directly jump into PLCrashReporters exception handler.
    // If we wouldn't do this, this call would lead to an infinite loop.
    
    NSUncaughtExceptionHandler *plcrExceptionHandler = [[BWQuincyManager sharedQuincyManager] plcrExceptionHandler];
    if (plcrExceptionHandler && exception) {
      plcrExceptionHandler(exception);
    }
  }
}

/*
 * Solution for Scenario 3
 *
 * Exceptions that happen inside an IBAction implementation do not trigger a call to
 * [NSApp reportException:] and it does not trigger a registered UncaughtExceptionHandler
 * Hence we need to catch these ourselves, e.g. by overwriting sendEvent: as done right here
 *
 * On 64bit systems the @try @catch block doesn't even cost any performance.
 */
- (void)sendEvent:(NSEvent *)theEvent {
  @try {
    [super sendEvent:theEvent];
  } @catch (NSException *exception) {
    // Don't invoke the registered UncaughtExceptionHandler if we are currently debugging this app!
    if (![[BWQuincyManager sharedQuincyManager] isDebuggerAttached]) {
      // We forward this exception to PLCrashReporters UncaughtExceptionHandler only
      NSUncaughtExceptionHandler *plcrExceptionHandler = [[BWQuincyManager sharedQuincyManager] plcrExceptionHandler];
      if (plcrExceptionHandler && exception) {
        plcrExceptionHandler(exception);
      }
    }
  }
}

@end
