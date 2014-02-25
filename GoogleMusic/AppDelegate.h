//
//  AppDelegate.h
//  GoogleMusic
//
//  Created by James Fator on 5/16/13.
//

#import <Cocoa/Cocoa.h>
#import <IOKit/hidsystem/ev_keymap.h>
#import <WebKit/WebKit.h>

#import "CustomWebView.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, CustomWebViewDelegate>
{
    CFMachPortRef eventTap;
    CFRunLoopSourceRef eventPortSource;
}

@property (assign) IBOutlet NSWindow *window;
@property (nonatomic, retain) IBOutlet CustomWebView *webView;
@property (assign) NSUserDefaults *defaults;
@property (weak) IBOutlet NSButton *loginButton;
@property (weak) IBOutlet NSTextField *usernameField;
@property (weak) IBOutlet NSSecureTextField *passwordField;

- (void) playPause;
- (void) forwardAction;
- (void) backAction;

// Preferences
- (IBAction)initLastFM:(id)sender;

@end
