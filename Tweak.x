#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <rootless.h>

// Безопасный фоновый декодер анимированных GIF через ImageIO
static UIImage *loadAnimatedGIF(NSString *path) {
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;

    size_t count = CGImageSourceGetCount(source);
    if (count <= 1) {
        CFRelease(source);
        return [UIImage imageWithData:data];
    }

    NSMutableArray *images = [NSMutableArray arrayWithCapacity:count];
    NSTimeInterval duration = 0.0;

    for (size_t i = 0; i < count; i++) {
        CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (!cgImage) continue;

        NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
        NSDictionary *gifDict = properties[(NSString *)kCGImagePropertyGIFDictionary];
        NSNumber *delayTime = gifDict[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?: gifDict[(NSString *)kCGImagePropertyGIFDelayTime];
        
        double delay = [delayTime doubleValue];
        if (delay <= 0.02) delay = 0.1;
        duration += delay;

        [images addObject:[UIImage imageWithCGImage:cgImage]];
        CGImageRelease(cgImage);
    }
    CFRelease(source);

    if (duration <= 0.0) duration = 0.1 * count;
    return [UIImage animatedImageWithImages:images duration:duration];
}

// Менеджер фоновой загрузки изображений
@interface LSClockManager : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *imageCache;
@property (nonatomic, assign) BOOL isLoaded;
+ (instancetype)sharedManager;
- (void)preloadImagesAsync:(void(^)(void))completion;
- (UIImage *)imageForName:(NSString *)name;
@end

@implementation LSClockManager

+ (instancetype)sharedManager {
    static LSClockManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) {
        _imageCache = [NSMutableDictionary dictionary];
        _isLoaded = NO;
        [self preloadImagesAsync:nil];
    }
    return self;
}

- (void)preloadImagesAsync:(void(^)(void))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *baseDir = ROOT_PATH_NS(@"/Library/Application Support/LSClock");
        NSArray *names = @[@"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"colon"];
        
        NSMutableDictionary *tempDict = [NSMutableDictionary dictionary];
        for (NSString *name in names) {
            NSString *filePath = [baseDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.gif", name]];
            UIImage *img = loadAnimatedGIF(filePath);
            if (img) {
                tempDict[name] = img;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.imageCache addEntriesFromDictionary:tempDict];
            self.isLoaded = YES;
            [[NSNotificationCenter defaultCenter] postNotificationName:@"LSClockImagesReadyNotification" object:nil];
            if (completion) completion();
        });
    });
}

- (UIImage *)imageForName:(NSString *)name {
    return self.imageCache[name];
}

@end

// Нативный контейнер отображения часов
@interface LSClockContainerView : UIView
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UIImageView *h1View;
@property (nonatomic, strong) UIImageView *h2View;
@property (nonatomic, strong) UIImageView *colonView;
@property (nonatomic, strong) UIImageView *m1View;
@property (nonatomic, strong) UIImageView *m2View;
@property (nonatomic, copy) NSString *lastTimeStr;
@property (nonatomic, strong) NSTimer *updateTimer;
- (void)updateClockDisplay;
@end

@implementation LSClockContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor clearColor];

        _stackView = [[UIStackView alloc] initWithFrame:self.bounds];
        _stackView.axis = UILayoutConstraintAxisHorizontal;
        _stackView.alignment = UIStackViewAlignmentCenter;
        _stackView.distribution = UIStackViewDistributionFillEqually;
        _stackView.spacing = 2.0;
        _stackView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_stackView];

        _h1View = [self createImageView];
        _h2View = [self createImageView];
        _colonView = [self createImageView];
        _m1View = [self createImageView];
        _m2View = [self createImageView];

        [_stackView addArrangedSubview:_h1View];
        [_stackView addArrangedSubview:_h2View];
        [_stackView addArrangedSubview:_colonView];
        [_stackView addArrangedSubview:_m1View];
        [_stackView addArrangedSubview:_m2View];

        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(updateClockDisplay) 
                                                     name:@"LSClockImagesReadyNotification" 
                                                   object:nil];

        [self updateClockDisplay];

        __weak typeof(self) weakSelf = self;
        _updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [weakSelf updateClockDisplay];
        }];
        [[NSRunLoop mainRunLoop] addTimer:_updateTimer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (UIImageView *)createImageView {
    UIImageView *iv = [[UIImageView alloc] init];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.backgroundColor = [UIColor clearColor];
    iv.clipsToBounds = YES;
    return iv;
}

- (void)updateClockDisplay {
    LSClockManager *mgr = [LSClockManager sharedManager];
    if (!mgr.isLoaded && mgr.imageCache.count == 0) {
        return;
    }

    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comps = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:now];

    NSString *currentTimeStr = [NSString stringWithFormat:@"%02ld%02ld", (long)comps.hour, (long)comps.minute];

    if ([currentTimeStr isEqualToString:self.lastTimeStr] && self.colonView.image != nil) {
        return;
    }
    self.lastTimeStr = currentTimeStr;

    NSString *d0 = [currentTimeStr substringWithRange:NSMakeRange(0, 1)];
    NSString *d1 = [currentTimeStr substringWithRange:NSMakeRange(1, 1)];
    NSString *d2 = [currentTimeStr substringWithRange:NSMakeRange(2, 1)];
    NSString *d3 = [currentTimeStr substringWithRange:NSMakeRange(3, 1)];

    self.h1View.image = [mgr imageForName:d0];
    self.h2View.image = [mgr imageForName:d1];
    self.colonView.image = [mgr imageForName:@"colon"];
    self.m1View.image = [mgr imageForName:d2];
    self.m2View.image = [mgr imageForName:d3];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_updateTimer invalidate];
    _updateTimer = nil;
}

@end

// Хук часов локскрина
@interface SBFLockScreenDateView : UIView
@property (nonatomic, strong) LSClockContainerView *lsClockContainer;
@end

%hook SBFLockScreenDateView

%property (nonatomic, strong) LSClockContainerView *lsClockContainer;

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        if (!self.lsClockContainer) {
            LSClockContainerView *container = [[LSClockContainerView alloc] initWithFrame:self.bounds];
            self.lsClockContainer = container;
            [self addSubview:container];
        }
        [self.lsClockContainer updateClockDisplay];
    }
}

- (void)layoutSubviews {
    %orig;

    // Скрываем родные цифры через alpha без вызова рекурсии AutoLayout
    for (UIView *subview in self.subviews) {
        if (subview != self.lsClockContainer) {
            if (subview.alpha != 0.0) {
                subview.alpha = 0.0;
            }
        }
    }

    if (self.lsClockContainer) {
        if (!CGRectEqualToRect(self.lsClockContainer.frame, self.bounds)) {
            self.lsClockContainer.frame = self.bounds;
        }
    }
}

%end

%ctor {
    // Предварительный запуск фонового менеджера
    [LSClockManager sharedManager];
}
