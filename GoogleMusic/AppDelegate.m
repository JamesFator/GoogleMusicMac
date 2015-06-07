//
//  AppDelegate.m
//  GoogleMusic
//
//  Created by James Fator on 5/16/13.
//

#import "AppDelegate.h"
#import "LastFm/LastFm.h"
#import "SSKeychain.h"

#define SESSION_KEY @"lastfm.session"
#define USERNAME_KEY @"lastfm.username"
#define NOTIF_ENABLED_KEY @"notifications.enabled"
#define LASTFM_ENABLED_KEY @"lastfm.enabled"

static NSString *kServiceName = @"GoogleMusicMac";

@implementation AppDelegate

@synthesize webView;
@synthesize window;

// Terminate on window close
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{ return YES; }

/**
 * Set defaults.
 */
+ (void)initialize
{
    // Register default preferences.
    NSString *prefsPath = [[NSBundle mainBundle] pathForResource:@"Preferences" ofType:@"plist"];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:prefs];
}

/**
 * Application finished launching, we will register the event tap callback.
 */
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Load the user preferences.
    _defaults = [NSUserDefaults standardUserDefaults];
    
    // Add an event tap to intercept the system defined media key events
    eventTap = CGEventTapCreate(kCGSessionEventTap,
                                  kCGHeadInsertEventTap,
                                  kCGEventTapOptionDefault,
                                  CGEventMaskBit(NX_SYSDEFINED),
                                  event_tap_callback,
                                  (__bridge void *)(self));
    if (!eventTap) {
        fprintf(stderr, "failed to create event tap\n");
        exit(1);
    }
    // Create a run loop source.
    eventPortSource = CFMachPortCreateRunLoopSource( kCFAllocatorDefault, eventTap, 0 );
    
    // Enable the event tap.
    CGEventTapEnable(eventTap, true);
    
    // Let's do this in a separate thread so that a slow app doesn't lag the event tap
    [NSThread detachNewThreadSelector:@selector(eventTapThread) toTarget:self withObject:nil];
    
    // Load the main page
    [webView setAppDelegate:self];
    [webView setFrameLoadDelegate:self];
    [webView setResourceLoadDelegate:self];
    [[webView preferences] setPlugInsEnabled:YES];
    NSURL *url = [NSURL URLWithString:@"https://play.google.com/music"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [[webView mainFrame] loadRequest:request];
    
    // Initialize LastFm
    [self initLastFM:self];
}

#pragma mark - Event tap methods

/**
 * eventTapThread is the selector that adds the callback thread into the loop.
 */
- (void)eventTapThread;
{
    CFRunLoopRef tapThreadRL = CFRunLoopGetCurrent();
    CFRunLoopAddSource( tapThreadRL, eventPortSource, kCFRunLoopCommonModes );
    CFRunLoopRun();
}

/**
 * event_tap_callback is the event callback that recognizes the keys we want
 *   and launches the assigned commands.
 */
static CGEventRef event_tap_callback(CGEventTapProxy proxy,
                                     CGEventType type,
                                     CGEventRef event,
                                     void *refcon)
{
    AppDelegate *self = (__bridge AppDelegate *)(refcon);
    
    if(type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(self->eventTap, TRUE);
        return event;
    }
    
    if (!(type == NX_SYSDEFINED) || (type == NX_KEYDOWN))
        return event;
    
    NSEvent* keyEvent = [NSEvent eventWithCGEvent: event];
    if (keyEvent.type != NSSystemDefined || keyEvent.subtype != 8) return event;
    
    int keyCode = (([keyEvent data1] & 0xFFFF0000) >> 16);
    int keyFlags = ([keyEvent data1] & 0x0000FFFF);
    int keyState = (((keyFlags & 0xFF00) >> 8)) == 0xA;
    
    ProcessSerialNumber psn;
    GetProcessForPID([[NSProcessInfo processInfo] processIdentifier], &psn);
    
    switch( keyCode )
    {
        case NX_KEYTYPE_PLAY:   // F8
            if( keyState == 0 ) {
                    [self performSelectorOnMainThread:@selector(playPause)
                                       withObject:nil waitUntilDone:NO];
            }
            return NULL;
            
        case NX_KEYTYPE_FAST:   // F9
        case NX_KEYTYPE_NEXT:
            if( keyState == 0 ) {
                    [self performSelectorOnMainThread:@selector(forwardAction)
                                           withObject:nil waitUntilDone:NO];
            }
            return NULL;
            
        case NX_KEYTYPE_REWIND:   // F7
        case NX_KEYTYPE_PREVIOUS:
            if( keyState == 0 ) {
                    [self performSelectorOnMainThread:@selector(backAction)
                                           withObject:nil waitUntilDone:NO];
            }
            return NULL;
    }
    return event;
}

