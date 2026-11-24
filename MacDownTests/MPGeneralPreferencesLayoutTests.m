//
//  MPGeneralPreferencesLayoutTests.m
//  MacDownTests
//

#import <XCTest/XCTest.h>
#import "MPGeneralPreferencesViewController.h"
#import "MPMarkdownPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPHtmlPreferencesViewController.h"
#import "MPFeaturesPreferencesViewController.h"
#import "MPTerminalPreferencesViewController.h"


@interface MPGeneralPreferencesLayoutTests : XCTestCase
@end


static void MPCollectButtons(NSView *view, NSMutableArray<NSButton *> *out)
{
    if ([view isKindOfClass:[NSButton class]])
        [out addObject:(NSButton *)view];
    for (NSView *sub in view.subviews)
        MPCollectButtons(sub, out);
}


@implementation MPGeneralPreferencesLayoutTests

- (void)testGeneralPaneHasNoScrollSyncOptionAndNoOverlap
{
    MPGeneralPreferencesViewController *controller =
        [[MPGeneralPreferencesViewController alloc] init];
    NSView *view = controller.view;
    [view layoutSubtreeIfNeeded];

    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    MPCollectButtons(view, buttons);
    XCTAssertGreaterThan(buttons.count, 0u);

    for (NSButton *button in buttons)
    {
        XCTAssertFalse([button.title.lowercaseString containsString:@"scroll"],
                       @"Scroll syncing is gone; no option for it");
    }

    for (NSUInteger i = 0; i < buttons.count; i++)
    {
        NSRect a = [buttons[i] convertRect:buttons[i].bounds toView:view];
        for (NSUInteger j = i + 1; j < buttons.count; j++)
        {
            NSRect b = [buttons[j] convertRect:buttons[j].bounds toView:view];
            XCTAssertFalse(NSIntersectsRect(NSInsetRect(a, 1, 1),
                                            NSInsetRect(b, 1, 1)),
                           @"'%@' overlaps '%@'", buttons[i].title,
                           buttons[j].title);
        }
    }
}

// Every pane must load without AppKit assertions and be wide enough that the
// toolbar shows all pane icons (a narrow pane collapses it into an overflow menu).
- (void)testEveryPaneLoadsAndIsWideEnoughForTheToolbar
{
    NSArray<NSViewController *> *panes = @[
        [[MPGeneralPreferencesViewController alloc] init],
        [[MPMarkdownPreferencesViewController alloc] init],
        [[MPEditorPreferencesViewController alloc] init],
        [[MPHtmlPreferencesViewController alloc] init],
        [[MPFeaturesPreferencesViewController alloc] init],
        [[MPTerminalPreferencesViewController alloc] init],
    ];
    for (NSViewController *pane in panes)
    {
        NSView *view = pane.view;
        [view layoutSubtreeIfNeeded];
        XCTAssertGreaterThanOrEqual(NSWidth(view.frame), 680.0,
                                    @"%@ is too narrow", NSStringFromClass(pane.class));
        XCTAssertGreaterThan(NSHeight(view.frame), 50.0);
    }
}

@end
