/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
 *
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
#import <sys/sysctl.h>
#import <CrashReporter/CrashReporter.h>

@interface BWQuincyManager(private)
- (void) startManager;
- (void) handleCrashReport;

- (void) _postXML:(NSString*)xml toURL:(NSURL*)url;
- (void) searchCrashLogFile:(NSString *)path;
- (BOOL) hasPendingCrashReport;
- (void) returnToMainApplication;
@end

@interface BWQuincyUI(private)
- (void) askCrashReportDetails;
- (void) endCrashReporter;
@end

const CGFloat kCommentsHeight = 105;
const CGFloat kDetailsHeight = 285;

@implementation BWQuincyManager

@synthesize delegate = _delegate;
@synthesize submissionURL = _submissionURL;
@synthesize companyName = _companyName;
@synthesize appIdentifier = _appIdentifier;

+ (BWQuincyManager *)sharedQuincyManager {
	static BWQuincyManager *quincyManager = nil;
	
	if (quincyManager == nil) {
		quincyManager = [[BWQuincyManager alloc] init];
	}
	
	return quincyManager;
}

- (id) init {
    if ((self = [super init])) {
		_serverResult = CrashReportStatusFailureDatabaseNotAvailable;
		_quincyUI = nil;
        
		_submissionURL = nil;
        _appIdentifier = nil;
        
		self.delegate = nil;
		self.companyName = @"";
		
		_crashFiles = [[NSMutableArray alloc] init];
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
		_crashesDir = [[NSString stringWithFormat:@"%@", [[paths objectAtIndex:0] stringByAppendingPathComponent:@"/crashes/"]] retain];
		
		NSFileManager *fm = [NSFileManager defaultManager];
		
		if (![fm fileExistsAtPath:_crashesDir]) {
			NSDictionary *attributes = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedLong: 0755] forKey: NSFilePosixPermissions];
			NSError *theError = NULL;
			
			[fm createDirectoryAtPath:_crashesDir withIntermediateDirectories: YES attributes: attributes error: &theError];
		}
		
		PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
		NSError *error = NULL;
		
		// Check if we previously crashed
		if ([crashReporter hasPendingCrashReport]) {
			[self handleCrashReport];
		}
		
		// Enable the Crash Reporter
		if (![crashReporter enableCrashReporterAndReturnError: &error])
			NSLog(@"Warning: Could not enable crash reporter: %@", error);
		
	}
	return self;
}

- (void)dealloc {
	_companyName = nil;
	_delegate = nil;
	_submissionURL = nil;
    _appIdentifier = nil;
    
    [_crashFiles release];
    [_crashesDir release];
	[_quincyUI release];
	
	[super dealloc];
}


#pragma mark -
#pragma mark setter
- (void)setSubmissionURL:(NSString *)anSubmissionURL {
    if (_submissionURL != anSubmissionURL) {
        [_submissionURL release];
        _submissionURL = [anSubmissionURL copy];
    }
    
    [self performSelector:@selector(startManager) withObject:nil afterDelay:0.1f];
}

- (void)setAppIdentifier:(NSString *)anAppIdentifier {    
    if (_appIdentifier != anAppIdentifier) {
        [_appIdentifier release];
        _appIdentifier = [anAppIdentifier copy];
    }
    
    [self setSubmissionURL:@"https://rink.hockeyapp.net/"];
}

#pragma mark -
#pragma mark GetCrashData

- (BOOL) hasPendingCrashReport {
	NSFileManager *fm = [NSFileManager defaultManager];
	
	if ([_crashFiles count] == 0 && [fm fileExistsAtPath: _crashesDir]) {
		NSString *file = nil;
		NSError *error = NULL;
		
		NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath: _crashesDir];
		
		while ((file = [dirEnum nextObject])) {
			NSDictionary *fileAttributes = [fm attributesOfItemAtPath:[_crashesDir stringByAppendingPathComponent:file] error:&error];
			if ([[fileAttributes objectForKey:NSFileSize] intValue] > 0) {
				[_crashFiles addObject:file];
			}
		}
	}
	
	if ([_crashFiles count] > 0) {
		return YES;
	} else
		return NO;
}

