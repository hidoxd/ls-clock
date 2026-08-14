#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <rootless.h>

// Функция нативного декодирования и анимации GIF через GPU (ImageIO)
static UIImage *animatedGIFFromFile(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;

    size_t count = CGImageSourceGetCount(source);
    if (count <= 1) {
        CFRelease(source);
        return [UIImage imageWithContentsOfFile:path];
    }

    NSMutableArray *images = [NSMutableArray arrayWithCapacity:count];
    NSTimeInterval duration = 0.0;

    for (size_t i = 0; i < count; i++) {
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (!image) continue;

        NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
        NSDictionary *gifProperties = properties[(NSString *)kCGImagePropertyGIFDictionary];
        NSNumber *delayTime = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?: gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
        duration += [delayTime doubleValue] > 0.0 ? [delayTime doubleValue] : 0.1;

        [images addObject:[UIImage imageWithCGImage:image]];
        CGImageRelease(image);
    }
    CFRelease(source);

    if (duration == 0.0) duration = 0.1 * count;
    return [UIImage animatedImageWithImages:images duration:duration];
}

// Нативный контейнер часов
@interface LSClockContainerView : UIView
@property (nonatomic, retain) UIStackView *stackView;
@property (nonatomic, retain) UIImageView *h1View;
@property (nonatomic, retain) UIImageView *h2View;
@property (nonatomic, retain) UIImageView *colonView;
@property (nonatomic, retain) UIImageView *m1View;
@property (nonatomic, retain) UIImageView *m2View;
@property (nonatomic, retain) NSMutableDictionary<NSString *, UIImage *> *gifCache;
@property (nonatomic, retain) NSTimer *timer;
- (void)updateTime;
- (UIImage *)gifNamed:(NSString *)name;
@end

@implementation LSClockContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = NO;
        self.gifCache = [NSMutableDictionary dictionary];

        // Горизонтальный стек для 5 элементов: [Ч][Ч]:[М][М]
        self.stackView = [[UIStackView alloc] initWithFrame:self.bounds];
        self.stackView.axis = UILayoutConstraintAxisHorizontal;
        self.stackView.alignment = UIStackViewAlignmentCenter;
        self.stackView.distribution = UIStackViewDistributionFillEqually;
        self.stackView.spacing = 2;
        self.stackView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.stackView];

        self.h1View = [self createDigitView];
        self.h2View = [self createDigitView];
        self.colonView = [self createDigitView];
        self.m1View = [self createDigitView];
        self.m2View = [self createDigitView];

        [self.stackView addArrangedSubview:self.h1View];
        [self.stackView addArrangedSubview:self.h2View];
        [self.stackView addArrangedSubview:self.colonView];
        [self.stackView addArrangedSubview:self.m1View];
        [self.stackView addArrangedSubview:self.m2View];

        [self updateTime];

        // Таймер для обновления цифр каждую секунду
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateTime) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (UIImageView *)createDigitView {
    UIImageView *iv = [[UIImageView alloc] init];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    return iv;
}

- (UIImage *)gifNamed:(NSString *)name {
    if (!name) return nil;
    if (self.gifCache[name]) return self.gifCache[name];

    NSString *baseDir = ROOT_PATH_NS(@"/Library/Application Support/LSClock");
    NSString *path = [baseDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.gif", name]];

    UIImage *img = animatedGIFFromFile(path);
    if (img) {
        self.gifCache[name] = img;
    }
    return img;
}

- (void)updateTime {
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comps = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:now];

    NSString *timeStr = [NSString stringWithFormat:@"%02ld%02ld", (long)comps.hour, (long)comps.minute];

    self.h1View.image = [self gifNamed:[timeStr substringWithRange:NSMakeRange(0, 1)]];
    self.h2View.image = [self gifNamed:[timeStr substringWithRange:NSMakeRange(1, 1)]];
    self.colonView.image = [self gifNamed:@"colon"];
    self.m1View.image = [self gifNamed:[timeStr substringWithRange:NSMakeRange(2, 1)]];
    self.m2View.image = [self gifNamed:[timeStr substringWithRange:NSMakeRange(3, 1)]];
}

- (void)dealloc {
    [self.timer invalidate];
}

@end

// Хук системных часов экрана блокировки
@interface SBFLockScreenDateView : UIView
@property (nonatomic, retain) LSClockContainerView *lsClockContainer;
@end

%hook SBFLockScreenDateView

%property (nonatomic, retain) LSClockContainerView *lsClockContainer;

- (void)didMoveToWindow {
    %orig;
    if (self.window && !self.lsClockContainer) {
        self.lsClockContainer = [[LSClockContainerView alloc] initWithFrame:self.bounds];
        [self addSubview:self.lsClockContainer];
    }
}

- (void)layoutSubviews {
    %orig;

    // Скрываем стандартные белые цифры системных часов
    for (UIView *subview in self.subviews) {
        if (subview != self.lsClockContainer) {
            subview.hidden = YES;
            subview.alpha = 0.0;
        }
    }

    if (self.lsClockContainer) {
        self.lsClockContainer.frame = self.bounds;
    }
}

%end
