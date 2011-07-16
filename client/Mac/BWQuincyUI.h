
#import "BWQuincyUIDelegate.h"

#define BWQuincyLocalize(StringToken) NSLocalizedStringFromTable(StringToken, @"Quincy", @"")

@interface BWQuincyUI : NSWindowController <BWQuincyUIDelegate>
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

- (IBAction)cancelReport:(id)sender;
- (IBAction)submitReport:(id)sender;
- (IBAction)showDetails:(id)sender;
- (IBAction)hideDetails:(id)sender;
- (IBAction)showComments:(id)sender;

- (BOOL)showComments;
- (void)setShowComments:(BOOL)value;

- (BOOL)showDetails;
- (void)setShowDetails:(BOOL)value;

@property (nonatomic, assign) id delegate;
@property (nonatomic, retain) NSString *companyName;
@property (nonatomic, retain) NSString *applicationName;
@property (nonatomic, assign) BOOL shouldPresentModal;

@end