- (void) returnToMainApplication {
	if ( self.delegate != nil && [self.delegate respondsToSelector:@selector(showMainApplicationWindow)])
		[self.delegate showMainApplicationWindow];
}

- (void) startManager {
    if ([self hasPendingCrashReport]) {
        
        _quincyUI = [[BWQuincyUI alloc] init:self crashFile:[_crashesDir stringByAppendingPathComponent: [_crashFiles objectAtIndex: 0]] companyName:_companyName applicationName:[self applicationName]];
        [_quincyUI askCrashReportDetails];
    } else {
        [self returnToMainApplication];
    }
}

- (NSString*) modelVersion {
    NSString * modelString  = nil;
    int        modelInfo[2] = { CTL_HW, HW_MODEL };
    size_t     modelSize;
	
    if (sysctl(modelInfo,
               2,
               NULL,
               &modelSize,
               NULL, 0) == 0) {
        void * modelData = malloc(modelSize);
        
        if (modelData) {
            if (sysctl(modelInfo,
                       2,
                       modelData,
                       &modelSize,
                       NULL, 0) == 0) {
                modelString = [NSString stringWithUTF8String:modelData];
            }
            
            free(modelData);
        }
    }
    
    return modelString;
}



- (void) cancelReport {
    [self returnToMainApplication];
}


- (void) sendReport:(NSString *)xml {
    [self returnToMainApplication];
	
    [self _postXML:[NSString stringWithFormat:@"<crashes>%@</crashes>", xml]
             toURL:[NSURL URLWithString:self.submissionURL]];
}

- (void)_postXML:(NSString*)xml toURL:(NSURL*)url {
	NSMutableURLRequest *request = nil;
    NSString *boundary = @"----FOO";

    if (self.appIdentifier) {
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@api/2/apps/%@/crashes",
                                                                            self.submissionURL,
                                                                            [self.appIdentifier stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
                                                                            ]
                                                       ]];
    } else {
        request = [NSMutableURLRequest requestWithURL:url];
    }
	
	[request setValue:@"Quincy/Mac" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
	[request setTimeoutInterval: 15];
	[request setHTTPMethod:@"POST"];
	NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
	[request setValue:contentType forHTTPHeaderField:@"Content-type"];
	
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
	[request setHTTPBody:postBody];
    
	_serverResult = CrashReportStatusUnknown;
	_statusCode = 200;
	
	NSHTTPURLResponse *response = nil;
	NSError *error = nil;
	
	NSData *responseData = nil;
	responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	_statusCode = [response statusCode];

	if (responseData != nil) {
		if (_statusCode >= 200 && _statusCode < 400) {
			NSXMLParser *parser = [[NSXMLParser alloc] initWithData:responseData];
			// Set self as the delegate of the parser so that it will receive the parser delegate methods callbacks.
			[parser setDelegate:self];
			// Depending on the XML document you're parsing, you may want to enable these features of NSXMLParser.
			[parser setShouldProcessNamespaces:NO];
			[parser setShouldReportNamespacePrefixes:NO];
			[parser setShouldResolveExternalEntities:NO];
			
			[parser parse];
			
			[parser release];
		}
	}
}


#pragma mark NSXMLParser

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict {
	if (qName) {
		elementName = qName;
	}
	
	if ([elementName isEqualToString:@"result"]) {
		_contentOfProperty = [NSMutableString string];
	}
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
	if (qName) {
		elementName = qName;
	}
	
	if ([elementName isEqualToString:@"result"]) {
		if ([_contentOfProperty intValue] > _serverResult) {
			_serverResult = [_contentOfProperty intValue];
		}
	}
}


- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
	if (_contentOfProperty) {
		// If the current element is one whose content we care about, append 'string'
		// to the property that holds the content of the current element.
		if (string != nil) {
			[_contentOfProperty appendString:string];
		}
	}
}


#pragma mark GetterSetter

- (NSString *) applicationName {
	NSString *applicationName = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleExecutable"];
	
	if (!applicationName)
		applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleExecutable"];
	
	return applicationName;
}


