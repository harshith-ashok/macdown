//
//  MPHtmlPreferencesViewController.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 8/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPHtmlPreferencesViewController.h"
#import "MPUtilities.h"
#import "MPPreferences.h"


NS_INLINE NSString *MPPrismDefaultThemeName()
{
    return NSLocalizedString(@"(Default)", @"Prism theme title");
}


@interface MPHtmlPreferencesViewController ()
@property (strong) NSPopUpButton *stylesheetSelect;
@property (strong) NSSegmentedControl *stylesheetFunctions;
@property (strong) NSPopUpButton *highlightingThemeSelect;
@end


@implementation MPHtmlPreferencesViewController

#pragma mark - MASPreferencesViewController

- (NSString *)viewIdentifier
{
    return @"HtmlPreferences";
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:@"PreferencesRendering"];
}

- (NSString *)toolbarItemLabel
{
    return NSLocalizedString(@"Rendering", @"Preference pane title.");
}


#pragma mark - Override

// The layout is built in code (the old nib used hard-coded 2015 control sizes,
// so rows overlapped with current system controls).
static const CGFloat kLabelWidth = 100.0;
static const CGFloat kIndent = 22.0;

- (NSStackView *)rowWithViews:(NSArray *)views indent:(CGFloat)indent
{
    NSMutableArray *all = [NSMutableArray array];
    if (indent > 0.0)
    {
        NSView *spacer = [[NSView alloc] init];
        [spacer.widthAnchor constraintEqualToConstant:indent].active = YES;
        [all addObject:spacer];
    }
    [all addObjectsFromArray:views];
    NSStackView *row = [NSStackView stackViewWithViews:all];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8.0;
    return row;
}

- (NSTextField *)labelWithTitle:(NSString *)title
{
    NSTextField *label = [NSTextField labelWithString:title];
    label.alignment = NSTextAlignmentRight;
    [label.widthAnchor constraintEqualToConstant:kLabelWidth].active = YES;
    return label;
}

- (NSButton *)checkboxWithTitle:(NSString *)title
                        valuePath:(NSString *)valuePath
                      enabledPath:(NSString *)enabledPath
{
    NSButton *button = [NSButton checkboxWithTitle:title target:nil action:nil];
    [button bind:NSValueBinding toObject:self
     withKeyPath:valuePath options:nil];
    if (enabledPath)
    {
        [button bind:NSEnabledBinding toObject:self
         withKeyPath:enabledPath options:nil];
    }
    return button;
}