# pragma mark - Play Actions

/**
 * playPause toggles the playing status for the app
 */
- (void)playPause
{
    CGEventRef keyDownEvent = CGEventCreateKeyboardEvent(nil, (CGKeyCode)49, true);
    [window sendEvent:[NSEvent eventWithCGEvent:keyDownEvent]];
    CFRelease(keyDownEvent);
}

/**
 * forwardAction skips track forward
 */
- (void)forwardAction
{
    CGEventRef keyDownEvent = CGEventCreateKeyboardEvent(nil, (CGKeyCode)124, true);
    [window sendEvent:[NSEvent eventWithCGEvent:keyDownEvent]];
    CFRelease(keyDownEvent);
}

/**
 * backAction skips track backwards
 */
- (void)backAction
{
    CGEventRef keyDownEvent = CGEventCreateKeyboardEvent(nil, (CGKeyCode)123, true);
    [window sendEvent:[NSEvent eventWithCGEvent:keyDownEvent]];
    CFRelease(keyDownEvent);
}

# pragma mark - Web Level

/**
 * didFinishLoadForFrame is called when the Web Frame finished loading.
 * We take this time to execute the main.js file
 */
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    [self evaluateJavaScriptFile:@"main"];
    [[sender windowScriptObject] setValue:self forKey:@"googleMusicApp"];
}


- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource
{
    if ([[[request URL] lastPathComponent] isEqualToString:@"webcomponents.js"]) {
        // Load our modified version
        [self evaluateJavaScriptFile:@"webcomponents"];
        // Prevent original request from being made
        return [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://google.com"]];
    } else {
        return request;
    }
}

/**
 * evaluateJavaScriptFile will load the JS file and execute it in the webView.
 */
- (void)evaluateJavaScriptFile:(NSString*)name
{
    NSString *file = [NSString stringWithFormat:@"js/%@", name];
    NSString *path = [[NSBundle mainBundle] pathForResource:file ofType:@"js"];
    NSString *js = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    
    [webView stringByEvaluatingJavaScriptFromString:js];
}

/**
 * notifySong is called when the song is updated. We use this to either
 * bring up a standard OSX notification or a 3rd party notification.
 */
- (void)notifySong:(NSString*)title withArtist:(NSString*)artist
             album:(NSString*)album art:(NSString*)art time:(NSString*)time
{
    // Notification Center
    NSString *songData = [NSString stringWithFormat:@"%@%@%@%@",title,artist,album,time];
    if ([_defaults boolForKey:NOTIF_ENABLED_KEY]) {
        NSUserNotification *notif = [[NSUserNotification alloc] init];
        notif.title = title;
        notif.informativeText = [NSString stringWithFormat:@"%@ — %@", artist, album];
        
        // Try to load the album art if possible.
        if (art) {
            NSURL *url = [NSURL URLWithString:art];
            NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
            
            notif.contentImage = image;
        }
        
        // Remove the previous notifications in order to make this notification appear immediately.
        [[NSUserNotificationCenter defaultUserNotificationCenter] removeAllDeliveredNotifications];
        
        // Deliver the notification.
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notif];
    }
    // Last.fm
    if ([_defaults boolForKey:LASTFM_ENABLED_KEY]) {
        NSTimeInterval duration = 0;
        if (![time isEqualToString:@"Unknown"]) {
            // If we have a time, convert to time interval
            NSArray *timeSplit = [time componentsSeparatedByString:@":"];
            @try {
                duration += [timeSplit[0] intValue] * 60;   // 60 seconds in minute
                duration += [timeSplit[1] intValue];        // seconds
            }
            @catch (NSException *exception) {}
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, duration/2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(),
        ^{
            if ([songData isEqualTo:_songCheck]) {
                // If the song check is the same
                [[LastFm sharedInstance] sendScrobbledTrack:title byArtist:artist
                                                    onAlbum:album withDuration:duration
                                                atTimestamp:(int)[[NSDate date] timeIntervalSince1970]
                                             successHandler:^(NSDictionary *result)
                 {
//                     NSLog(@"result: %@", result);
                 } failureHandler:^(NSError *error) {
//                     NSLog(@"error: %@", error);
                 }];
            }
        });
    }
    _songCheck = songData;
}

