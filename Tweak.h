#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Безопасное определение пути для Rootless (Dopamine 3.0 / /var/jb)
#if __has_include(<rootless.h>)
#import <rootless.h>
#endif

#ifndef ROOT_PATH_NS
#define ROOT_PATH_NS(path) [NSString stringWithFormat:@"/var/jb%@", path]
#endif

#define LSCLOCK_VIEW_TAG 0x15C10C
#define PREF_PATH ROOT_PATH_NS(@"/Library/Application Support/LSClock/settings.plist")
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
    BOOL customDateFormatEnabled;
    BOOL hideOriginalClock;
    BOOL showBattery;
    NSTextAlignment alignment;
    CGFloat timeFontSize;
    CGFloat dateFontSize;
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
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *batteryLabel;
@property (nonatomic, strong) NSTimer *timer;
- (void)updateClock;
- (void)startTimer;
- (void)stopTimer;
- (void)applyConfiguration;
@end
