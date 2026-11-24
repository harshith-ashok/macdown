//
//  MPPreferencesViewController.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPPreferencesViewController.h"
#import "MPPreferences.h"


NSString * const MPDidRequestPreviewRenderNotification =
    @"MPDidRequestPreviewRenderNotificationName";
NSString * const MPDidRequestEditorSetupNotification =
    @"MPDidRequestEditorSetupNotificationName";

static const CGFloat MPPreferencesMinimumWidth = 680.0;

@implementation MPPreferencesViewController

- (id)init
{
    return [self initWithNibName:NSStringFromClass(self.class)
                          bundle:nil];
}

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

- (void)loadView
{
    [super loadView];
    [self centerViewInMinimumWidth];
}

// MASPreferences sizes the window to the pane's view, and the toolbar needs
// room for every pane icon. Panes narrower than that make the toolbar collapse
// into an overflow menu, so every pane is centred in a view of at least this width.
- (void)centerViewInMinimumWidth
{
    NSView *content = self.view;
    CGFloat width = MAX(NSWidth(content.frame), MPPreferencesMinimumWidth);
    NSView *container = [[NSView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, width, NSHeight(content.frame))];
    content.frame = NSMakeRect(round((width - NSWidth(content.frame)) / 2.0),
                               0.0, NSWidth(content.frame),
                               NSHeight(content.frame));
    content.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
    // Make the container the controller's view first: adding the old view to it
    // while it is still the controller's view confuses the responder chain.
    self.view = container;
    [container addSubview:content];
}

@end