/**
 * webScriptNameForSelector will help the JS components access the notify selector.
 */
+ (NSString*)webScriptNameForSelector:(SEL)sel
{
    if (sel == @selector(notifySong:withArtist:album:art:time:))
        return @"notifySong";
    
    return nil;
}

/**
 * isSelectorExcludedFromWebScript will prevent notify from being excluded from script.
 */
+ (BOOL)isSelectorExcludedFromWebScript:(SEL)sel
{
    if (sel == @selector(notifySong:withArtist:album:art:time:))
        return NO;
    
    return YES;
}

# pragma mark - Last.fm

/**
 * initLastFM will start and stop the LastFm sharedInstance and log in if we can.
 */
- (IBAction)initLastFM:(id)sender
{
    if ([_defaults boolForKey:LASTFM_ENABLED_KEY]) {
        // Set the Last.fm session info
        // THESE NEED TO BE REPLACED WITH DEVELOPER API CREDENTIALS
        [LastFm sharedInstance].apiKey = @"xxx";
        [LastFm sharedInstance].apiSecret = @"xxx";
        
        [_loginButton setEnabled:YES];
        [[LastFm sharedInstance] getSessionInfoWithSuccessHandler:^(NSDictionary *result) {
            // Log in if we're already logged in
            [_loginButton setTitle:[NSString stringWithFormat:@"Logout %@", result[@"name"]]];
            [_loginButton setAction:@selector(logout)];
            [self enableLoginForm:NO];
        } failureHandler:^(NSError *error) {
            // No, show login form
            [self enableLoginForm:YES];
            [_loginButton setTitle:@"Login"];
            [_loginButton setAction:@selector(login)];
            [self login];
        }];
    } else {
        [self enableLoginForm:NO];
        [_loginButton setTitle:@"Login"];
        [_loginButton setAction:@selector(login)];
        [_loginButton setEnabled:NO];
        // Remove the securely stored password
        NSString *username = [[NSUserDefaults standardUserDefaults] objectForKey:USERNAME_KEY];
        [SSKeychain deletePasswordForService:kServiceName account:username];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:USERNAME_KEY];
    }
}

/**
 * enableLoginForm will enable/disable the username/password fields.
 * @param hide - whether or not we want to enable the fields
 */
- (void)enableLoginForm:(BOOL)hide
{
    [_usernameField setEnabled:hide];
    [_passwordField setEnabled:hide];
}

/**
 * login will sign the user into LastFm scrobbling.
 */
- (void)login
{
    NSString *username = _usernameField.stringValue;
    NSString *password = _passwordField.stringValue;
    if ([_passwordField.stringValue length] == 0) {
        // Test if saved securely
        username = [[NSUserDefaults standardUserDefaults] objectForKey:USERNAME_KEY];
        if (username) {
            _usernameField.stringValue = username;
            password = [SSKeychain passwordForService:kServiceName account:username];
        } else {
            username = @"";
        }
    }
    [[LastFm sharedInstance] getSessionForUser:username
                                      password:password
                                successHandler:^(NSDictionary *result)
    {
        // Save the session into NSUserDefaults. It is loaded on app start up in AppDelegate.
        [[NSUserDefaults standardUserDefaults] setObject:result[@"key"] forKey:SESSION_KEY];
        [[NSUserDefaults standardUserDefaults] setObject:result[@"name"] forKey:USERNAME_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        // Also set the session of the LastFm object
        [LastFm sharedInstance].session = result[@"key"];
        [LastFm sharedInstance].username = result[@"name"];
        
        // Show the logout button
        [self.loginButton setTitle:[NSString stringWithFormat:@"Logout %@", result[@"name"]]];
        [self.loginButton setAction:@selector(logout)];
        [self enableLoginForm:NO];
        
        // Store the credentials in Keychain securely
        [SSKeychain setPassword:password forService:kServiceName account:username];
    } failureHandler:^(NSError *error) {
        // TODO: Error message
    }];
    // Clear the password
    [_passwordField setStringValue:@""];
}

/**
 * logout will sign the user out of LastFm scrobbling.
 */
- (void)logout
{
    [self enableLoginForm:YES];
    [_loginButton setTitle:@"Login"];
    [_loginButton setAction:@selector(login)];
    [[LastFm sharedInstance] logout];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SESSION_KEY];
    // Remove the securely stored password
    NSString *username = [[NSUserDefaults standardUserDefaults] objectForKey:USERNAME_KEY];
    [SSKeychain deletePasswordForService:kServiceName account:username];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:USERNAME_KEY];
}

@end
