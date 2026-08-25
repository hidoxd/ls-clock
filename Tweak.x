#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <substrate.h>
#import "Tweak.h"

#ifndef jbroot
#define jbroot(path) @"/var/jb" path
#endif

// Безопасная функция декодирования GIF
static UIImage *AnimatedGIFFromFilePath(NSString *filePath) {
    if (!filePath || ![[NSFileManager defaultManager] fileExistsAtPath:filePath]) return nil;
    
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
    if (!source) return nil;

    size_t count = CGImageSourceGetCount(source);
    if (count <= 1) {
        UIImage *singleImage = [UIImage imageWithContentsOfFile:filePath];
        CFRelease(source);
        return singleImage;
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
                totalDuration += delay.doubleValue;
            }
            CFRelease(properties);
        }
    }
    CFRelease(source);

    if (totalDuration == 0) totalDuration = (1.0 / 10.0) * count;

    return [UIImage animatedImageWithImages:images duration:totalDuration];
}

static NSMutableDictionary<NSString *, UIImage *> *digitImageCache = nil;

static void LoadDigitImagesIfNeeded() {
    if (digitImageCache) return;
    digitImageCache = [NSMutableDictionary new];
    
    NSString *basePath = jbroot(@"/Library/Application Support/LSClock/Digits/");
    
    for (int i = 0; i <= 9; i++) {
        NSString *fileName = [NSString stringWithFormat:@"%d.gif", i];
        NSString *fullPath = [basePath stringByAppendingPathComponent:fileName];
        
        UIImage *animatedGIF = AnimatedGIFFromFilePath(fullPath);
        if (animatedGIF) {
            digitImageCache[@(i).stringValue] = animatedGIF;
        }
    }
}

@interface CSProminentTimeView : UIView
@property (nonatomic, strong) UIView *customClockContainer;
@property (nonatomic, strong) UIImageView *hourTensImageView;
@property (nonatomic, strong) UIImageView *hourOnesImageView;
@property (nonatomic, strong) UIImageView *minuteTensImageView;
@property (nonatomic, strong) UIImageView *minuteOnesImageView;

- (void)setupCustomClockView;
- (void)updateCustomGIFClock;
@end

%hook CSProminentTimeView

%property (nonatomic, strong) UIView *customClockContainer;
%property (nonatomic, strong) UIImageView *hourTensImageView;
%property (nonatomic, strong) UIImageView *hourOnesImageView;
%property (nonatomic, strong) UIImageView *minuteTensImageView;
%property (nonatomic, strong) UIImageView *minuteOnesImageView;

- (void)didMoveToWindow {
    %orig;
    @try {
        if (self.window) {
            [self setupCustomClockView];
        }
    } @catch (NSException *e) {}
}

%new
- (void)setupCustomClockView {
    if (self.customClockContainer) return;

    LoadDigitImagesIfNeeded();

    // Создаем контейнер поверх оригинальных часов
    self.customClockContainer = [[UIView alloc] initWithFrame:self.bounds];
    self.customClockContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.customClockContainer.userInteractionEnabled = NO;
    self.customClockContainer.layer.zPosition = 999; // Гарантируем отображение поверх системного текста

    // Скрываем оригинальный текст безопасным способом
    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:[UILabel class]] || [NSStringFromClass([subview class]) containsString:@"Label"]) {
            subview.hidden = YES;
        }
    }

    [self addSubview:self.customClockContainer];

    CGFloat digitWidth = self.bounds.size.width / 4.5;
    CGFloat digitHeight = self.bounds.size.height;

    self.hourTensImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, digitWidth, digitHeight)];
    self.hourOnesImageView = [[UIImageView alloc] initWithFrame:CGRectMake(digitWidth, 0, digitWidth, digitHeight)];
    self.minuteTensImageView = [[UIImageView alloc] initWithFrame:CGRectMake(digitWidth * 2.5, 0, digitWidth, digitHeight)];
    self.minuteOnesImageView = [[UIImageView alloc] initWithFrame:CGRectMake(digitWidth * 3.5, 0, digitWidth, digitHeight)];

    NSArray *views = @[self.hourTensImageView, self.hourOnesImageView, self.minuteTensImageView, self.minuteOnesImageView];
    for (UIImageView *v in views) {
        v.contentMode = UIViewContentModeScaleAspectFit;
        [self.customClockContainer addSubview:v];
    }

    [self updateCustomGIFClock];
}

%new
- (void)updateCustomGIFClock {
    @try {
        NSDate *now = [NSDate date];
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:now];

        NSInteger hour = components.hour;
        NSInteger minute = components.minute;

        NSString *hTens = [NSString stringWithFormat:@"%ld", (long)(hour / 10)];
        NSString *hOnes = [NSString stringWithFormat:@"%ld", (long)(hour % 10)];
        NSString *mTens = [NSString stringWithFormat:@"%ld", (long)(minute / 10)];
        NSString *mOnes = [NSString stringWithFormat:@"%ld", (long)(minute % 10)];

        if (digitImageCache[hTens]) self.hourTensImageView.image = digitImageCache[hTens];
        if (digitImageCache[hOnes]) self.hourOnesImageView.image = digitImageCache[hOnes];
        if (digitImageCache[mTens]) self.minuteTensImageView.image = digitImageCache[mTens];
        if (digitImageCache[mOnes]) self.minuteOnesImageView.image = digitImageCache[mOnes];
    } @catch (NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        if (!self.customClockContainer) {
            [self setupCustomClockView];
        } else {
            [self bringSubviewToFront:self.customClockContainer];
            [self updateCustomGIFClock];
        }
    } @catch (NSException *e) {}
}

%end
