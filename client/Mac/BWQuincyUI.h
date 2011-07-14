@interface BWQuincyUI : NSWindowController
{
  IBOutlet NSTextField *descriptionTextField;
  IBOutlet NSTextView *crashLogTextView;
  
  IBOutlet NSTextField *noteText;
  
  IBOutlet NSButton *showButton;
  IBOutlet NSButton *hideButton;
  IBOutlet NSButton *cancelButton;
  IBOutlet NSButton *submitButton;
  
  id delegate_;
  
  BOOL showComments;
  BOOL showDetails;
}

@property (nonatomic, assign) id delegate;
@property (nonatomic, retain) NSString *applicationName;
@property (nonatomic, retain) NSString *companyName;

- (void) askCrashReportDetails;

- (IBAction)cancelReport:(id)sender;
- (IBAction)submitReport:(id)sender;
- (IBAction)showDetails:(id)sender;
- (IBAction)hideDetails:(id)sender;
- (IBAction)showComments:(id)sender;

- (BOOL)showComments;
- (void)setShowComments:(BOOL)value;

- (BOOL)showDetails;
- (void)setShowDetails:(BOOL)value;

@end