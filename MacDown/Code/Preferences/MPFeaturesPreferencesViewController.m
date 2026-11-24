//
//  MPFeaturesPreferencesViewController.m
//  MacDown
//

#import "MPFeaturesPreferencesViewController.h"
#import "MacDown-Swift.h"


@interface MPFeaturesPreferencesViewController ()
@property (strong) NSPopUpButton *themePopUp;
@property (strong) NSButton *openInTabs;
@property (strong) NSButton *ligatures;
@property (strong) NSButton *lint;
@property (strong) NSButton *git;
@property (strong) NSButton *vegaRemote;
@end


@implementation MPFeaturesPreferencesViewController

static NSString *MPNoThemeTitle()
{
    return NSLocalizedString(@"None (use the CSS style)", @"Theme menu item");
}

#pragma mark - MASPreferencesViewController

- (NSString *)viewIdentifier
{
    return @"FeaturesPreferences";
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:NSImageNameAdvanced];
}

- (NSString *)toolbarItemLabel
{
    return NSLocalizedString(@"Features", @"Preference pane title.");
}

#pragma mark - Layout

- (NSButton *)checkboxWithTitle:(NSString *)title
                          note:(NSString *)note
                        action:(SEL)action
                         stack:(NSStackView *)stack
{
    NSButton *button = [NSButton checkboxWithTitle:title target:self
                                            action:action];
    [stack addArrangedSubview:button];
    if (note)
    {
        NSTextField *label = [NSTextField wrappingLabelWithString:note];
        label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        label.textColor = NSColor.secondaryLabelColor;
        label.preferredMaxLayoutWidth = 380.0;
        NSStackView *row = [NSStackView stackViewWithViews:@[
            [[NSView alloc] init], label]];
        [row.arrangedSubviews[0].widthAnchor constraintEqualToConstant:20.0]
            .active = YES;
        row.alignment = NSLayoutAttributeTop;
        row.spacing = 0.0;
        [stack addArrangedSubview:row];
        [stack setCustomSpacing:14.0 afterView:row];
    }
    return button;
}

- (void)loadView
{
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 4.0;
    stack.edgeInsets = NSEdgeInsetsMake(22.0, 28.0, 22.0, 28.0);

    // Theme.
    NSTextField *themeLabel = [NSTextField labelWithString:
        NSLocalizedString(@"Theme:", @"")];
    self.themePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect
                                                 pullsDown:NO];
    self.themePopUp.target = self;
    self.themePopUp.action = @selector(changeTheme:);
    [self.themePopUp.widthAnchor constraintGreaterThanOrEqualToConstant:200.0]
        .active = YES;
    NSStackView *themeRow = [NSStackView stackViewWithViews:@[
        themeLabel, self.themePopUp]];
    themeRow.spacing = 8.0;
    themeRow.alignment = NSLayoutAttributeCenterY;
    [stack addArrangedSubview:themeRow];
    NSTextField *themeNote = [NSTextField wrappingLabelWithString:
        NSLocalizedString(@"Colours and fonts for the preview, layered on "
                          @"top of the CSS style. Add your own YAML themes to "
                          @"~/.config/macdown/themes.", @"")];
    themeNote.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    themeNote.textColor = NSColor.secondaryLabelColor;
    themeNote.preferredMaxLayoutWidth = 400.0;
    [stack addArrangedSubview:themeNote];
    [stack setCustomSpacing:18.0 afterView:themeNote];

    self.openInTabs = [self checkboxWithTitle:
        NSLocalizedString(@"Open documents in tabs", @"")
        note:NSLocalizedString(@"New documents and files opened from the "
                               @"sidebar join the current window as tabs.",
                               @"")
        action:@selector(toggleOpenInTabs:) stack:stack];

    self.ligatures = [self checkboxWithTitle:
        NSLocalizedString(@"Ligatures in code", @"")
        note:NSLocalizedString(@"Combine characters such as => and != in "
                               @"fonts that support it. Applies to the editor "
                               @"and to code in the preview.", @"")
        action:@selector(toggleLigatures:) stack:stack];

    self.lint = [self checkboxWithTitle:
        NSLocalizedString(@"Check Markdown while typing (lint)", @"")
        note:NSLocalizedString(@"Underlines heading jumps, duplicate headings, "
                               @"broken local links, missing image text and "
                               @"more. The warning count shows under the "
                               @"window title.", @"")
        action:@selector(toggleLint:) stack:stack];

    self.git = [self checkboxWithTitle:
        NSLocalizedString(@"Show the git branch", @"")
        note:NSLocalizedString(@"Shows the branch of the folder a document is "
                               @"in, under the window title. Uses the git "
                               @"installed on this Mac.", @"")
        action:@selector(toggleGit:) stack:stack];

    self.vegaRemote = [self checkboxWithTitle:
        NSLocalizedString(@"Let Vega-Lite charts load data from the web", @"")
        note:NSLocalizedString(@"Off: charts can only use data written in "
                               @"the document or in local files.", @"")
        action:@selector(toggleVegaRemote:) stack:stack];

    [stack layoutSubtreeIfNeeded];
    NSSize size = stack.fittingSize;
    NSView *view = [[NSView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, size.width, size.height)];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
    ]];
    self.view = view;
    [self centerViewInMinimumWidth];
}

#pragma mark - Override

- (void)viewWillAppear
{
    [self.themePopUp removeAllItems];
    [self.themePopUp addItemWithTitle:MPNoThemeTitle()];
    [self.themePopUp.menu addItem:[NSMenuItem separatorItem]];
    [self.themePopUp addItemsWithTitles:MPFeatureSettings.availableThemeNames];
    NSString *current = MPFeatureSettings.themeName;
    if (current.length)
        [self.themePopUp selectItemWithTitle:current];

    self.openInTabs.state = MPFeatureSettings.openInTabs
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.ligatures.state = MPFeatureSettings.ligatures
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.lint.state = MPFeatureSettings.lintEnabled
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.git.state = MPFeatureSettings.gitEnabled
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.vegaRemote.state = MPFeatureSettings.vegaLiteRemoteData
        ? NSControlStateValueOn : NSControlStateValueOff;
}

#pragma mark - Actions

- (void)changeTheme:(NSPopUpButton *)sender
{
    NSString *title = sender.selectedItem.title;
    MPFeatureSettings.themeName =
        [title isEqualToString:MPNoThemeTitle()] ? nil : title;
}

- (void)toggleOpenInTabs:(NSButton *)sender
{
    MPFeatureSettings.openInTabs = sender.state == NSControlStateValueOn;
}

- (void)toggleLigatures:(NSButton *)sender
{
    MPFeatureSettings.ligatures = sender.state == NSControlStateValueOn;
}

- (void)toggleLint:(NSButton *)sender
{
    MPFeatureSettings.lintEnabled = sender.state == NSControlStateValueOn;
}

- (void)toggleGit:(NSButton *)sender
{
    MPFeatureSettings.gitEnabled = sender.state == NSControlStateValueOn;
}

- (void)toggleVegaRemote:(NSButton *)sender
{
    MPFeatureSettings.vegaLiteRemoteData = sender.state == NSControlStateValueOn;
}

@end
