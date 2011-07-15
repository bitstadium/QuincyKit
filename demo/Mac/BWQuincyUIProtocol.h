//
//  BWQuincyUIProtocol.h
//  QuincyDemo
//
//  Created by Stanley Rost on 15.07.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol BWQuincyUIProtocol <NSObject>

@property (nonatomic, assign) id delegate;
@property (nonatomic, retain) NSString *applicationName;
@property (nonatomic, retain) NSString *companyName;
@property (nonatomic, retain) NSString *crashFileContent;
@property (nonatomic, retain) NSString *consoleContent;

- (void)presentInterface;

@end
