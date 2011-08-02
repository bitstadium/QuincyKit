//
//  BWQuincyUtilities.c
//  QuincyDemo
//
//  Created by Stanley Rost on 31.07.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

NSArray* FindNewCrashFiles();
BOOL hasCrashesTheUserDidNotSeeYet(NSArray *crashFiles, NSString **crashFileContent);
NSString* consoleContent();
int sendCrashReportsToServerAndParseResponse(NSArray *crashReports, NSDictionary* additionalDataByCrashFile, NSString *submissionURL, BOOL isHockeyApp, NSTimeInterval networkTimeoutInterval);
// void processServerResponse(NSUInteger statusCode, NSData* payload, NSArray *crashReports);

void storeCommentForReport(NSString *comment, NSString *report);
void markReportsProcessed(NSArray *listOfReports);


