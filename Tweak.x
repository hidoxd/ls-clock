#import <UIKit/UIKit.h>
#import <substrate.h>
#import "Tweak.h"

#ifndef jbroot
#define jbroot(path) @"/var/jb" path
#endif

// Кэш изображений .gif
static NSDictionary<NSString *, UIImage *> *sDigitCache = nil;

static void LoadDigitCacheIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *dict = [NSMutableDictionary new];
        NSString *basePath = jbroot(@"/Library/Application Support/LSClock/Digits/");

        for (int i = 0; i <= 9; i++) {
            NSString *path = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.gif", i]];
            UIImage *img = [UIImage imageWithContentsOfFile:path];
            if (img) dict[@(i).stringValue] = img;
        }

        NSString *colonPath = [basePath stringByAppendingPathComponent:@"colon.gif"];
        UIImage *colonImg = [UIImage imageWithContentsOfFile:colonPath];
        if (colonImg) dict[@"colon"] = colonImg;

        sDigitCache = [dict copy];
    });
}

// Контейнер часов
@interface LSClockContainerView : UIView
@property (nonatomic, strong) UIImageView *hourTensImageView;
@property (nonatomic, strong) UIImageView *hourOnesImageView;
@property (nonatomic, strong) UIImageView *minuteTensImageView;
@property (nonatomic, strong) UIImageView *minuteOnesImageView;
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
        _minuteTensImageView = [[UIImageView alloc] init];
        _minuteOnesImageView = [[UIImageView alloc] init];

        NSArray *views = @[_hourTensImageView, _hourOnesImageView, _minuteTensImageView, _minuteOnesImageView];
        for (UIImageView *v in views) {
            v.contentMode = UIViewContentModeScaleAspectFit;
            v.clipsToBounds = YES;
            [self addSubview:v];
        }
        [self updateTime];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    if (w <= 0 || h <= 0) return;

    CGFloat digitW = w / 4.5;

    _hourTensImageView.frame = CGRectMake(0, 0, digitW, h);
    _hourOnesImageView.frame = CGRectMake(digitW, 0, digitW, h);
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

    if (sDigitCache[hT]) _hourTensImageView.image = sDigitCache[hT];
    if (sDigitCache[hO]) _hourOnesImageView.image = sDigitCache[hO];
    if (sDigitCache[mT]) _minuteTensImageView.image = sDigitCache[mT];
    if (sDigitCache[mO]) _minuteOnesImageView.image = sDigitCache[mO];
}

@end

// Хук системных часов
%hook CSProminentTimeView

%property (nonatomic, strong) LSClockContainerView *lsClockContainer;

- (void)layoutSubviews {
    %orig;

    if (CGRectIsEmpty(self.bounds) || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) {
        return;
    }

    for (UIView *subview in self.subviews) {
        if (subview != self.lsClockContainer) {
            subview.alpha = 0.001;
        }
    }

    if (!self.lsClockContainer) {
        LSClockContainerView *container = [[LSClockContainerView alloc] initWithFrame:self.bounds];
        container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.lsClockContainer = container;
        [self addSubview:container];
    } else {
        self.lsClockContainer.frame = self.bounds;
        [self.lsClockContainer updateTime];
    }
}

%end

%ctor {
    @autoreleasepool {
        %init;
    }
}
