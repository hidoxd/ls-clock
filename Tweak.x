#import <UIKit/UIKit.h>
#import <substrate.h>
#import "Tweak.h"

#ifndef jbroot
#define jbroot(path) @"/var/jb" path
#endif

static NSDictionary<NSString *, UIImage *> *sDigitCache = nil;

// Автоматическая загрузка PNG или GIF без сбоев
static void LoadDigitCacheIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *dict = [NSMutableDictionary new];
        NSString *basePath = jbroot(@"/Library/Application Support/LSClock/Digits/");
        NSFileManager *fm = [NSFileManager defaultManager];

        for (int i = 0; i <= 9; i++) {
            NSString *key = @(i).stringValue;
            NSString *pngPath = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]];
            NSString *gifPath = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.gif", i]];

            UIImage *img = nil;
            if ([fm fileExistsAtPath:pngPath]) {
                img = [UIImage imageWithContentsOfFile:pngPath];
            } else if ([fm fileExistsAtPath:gifPath]) {
                img = [UIImage imageWithContentsOfFile:gifPath];
            }
            if (img) dict[key] = img;
        }

        NSString *colonPng = [basePath stringByAppendingPathComponent:@"colon.png"];
        NSString *colonGif = [basePath stringByAppendingPathComponent:@"colon.gif"];
        UIImage *colonImg = nil;
        if ([fm fileExistsAtPath:colonPng]) {
            colonImg = [UIImage imageWithContentsOfFile:colonPng];
        } else if ([fm fileExistsAtPath:colonGif]) {
            colonImg = [UIImage imageWithContentsOfFile:colonGif];
        }
        if (colonImg) dict[@"colon"] = colonImg;

        sDigitCache = [dict copy];
    });
}

// Изолированный UIView для цифр
@interface LSClockContainerView : UIView
@property (nonatomic, strong) UIImageView *hourTensImageView;
@property (nonatomic, strong) UIImageView *hourOnesImageView;
@property (nonatomic, strong) UIImageView *colonImageView;
@property (nonatomic, strong) UIImageView *minuteTensImageView;
@property (nonatomic, strong) UIImageView *minuteOnesImageView;
@property (nonatomic, strong) NSTimer *updateTimer;
- (void)updateTime;
@end

@implementation LSClockContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = NO;

        _hourTensImageView = [[UIImageView alloc] init];
        _hourOnesImageView = [[UIImageView alloc] init];
        _colonImageView = [[UIImageView alloc] init];
        _minuteTensImageView = [[UIImageView alloc] init];
        _minuteOnesImageView = [[UIImageView alloc] init];

        NSArray *views = @[_hourTensImageView, _hourOnesImageView, _colonImageView, _minuteTensImageView, _minuteOnesImageView];
        for (UIImageView *v in views) {
            v.contentMode = UIViewContentModeScaleAspectFit;
            v.clipsToBounds = YES;
            [self addSubview:v];
        }
        [self updateTime];
    }
    return self;
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (newWindow) {
        [self startTimer];
        [self updateTime];
    } else {
        [self stopTimer];
    }
}

- (void)startTimer {
    [self stopTimer];
    _updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                     target:self
                                                   selector:@selector(updateTime)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)stopTimer {
    if (_updateTimer) {
        [_updateTimer invalidate];
        _updateTimer = nil;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    if (w <= 0 || h <= 0) return;

    CGFloat digitW = w / 4.5;

    _hourTensImageView.frame = CGRectMake(0, 0, digitW, h);
    _hourOnesImageView.frame = CGRectMake(digitW, 0, digitW, h);
    _colonImageView.frame = CGRectMake(digitW * 2.0, 0, digitW * 0.5, h);
    _minuteTensImageView.frame = CGRectMake(digitW * 2.5, 0, digitW, h);
    _minuteOnesImageView.frame = CGRectMake(digitW * 3.5, 0, digitW, h);
}

- (void)updateTime {
    LoadDigitCacheIfNeeded();
    if (!sDigitCache || sDigitCache.count == 0) return;

    NSDateComponents *comp = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
    NSInteger hour = comp.hour;
    NSInteger minute = comp.minute;

    NSString *hT = [NSString stringWithFormat:@"%ld", (long)(hour / 10)];
    NSString *hO = [NSString stringWithFormat:@"%ld", (long)(hour % 10)];
    NSString *mT = [NSString stringWithFormat:@"%ld", (long)(minute / 10)];
    NSString *mO = [NSString stringWithFormat:@"%ld", (long)(minute % 10)];

    if (sDigitCache[hT] && _hourTensImageView.image != sDigitCache[hT]) _hourTensImageView.image = sDigitCache[hT];
    if (sDigitCache[hO] && _hourOnesImageView.image != sDigitCache[hO]) _hourOnesImageView.image = sDigitCache[hO];
    if (sDigitCache[@"colon"] && _colonImageView.image != sDigitCache[@"colon"]) _colonImageView.image = sDigitCache[@"colon"];
    if (sDigitCache[mT] && _minuteTensImageView.image != sDigitCache[mT]) _minuteTensImageView.image = sDigitCache[mT];
    if (sDigitCache[mO] && _minuteOnesImageView.image != sDigitCache[mO]) _minuteOnesImageView.image = sDigitCache[mO];
}

@end

// Безопасный перехват часов
%hook CSProminentTimeView

%property (nonatomic, strong) LSClockContainerView *lsClockContainer;

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [self ls_hideSystemSubviews];
        [self ls_setupCustomClock];
    }
}

- (void)didAddSubview:(UIView *)subview {
    %orig;
    if (self.lsClockContainer && subview != self.lsClockContainer) {
        subview.alpha = 0.0;
    }
}

%new
- (void)ls_hideSystemSubviews {
    for (UIView *subview in self.subviews) {
        if (subview != self.lsClockContainer) {
            subview.alpha = 0.0;
        }
    }
}

%new
- (void)ls_setupCustomClock {
    if (CGRectIsEmpty(self.bounds) || self.bounds.size.width <= 0) return;

    if (!self.lsClockContainer) {
        LSClockContainerView *container = [[LSClockContainerView alloc] initWithFrame:self.bounds];
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.lsClockContainer = container;
        [self addSubview:container];
    }
}

- (void)layoutSubviews {
    %orig;

    if (CGRectIsEmpty(self.bounds) || self.bounds.size.width <= 0) return;

    if (!self.lsClockContainer) {
        [self ls_hideSystemSubviews];
        [self ls_setupCustomClock];
    } else {
        if (!CGRectEqualToRect(self.lsClockContainer.frame, self.bounds)) {
            self.lsClockContainer.frame = self.bounds;
        }
    }
}

%end

%ctor {
    @autoreleasepool {
        %init;
    }
}
