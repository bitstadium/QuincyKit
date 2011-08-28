//
//  BWQuincyUtilities.c
//  QuincyDemo
//
//  Created by Stanley Rost on 31.07.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

NSArray* FindNewCrashFiles(NSDate* lastCrashDate, NSArray* listOfAlreadyProcessedCrashFileNames, int limit);
BOOL hasCrashesTheUserDidNotSeeYet(NSArray *crashFiles, NSString **crashFileContent);
NSString* consoleContent();

int sendCrashReportsToServerAndParseResponse(
                                             NSArray *crashReports,
                                             NSDictionary* additionalDataByCrashFile,
                                             NSString *submissionURL,
                                             BOOL isHockeyApp,
                                             NSTimeInterval networkTimeoutInterval,
                                             NSString **crashId,
                                             NSTimeInterval *feedbackDelay);

NSDictionary* contentsOfCrashReportsByFileName(NSArray *crashLogs);
BOOL parseVersionOfCrashedApplicationFromCrashLog(NSString *crashReportContent, NSString **version, NSString **shortVersion);
void storeCommentForReport(NSString *comment, NSString *report);
void markReportsProcessed(NSArray *listOfReports);
int checkForFeedbackStatus(NSString *url, NSTimeInterval networkTimeoutInterval);

