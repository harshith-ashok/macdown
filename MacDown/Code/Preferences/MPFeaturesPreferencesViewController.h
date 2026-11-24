//
//  MPFeaturesPreferencesViewController.h
//  MacDown
//

#import "MPPreferencesViewController.h"
#import <MASPreferences/MASPreferencesViewController.h>

/// Settings > Features: theme and the optional features. The values live in
/// ~/.config/macdown/config.yaml (see MPFeatureSettings).
@interface MPFeaturesPreferencesViewController : MPPreferencesViewController
    <MASPreferencesViewController>

@end
