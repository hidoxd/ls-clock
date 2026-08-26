#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <substrate.h>
#import "Tweak.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

%ctor {
    // 1. Уводим исполнение из главного потока, чтобы backboardd не зависал в ожидании SB
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // 2. Защита от сбоя CommCenter (Cause 15 / kEmergencyOnly)
        // Пауза перед стартом даёт модему время перерегистрироваться в сети
        [NSThread sleepForTimeInterval:3.0];
        
        NSLog(@"[DiagnosticsFix] Фоновый поток запущен. Sandbox ограничен!");

#ifndef jbroot
#define jbroot(path) @"/var/jb" path
#endif

static NSDictionary<NSString *, UIImage *> *sDigitCache = nil;

// Корректная загрузка GIF (с анимацией) и PNG через ImageIO
static UIImage *LoadImageAtPath(NSString *path) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;

    if ([path.pathExtension.lowercaseString isEqualToString:@"gif"]) {
        NSURL *url = [NSURL fileURLWithPath:path];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (!source) return nil;

        size_t count = CGImageSourceGetCount(source);
        if (count <= 1) {
            CFRelease(source);
            return [UIImage imageWithContentsOfFile:path];
        }

        NSMutableArray<UIImage *> *images = [NSMutableArray arrayWithCapacity:count];
        NSTimeInterval duration = 0.0;

        for (size_t i = 0; i < count; i++) {
            CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (imageRef) {
                [images addObject:[UIImage imageWithCGImage:imageRef]];
                CGImageRelease(imageRef);
            }
            duration += 0.1; // Длительность смены кадров GIF
        }
        CFRelease(source);
        return [UIImage animatedImageWithImages:images duration:duration];
    }

    return [UIImage imageWithContentsOfFile:path];
}

static void PreloadImages(void) {
    NSMutableDictionary *dict = [NSMutableDictionary new];
    NSString *basePath = jbroot(@"/Library/Application Support/LSClock/Digits/");

    for (int i = 0; i <= 9; i++) {
        NSString *png = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", i]];
        NSString *gif = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.gif", i]];

        UIImage *img = LoadImageAtPath(png) ?: LoadImageAtPath(gif);
        if (img) dict[@(i).stringValue] = img;
    }

    NSString *cPng = [basePath stringByAppendingPathComponent:@"colon.png"];
    NSString *cGif = [basePath stringByAppendingPathComponent:@"colon.gif"];
    UIImage *cImg = LoadImageAtPath(cPng) ?: LoadImageAtPath(cGif);
    if (cImg) dict[@"colon"] = cImg;

    sDigitCache = [dict copy];
}

@interface LSClockContainerView : UIView
@property (nonatomic, strong) UIImageView *hT, *hO, *col, *mT, *mO;
@property (nonatomic, strong) dispatch_source_t timer;
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
        [self startTimer];
    } else {
        [self stopTimer];
    }
}

- (void)startTimer {
    if (_timer) return;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{
        [weakSelf updateTime];
    });
    dispatch_resume(_timer);
}

- (void)stopTimer {
    if (_timer) {
        dispatch_source_cancel(_timer);
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

// Внедряем контейнер при создании View часов
%hook CSProminentTimeView
%property (nonatomic, strong) LSClockContainerView *lsClockContainer;

- (void)didMoveToWindow {
    %orig;
    if (self.window && !self.lsClockContainer) {
        LSClockContainerView *clock = [[LSClockContainerView alloc] initWithFrame:self.bounds];
        clock.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.lsClockContainer = clock;
        [self addSubview:clock];
    }
}

%end

%ctor {
    @autoreleasepool {
        PreloadImages();
        %init;
    }
}