- (NSString*) applicationVersionString {
	NSString* string = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleShortVersionString"];
	
	if (!string)
		string = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleShortVersionString"];
	
	return string;
}

- (NSString *) applicationVersion {
	NSString* string = [[[NSBundle mainBundle] localizedInfoDictionary] valueForKey: @"CFBundleVersion"];
	
	if (!string)
		string = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleVersion"];
	
	return string;
}

#pragma mark PLCrashReporter

//
// Called to handle a pending crash report.
//
- (void)handleCrashReport {
	PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
	NSError *error = NULL;
	
	// Try loading the crash report
	NSData *crashData = [[NSData alloc] initWithData:[crashReporter loadPendingCrashReportDataAndReturnError: &error]];
	NSString *cacheFilename = [NSString stringWithFormat: @"%.0f", [NSDate timeIntervalSinceReferenceDate]];
	
	if (crashData == nil) {
		NSLog(@"Could not load crash report: %@", error);
	} else {
		[crashData writeToFile:[_crashesDir stringByAppendingPathComponent: cacheFilename] atomically:YES];
	}
	
	// Purge the report
	[crashReporter purgePendingCrashReport];
}

@end




@implementation BWQuincyUI

- (id)init:(id)delegate crashFile:(NSString *)crashFile companyName:(NSString *)companyName applicationName:(NSString *)applicationName {
	
	self = [super initWithWindowNibName: @"BWQuincyMain"];
	
	if ( self != nil) {
		_xml = nil;
		_delegate = delegate;
		_crashFile = crashFile;
		_companyName = companyName;
		_applicationName = applicationName;
		[self setShowComments: YES];
		[self setShowDetails: NO];
	}
	return self;	
}


- (void) endCrashReporter {
	[self close];
}


- (IBAction) showComments: (id) sender {
	NSRect windowFrame = [[self window] frame];
	
	if ([sender intValue]) {
		[self setShowComments: NO];
		
		windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height + kCommentsHeight);
        windowFrame.origin.y -= kCommentsHeight;
		[[self window] setFrame: windowFrame
						display: YES
						animate: YES];
		
		[self setShowComments: YES];
	} else {
		[self setShowComments: NO];
		
		windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height - kCommentsHeight);
        windowFrame.origin.y += kCommentsHeight;
		[[self window] setFrame: windowFrame
						display: YES
						animate: YES];
	}
}


- (IBAction) showDetails:(id)sender {
	NSRect windowFrame = [[self window] frame];

	windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height + kDetailsHeight);
    windowFrame.origin.y -= kDetailsHeight;
	[[self window] setFrame: windowFrame
					display: YES
					animate: YES];
	
	[self setShowDetails:YES];

}


- (IBAction) hideDetails:(id)sender {
	NSRect windowFrame = [[self window] frame];

	[self setShowDetails:NO];

	windowFrame.size = NSMakeSize(windowFrame.size.width, windowFrame.size.height - kDetailsHeight);
    windowFrame.origin.y += kDetailsHeight;
	[[self window] setFrame: windowFrame
					display: YES
					animate: YES];
}


- (IBAction) cancelReport:(id)sender {
	[self endCrashReporter];
	[NSApp stopModal];
	
	if ( _delegate != nil && [_delegate respondsToSelector:@selector(cancelReport)])
		[_delegate cancelReport];
}


