//
//  CatchingWindow.m
//  QuincyDemo
//
//  Created by Max Seelemann on 02.11.11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "CatchingWindow.h"

@implementation CatchingWindow

- (void)sendEvent:(NSEvent *)theEvent
{
	@try {
		[super sendEvent: theEvent];
	}
	@catch (NSException *exception) {
		(NSGetUncaughtExceptionHandler())(exception);
	}
}

@end
