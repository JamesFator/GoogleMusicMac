//
//  AppDelegate.m
//  GoogleMusic
//
//  Created by James Fator on 5/16/13.
//

#import "AppDelegate.h"

@implementation AppDelegate

@synthesize webView;
@synthesize window;

// Terminate on window close
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{ return YES; }

/**
 * Application finished launching, we will register the event tap callback.
 */
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
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
	//Create a run loop source.
	eventPortSource = CFMachPortCreateRunLoopSource( kCFAllocatorDefault, eventTap, 0 );
    
	//Enable the event tap.
    CGEventTapEnable(eventTap, true);
    
    // Let's do this in a separate thread so that a slow app doesn't lag the event tap
    [NSThread detachNewThreadSelector:@selector(eventTapThread) toTarget:self withObject:nil];
    
    // Load the main page
    [webView setAppDelegate:self];
    [[webView preferences] setPlugInsEnabled:YES];
    NSURL *url = [NSURL URLWithString:@"https://play.google.com/music"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [[webView mainFrame] loadRequest:request];
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
    
    OSStatus err = noErr;
    ProcessSerialNumber psn;
    err = GetProcessForPID([[NSProcessInfo processInfo] processIdentifier], &psn);
    
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

#pragma mark - Play Actions

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

@end
