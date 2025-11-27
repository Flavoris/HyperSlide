#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.hyprglide.app";

/// The "DarkBG" asset catalog color resource.
static NSString * const ACColorNameDarkBG AC_SWIFT_PRIVATE = @"DarkBG";

/// The "NeonBlue" asset catalog color resource.
static NSString * const ACColorNameNeonBlue AC_SWIFT_PRIVATE = @"NeonBlue";

/// The "NeonPurple" asset catalog color resource.
static NSString * const ACColorNameNeonPurple AC_SWIFT_PRIVATE = @"NeonPurple";

#undef AC_SWIFT_PRIVATE
