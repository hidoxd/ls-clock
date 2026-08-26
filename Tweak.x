#import <UIKit/UIKit.h>
#import <substrate.h>
#import "Tweak.h"

#ifndef jbroot
#define jbroot(path) @"/var/jb" path
#endif

static BOOL sTweakReady = NO;
static NSDictionary<NSString *, UIImage *> *sDigitCache = nil;

// Однократная загрузка изображений в память при старте
static void PreloadImages(void) {
    NSMutableDictionary *dict = [NSMutableDictionary new];
    NSString *basePath = jbroot(@"/Library/Application Support/LSClock/Digits/");

    for (int i = 0; i <= 9; i++) {
        NSString *png = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]];
        NSString *gif = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.gif", i]];
        UIImage *img = [UIImage imageWithContentsOfFile:png] ?: [UIImage imageWithContentsOfFile:gif];
        if (img) dict[@(i).stringValue] = img;
    }

    NSString *cPng = [basePath stringByAppendingPathComponent:@"colon.png"];
    NSString *cGif = [basePath stringByAppendingPathComponent:@"colon.gif"];
    UIImage *cImg = [UIImage imageWithContentsOfFile:cPng] ?: [UIImage imageWithContentsOfFile:cGif];
    if (cImg) dict[@"colon"] = cImg;

    sDigitCache = [dict copy];
}

// Контейнер кастомных часов
@interface LSClockContainerView : UIView
@property (nonatomic, strong) UIImageView *hT, *hO, *col, *mT, *mO;
@property (nonatomic, strong) NSTimer *timer;
- (void)updateTime;
@end

@implementation LSClockContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;

        _hT = [UIImageView new];
        _hO = [UIImageView new];
        _col = [UIImageView new];
        _mT = [UIImageView new];
        _mO = [UIImageView new];

        NSArray *views = @[_hT, _hO, _col, _mT, _mO];
        for (UIImageView *v in views) {
            v.contentMode = UIViewContentModeScaleAspectFit;
            [self addSubview:v];
        }
        [self updateTime];
    }
    return self;
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (newWindow) {
        [self updateTime];
        if (!_timer) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateTime) userInfo:nil repeats:YES];
        }
    } else {
        [_timer invalidate];
        _timer = nil;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    CGFloat dW = w / 4.5;
    _hT.frame = CGRectMake(0, 0, dW, h);
    _hO.frame = CGRectMake(dW, 0, dW, h);
    _col.frame = CGRectMake(dW * 2.0, 0, dW * 0.5, h);
    _mT.frame = CGRectMake(dW * 2.5, 0, dW, h);
    _mO.frame = CGRectMake(dW * 3.5, 0, dW, h);
}

- (void)updateTime {
    if (!sDigitCache) return;
    NSDateComponents *c = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];

    _hT.image = sDigitCache[[NSString stringWithFormat:@"%ld", (long)(c.hour / 10)]];
    _hO.image = sDigitCache[[NSString stringWithFormat:@"%ld", (long)(c.hour % 10)]];
    _col.image = sDigitCache[@"colon"];
    _mT.image = sDigitCache[[NSString stringWithFormat:@"%ld", (long)(c.minute / 10)]];
    _mO.image = sDigitCache[[NSString stringWithFormat:@"%ld", (long)(c.minute % 10)]];
}

@end

// 1. Активация строго через 5 секунд после успешной загрузки SpringBoard
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sTweakReady = YES;
    });
}
%end

// 2. Перехват системного виджета часов
%hook CSProminentTimeView
%property (nonatomic, strong) LSClockContainerView *lsClockContainer;

- (void)didMoveToWindow {
    %orig;
    if (!sTweakReady) return;

    if (self.window && !self.lsClockContainer) {
        LSClockContainerView *clock = [[LSClockContainerView alloc] initWithFrame:self.bounds];
        clock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.lsClockContainer = clock;
        [self addSubview:clock];
    }
}

- (void)layoutSubviews {
    %orig;
    if (!sTweakReady) return;

    if (self.lsClockContainer && !CGRectEqualToRect(self.lsClockContainer.frame, self.bounds)) {
        self.lsClockContainer.frame = self.bounds;
    }
}

%end

%ctor {
    @autoreleasepool {
        PreloadImages();
        %init;
    }
}