- (void)loadView
{
    NSString *highlight = @"preferences.htmlSyntaxHighlighting";

    // Stylesheet row.
    NSPopUpButton *css = [[NSPopUpButton alloc] initWithFrame:NSZeroRect
                                                    pullsDown:NO];
    css.target = self;
    css.action = @selector(changeStylesheet:);
    [css.widthAnchor constraintGreaterThanOrEqualToConstant:200.0].active = YES;
    self.stylesheetSelect = css;

    NSSegmentedControl *functions = [NSSegmentedControl
        segmentedControlWithLabels:@[
            NSLocalizedString(@"Reveal", @"Stylesheet function"),
            NSLocalizedString(@"Reload", @"Stylesheet function"),
        ]
        trackingMode:NSSegmentSwitchTrackingMomentary
        target:self action:@selector(invokeStylesheetFunction:)];
    self.stylesheetFunctions = functions;

    // Code block rows.
    NSPopUpButton *theme = [[NSPopUpButton alloc] initWithFrame:NSZeroRect
                                                      pullsDown:NO];
    theme.target = self;
    theme.action = @selector(changeHighlightingTheme:);
    [theme.widthAnchor constraintGreaterThanOrEqualToConstant:200.0].active = YES;
    [theme bind:NSEnabledBinding toObject:self withKeyPath:highlight options:nil];
    self.highlightingThemeSelect = theme;

    NSPopUpButton *accessory = [[NSPopUpButton alloc] initWithFrame:NSZeroRect
                                                          pullsDown:NO];
    [accessory addItemsWithTitles:@[
        NSLocalizedString(@"None", @"Code block accessory"),
        NSLocalizedString(@"Language name", @"Code block accessory"),
        NSLocalizedString(@"Custom", @"Code block accessory"),
    ]];
    [accessory.widthAnchor constraintGreaterThanOrEqualToConstant:200.0].active = YES;
    [accessory bind:NSSelectedIndexBinding toObject:self
        withKeyPath:@"preferences.htmlCodeBlockAccessory" options:nil];
    [accessory bind:NSEnabledBinding toObject:self
        withKeyPath:highlight options:nil];

    NSPathControl *path = [[NSPathControl alloc] init];
    path.pathStyle = NSPathStylePopUp;
    path.allowedTypes = @[@"public.folder"];
    path.editable = YES;
    [path.widthAnchor constraintGreaterThanOrEqualToConstant:260.0].active = YES;
    [path bind:NSValueBinding toObject:self
   withKeyPath:@"preferences.htmlDefaultDirectoryUrl" options:nil];

    NSArray *rows = @[
        [self rowWithViews:@[
            [self labelWithTitle:NSLocalizedString(@"CSS:", @"")], css,
            functions] indent:0.0],
        [self checkboxWithTitle:NSLocalizedString(
            @"Syntax highlighted code block", @"")
                      valuePath:highlight enabledPath:nil],
        [self rowWithViews:@[
            [self labelWithTitle:NSLocalizedString(@"Theme:", @"")], theme]
                    indent:kIndent],
        [self rowWithViews:@[
            [self labelWithTitle:NSLocalizedString(@"Accessory:", @"")],
            accessory] indent:kIndent],
        [self rowWithViews:@[
            [self checkboxWithTitle:NSLocalizedString(@"Show line numbers", @"")
                          valuePath:@"preferences.htmlLineNumbers"
                        enabledPath:highlight]] indent:kIndent],
        [self rowWithViews:@[
            [self checkboxWithTitle:NSLocalizedString(@"Mermaid", @"")
                          valuePath:@"preferences.htmlMermaid"
                        enabledPath:highlight]] indent:kIndent],
        [self checkboxWithTitle:NSLocalizedString(@"TeX-like math syntax", @"")
                      valuePath:@"preferences.htmlMathJax" enabledPath:nil],
        [self rowWithViews:@[
            [self checkboxWithTitle:NSLocalizedString(
                @"Use dollar sign ($) as inline delimiter", @"")
                          valuePath:@"preferences.htmlMathJaxInlineDollar"
                        enabledPath:@"preferences.htmlMathJax"]]
                    indent:kIndent],
        [self checkboxWithTitle:NSLocalizedString(@"Task list syntax", @"")
                      valuePath:@"preferences.htmlTaskList" enabledPath:nil],
        [self checkboxWithTitle:NSLocalizedString(
            @"Detect Jekyll front-matter", @"")
                      valuePath:@"preferences.htmlDetectFrontMatter"
                    enabledPath:nil],
        [self checkboxWithTitle:NSLocalizedString(
            @"Detect table of contents token", @"")
                      valuePath:@"preferences.htmlRendersTOC" enabledPath:nil],
        [self checkboxWithTitle:NSLocalizedString(
            @"Render newline literally", @"")
                      valuePath:@"preferences.htmlHardWrap" enabledPath:nil],
        [self checkboxWithTitle:NSLocalizedString(
            @"Scale preview based on editor font size", @"")
                      valuePath:@"preferences.previewZoomRelativeToBaseFontSize"
                    enabledPath:nil],
        [self rowWithViews:@[
            [self labelWithTitle:NSLocalizedString(@"Default path:", @"")],
            path] indent:0.0],
    ];

    NSStackView *stack = [NSStackView stackViewWithViews:rows];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10.0;
    stack.edgeInsets = NSEdgeInsetsMake(22.0, 24.0, 22.0, 24.0);
    // Space the path row away from the toggles above it.
    [stack setCustomSpacing:18.0 afterView:rows[rows.count - 2]];
    [stack layoutSubtreeIfNeeded];

    NSView *view = [[NSView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, stack.fittingSize.width, stack.fittingSize.height)];
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

- (void)viewWillAppear
{
    [self loadStylesheets];
    [self loadHighlightingThemes];
}


#pragma mark - IBAction

- (IBAction)changeStylesheet:(NSPopUpButton *)sender
{
    NSString *title = sender.selectedItem.title;

    // Special case: the first (empty) item. No stylesheets will be used.
    if (!title.length)
        self.preferences.htmlStyleName = nil;
    else
        self.preferences.htmlStyleName = title;
}

- (IBAction)changeHighlightingTheme:(NSPopUpButton *)sender
{
    NSString *title = sender.selectedItem.title;
    if ([title isEqualToString:MPPrismDefaultThemeName()])
        self.preferences.htmlHighlightingThemeName = @"";
    else
        self.preferences.htmlHighlightingThemeName = title;
}

- (IBAction)invokeStylesheetFunction:(NSSegmentedControl *)sender
{
    switch (sender.selectedSegment)
    {
        case 0:     // Reveal
        {
            NSString *dirPath = MPDataDirectory(kMPStylesDirectoryName);
            NSURL *url = [NSURL fileURLWithPath:dirPath];
            NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
            [workspace activateFileViewerSelectingURLs:@[url]];
            break;
        }
        case 1:     // Reload
        {
            [self loadStylesheets];
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center postNotificationName:MPDidRequestPreviewRenderNotification
                                  object:self];
            break;
        }
        default:
            break;
    }
}


#pragma mark - Private

- (void)loadStylesheets
{
    self.stylesheetSelect.enabled = NO;
    [self.stylesheetSelect removeAllItems];

    NSArray *itemTitles = MPListEntriesForDirectory(
        kMPStylesDirectoryName,
        MPFileNameHasExtensionProcessor(kMPStyleFileExtension)
    );

    [self.stylesheetSelect addItemWithTitle:@""];
    [self.stylesheetSelect addItemsWithTitles:itemTitles];

    NSString *title = self.preferences.htmlStyleName;
    if (title.length)
        [self.stylesheetSelect selectItemWithTitle:title];

    self.stylesheetSelect.enabled = YES;
}

- (void)loadHighlightingThemes
{
    self.highlightingThemeSelect.enabled = NO;
    [self.highlightingThemeSelect removeAllItems];

    NSBundle *bundle = [NSBundle mainBundle];
    NSArray *urls = [bundle URLsForResourcesWithExtension:@"css"
                                             subdirectory:@"Prism/themes"];
    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSURL *url in urls)
    {
        NSString *name = url.lastPathComponent;
        if (name.length <= 10)
            continue;
        name = [name substringWithRange:NSMakeRange(6, name.length - 10)];
        [titles addObject:[name capitalizedString]];
    }

    [self.highlightingThemeSelect addItemWithTitle:MPPrismDefaultThemeName()];
    [self.highlightingThemeSelect addItemsWithTitles:titles];

    NSString *currentName = self.preferences.htmlHighlightingThemeName;
    if (currentName.length)
        [self.highlightingThemeSelect selectItemWithTitle:currentName];

    if (self.preferences.htmlSyntaxHighlighting)
        self.highlightingThemeSelect.enabled = YES;
}

@end
