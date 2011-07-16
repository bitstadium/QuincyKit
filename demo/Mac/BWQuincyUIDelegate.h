//
//  BWQuincyUIDelegate.h
//  QuincyDemo
//
//  Created by Stanley Rost on 15.07.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BWQuincyServerAPI.h"

@protocol BWQuincyUIDelegate <NSObject>

- (void)presentQuincyCrashSubmitInterfaceWithCrash:(NSString *)crashFileContent
                                           console:(NSString *)consoleContent;

- (void)presentQuincyServerFeedbackInterface:(CrashReportStatus)status;

@end
