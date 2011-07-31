//
//  BWQuincyUtilities.c
//  QuincyDemo
//
//  Created by Stanley Rost on 31.07.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

NSArray* FindLatestCrashFilesInPath(NSString* path, NSDate *minModifyTimestamp, NSArray *listOfAlreadyProcessedCrashFileNames, NSUInteger limit);
NSArray* FindLatestCrashFiles(NSDate *minModifyTimestamp, NSArray *listOfAlreadyProcessedCrashFileNames, NSUInteger limit);
NSArray* FindNewCrashFiles();
BOOL hasCrashesTheUserDidNotSeeYet(NSArray *crashFiles, NSString **crashFileContent);
NSString* OSVersion();
NSString* applicationName();
NSString* applicationVersionString();
NSString* computerModel();
BOOL parseVersionOfCrashedApplicationFromCrashLog(NSString *crashReportContent, NSString **version, NSString **shortVersion);
NSDictionary* crashLogsContentsByFilename(NSArray *crashLogs);
NSString* consoleContent();
int sendCrashReports(NSArray *crashReports, NSString *submissionURL, NSDictionary *additionalData, BOOL isHockeyApp, NSTimeInterval networkTimeoutInterval);
// void processServerResponse(NSUInteger statusCode, NSData* payload, NSArray *crashReports);

void storeCommentForReport(NSString *comment, NSString *report);
void markReportsProcessed(NSArray *listOfReports);
