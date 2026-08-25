#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <substrate.h>
#import "Tweak.h"

#ifndef jbroot
#define jbroot(path) @"/var/jb" path
#endif

// ==========================================
// Безопасный декодер GIF файлов
// ==========================================
static UIImage *SafeAnimatedGIFFromFilePath(NSString *filePath) {
    if (!filePath || filePath.length == 0) return nil;

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:filePath]) return nil;

    NSData *data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:nil];
    if (!data || data.length == 0) return nil;

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;

    size_t count = CGImageSourceGetCount(source);
    if (count == 0) {
        CFRelease(source);
        return nil;
    }

    if (count == 1) {
        CGImageRef cgImg = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        if (!cgImg) return nil;
        UIImage *img = [UIImage imageWithCGImage:cgImg];
        CGImageRelease(cgImg);
        return img;
    }

    NSMutableArray<UIImage *> *images = [NSMutableArray arrayWithCapacity:count];
    NSTimeInterval totalDuration = 0.0;

    for (size_t i = 0; i < count; i++) {
        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (imageRef) {
            [images addObject:[UIImage imageWithCGImage:imageRef]];
            CGImageRelease(imageRef);
        }

        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
        if (properties) {
            CFDictionaryRef gifProperties = CFDictionaryGetValue(properties, kCGImagePropertyGIFDictionary);
            if (gifProperties) {
                NSNumber *delay = CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFUnclampedDelayTime);
                if (!delay || delay.floatValue <= 0) {
                    delay = CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFDelayTime);
                }
                totalDuration += (delay ? delay.doubleValue : 0.1);
            }
            CFRelease(properties);
        }
    }
    CFRelease(source);

    if (images.count == 0) return nil;
    if (totalDuration <= 0) totalDuration = 0.1 * images.count;

    return [UIImage animatedImageWithImages:images duration:totalDuration];
}

// ==========================================
// Потокобезопасное кэширование цифр
// ==========================================
static NSDictionary<NSString *, UIImage *> *sDigitCache = nil;

static void LoadDigitCacheIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *dict = [NSMutableDictionary new];
        NSString *basePath = jbroot(@"/Library/Application Support/LSClock/Digits/");

        for (int i = 0; i <= 9; i++) {
            NSString *path = [basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.gif", i]];
            UIImage *img = SafeAnimatedGIFFromFilePath(path);
            if (img) {
                dict[@(i).stringValue] = img;
            }
        }
        sDigitCache = [dict copy];
    });
}

// ==========================================
// Изолированный контейнер часов
// ==========================================
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

// ==========================================
// Безопасный хук системы
// ==========================================
@interface CSProminentTimeView : UIView
@property (nonatomic, strong) LSClockContainerView *lsClockContainer;
@end

%hook CSProminentTimeView

%property (nonatomic, strong) LSClockContainerView *lsClockContainer;

- (void)layoutSubviews {
    %orig;

    // Защита от нулевых размеров при инициализации
    if (CGRectIsEmpty(self.bounds) || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) {
        return;
    }

    // Безопасное скрытие оригинального текста без сбоя Auto Layout
    for (UIView *subview in self.subviews) {
        if (subview != self.lsClockContainer) {
            subview.alpha = 0.001;
        }
    }

    // Ленивая инициализация
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
