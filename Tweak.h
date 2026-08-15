#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>

#if __has_include(<rootless.h>)
#import <rootless.h>
#endif

#ifndef ROOT_PATH_NS
#define ROOT_PATH_NS(path) [NSString stringWithFormat:@"/var/jb%@", path]
#endif

#define LSCLOCK_VIEW_TAG 0x15C10C
#define PREF_PATH ROOT_PATH_NS(@"/Library/Application Support/LSClock/settings.plist")
#define GIF_BUNDLE_PATH ROOT_PATH_NS(@"/Library/Application Support/LSClock")
#define NOTIFY_PREFS_CHANGED "com.hidoxd.lsclock.prefschanged"

#define LS_EXECUTE_ON_MAIN_THREAD(block) \
    if ([NSThread isMainThread]) { \
        block(); \
    } else { \
        dispatch_async(dispatch_get_main_queue(), block); \
    }

typedef struct {
    BOOL enabled;
    BOOL showSeconds;
    BOOL showDate;
    BOOL showBattery;
    CGFloat digitHeight;
    CGFloat digitSpacing;
} LSClockPreferences;

@interface SBFLockScreenDateView : UIView
@property (nonatomic, retain) UIView *customSubtitleView;
- (void)_updateLabels;
- (void)updateFormat;
@end

@interface CSCoverSheetViewController : UIViewController
@property (nonatomic, readonly) BOOL isPresented;
@end

@interface LSClockContainerView : UIView
@property (nonatomic, strong) UIView *digitsContainerView;
@property (nonatomic, strong) NSMutableArray<UIImageView *> *digitImageViews;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *batteryLabel;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *lastTimeString;

- (void)updateClock;
- (void)startTimer;
- (void)stopTimer;
- (void)applyConfiguration;
@end