- (IBAction) submitReport:(id)sender {
	[submitButton setEnabled:NO];
	
	[[self window] makeFirstResponder: nil];
	
	NSString *userid = @"";
	NSString *contact = @"";
	
	NSString *notes = [NSString stringWithFormat:@"Comments:\n%@\n\nConsole:\n%@", [descriptionTextField stringValue], _consoleContent];	
	
	SInt32 versionMajor, versionMinor, versionBugFix;
	if (Gestalt(gestaltSystemVersionMajor, &versionMajor) != noErr) versionMajor = 0;
	if (Gestalt(gestaltSystemVersionMinor, &versionMinor) != noErr)  versionMinor= 0;
	if (Gestalt(gestaltSystemVersionBugFix, &versionBugFix) != noErr) versionBugFix = 0;
	
	_xml = [[NSString stringWithFormat:@"<crash><applicationname>%s</applicationname><bundleidentifier>%s</bundleidentifier><systemversion>%@</systemversion><senderversion>%@</senderversion><version>%@</version><platform>%@</platform><userid>%@</userid><contact>%@</contact><description><![CDATA[%@]]></description><log><![CDATA[%@]]></log></crash>",
			[[_delegate applicationName] UTF8String],
			[[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"] UTF8String],
			[NSString stringWithFormat:@"%i.%i.%i", versionMajor, versionMinor, versionBugFix],
			[_delegate applicationVersion],
			[_delegate applicationVersion],
			[_delegate modelVersion],
			userid,
			contact,
			notes,
			_crashLogContent
			] retain];
	
	[self endCrashReporter];
	[NSApp stopModal];
	
	if ( _delegate != nil && [_delegate respondsToSelector:@selector(sendReport:)])
        [_delegate performSelector:@selector(sendReport:) withObject:_xml afterDelay:0.01];
}


- (void) askCrashReportDetails {
	NSError *error;
	
	[[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"Problem Report for %@", @"Window title"), _applicationName]];

	[[descriptionTextField cell] setPlaceholderString:NSLocalizedString(@"Please describe any steps needed to trigger the problem", @"User description placeholder")];
	[noteText setStringValue:NSLocalizedString(@"No personal information will be sent with this report.", @"Note text")];

	// get the crash log
	NSData *crashData = [NSData dataWithContentsOfFile: _crashFile];
	PLCrashReport *report = [[[PLCrashReport alloc] initWithData:crashData error:&error] autorelease];
	_crashLogContent = [PLCrashReportTextFormatter stringValueForCrashReport:report withTextFormat:PLCrashReportTextFormatiOS];
	
	// get the console log
	NSEnumerator *theEnum = [[[NSString stringWithContentsOfFile:@"/private/var/log/system.log" encoding:NSUTF8StringEncoding error:&error] componentsSeparatedByString: @"\n"] objectEnumerator];
	NSString* currentObject;
	NSMutableArray* applicationStrings = [NSMutableArray array];
	
	NSString* searchString = [[_delegate applicationName] stringByAppendingString:@"["];
	while ( (currentObject = [theEnum nextObject]) )
	{
		if ([currentObject rangeOfString:searchString].location != NSNotFound)
			[applicationStrings addObject: currentObject];
	}
	
	_consoleContent = [NSMutableString string];
	
    NSInteger i;
    for(i = ((NSInteger)[applicationStrings count])-1; (i>=0 && i>((NSInteger)[applicationStrings count])-100); i--) {
		[_consoleContent appendString:[applicationStrings objectAtIndex:i]];
		[_consoleContent appendString:@"\n"];
	}
	
    // Now limit the content to CRASHREPORTSENDER_MAX_CONSOLE_SIZE (default: 50kByte)
    if ([_consoleContent length] > CRASHREPORTSENDER_MAX_CONSOLE_SIZE)
    {
        _consoleContent = (NSMutableString *)[_consoleContent substringWithRange:NSMakeRange([_consoleContent length]-CRASHREPORTSENDER_MAX_CONSOLE_SIZE-1, CRASHREPORTSENDER_MAX_CONSOLE_SIZE)]; 
    }
        
	[crashLogTextView setString:[NSString stringWithFormat:@"%@\n\n%@", _crashLogContent, _consoleContent]];


	NSBeep();
	[NSApp runModalForWindow:[self window]];
}


- (void)dealloc {
	_companyName = nil;
	_delegate = nil;
	
	[super dealloc];
}


- (BOOL)showComments {
	return showComments;
}


- (void)setShowComments:(BOOL)value {
	showComments = value;
}


- (BOOL)showDetails {
	return showDetails;
}


- (void)setShowDetails:(BOOL)value {
	showDetails = value;
}

#pragma mark NSTextField Delegate

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    BOOL commandHandled = NO;
    
    if (commandSelector == @selector(insertNewline:)) {
        [textView insertNewlineIgnoringFieldEditor:self];
        commandHandled = YES;
    }
    
    return commandHandled;
}

@end

