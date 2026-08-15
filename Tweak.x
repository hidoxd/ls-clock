#import "Tweak.h"

static LSClockPreferences gPrefs;
static __weak LSClockContainerView *gActiveClockView = nil;
static NSMutableDictionary<NSString *, UIImage *> *sGifImageCache = nil;

// MARK: - Высокоэффективный загрузчик анимированных GIF (ImageIO)
static UIImage *LSGetAnimatedGIF(NSString *name) {
    if (!sGifImageCache) {
        sGifImageCache = [[NSMutableDictionary alloc] init];
    }
    
    if (sGifImageCache[name]) {
        return sGifImageCache[name];
    }
    
    NSString *filePath = [GIF_BUNDLE_PATH stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.gif", name]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return nil;
    }
    
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, NULL);
    if (!source) return nil;
    
    size_t count = CGImageSourceGetCount(source);
    UIImage *animatedImage = nil;
    
    if (count <= 1) {
        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        if (imageRef) {
            animatedImage = [UIImage imageWithCGImage:imageRef scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
            CGImageRelease(imageRef);
        }
    } else {
        NSMutableArray *images = [NSMutableArray arrayWithCapacity:count];
        NSTimeInterval totalDuration = 0.0;
        
        for (size_t i = 0; i < count; i++) {
            CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, i, NULL);
            if (!imageRef) continue;
            
            [images addObject:[UIImage imageWithCGImage:imageRef scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp]];
            CGImageRelease(imageRef);
            
            // Вычисление длительности каждого кадра
            NSTimeInterval frameDuration = 0.1;
            CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
            if (properties) {
                CFDictionaryRef gifProps = CFDictionaryGetValue(properties, kCGImagePropertyGIFDictionary);
                if (gifProps) {
                    NSNumber *unclampedDelay = CFDictionaryGetValue(gifProps, kCGImagePropertyGIFUnclampedDelayTime);
                    NSNumber *delay = CFDictionaryGetValue(gifProps, kCGImagePropertyGIFDelayTime);
                    if (unclampedDelay && [unclampedDelay doubleValue] > 0.0) {
                        frameDuration = [unclampedDelay doubleValue];
                    } else if (delay && [delay doubleValue] > 0.0) {
                        frameDuration = [delay doubleValue];
                    }
                }
                CFRelease(properties);
            }
            if (frameDuration < 0.02) frameDuration = 0.1;
            totalDuration += frameDuration;
        }
        
        animatedImage = [UIImage animatedImageWithImages:images duration:totalDuration];
    }
    
    CFRelease(source);
    
    if (animatedImage) {
        sGifImageCache[name] = animatedImage;
    }
    return animatedImage;
}

// MARK: - Загрузка настроек
static void LoadPreferences(void) {
    @autoreleasepool {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
        
        gPrefs.enabled = dict[@"enabled"] ? [dict[@"enabled"] boolValue] : YES;
        gPrefs.showSeconds = dict[@"showSeconds"] ? [dict[@"showSeconds"] boolValue] : YES;
        gPrefs.showDate = dict[@"showDate"] ? [dict[@"showDate"] boolValue] : YES;
        gPrefs.showBattery = dict[@"showBattery"] ? [dict[@"showBattery"] boolValue] : YES;
        gPrefs.digitHeight = dict[@"digitHeight"] ? [dict[@"digitHeight"] floatValue] : 72.0f;
        gPrefs.digitSpacing = dict[@"digitSpacing"] ? [dict[@"digitSpacing"] floatValue] : 4.0f;
        
        // Очистка кэша картинок при смене темы/настроек
        [sGifImageCache removeAllObjects];
        
        LS_EXECUTE_ON_MAIN_THREAD(^{
            if (gActiveClockView) {
                [gActiveClockView applyConfiguration];
                [gActiveClockView updateClock];
            }
        });
    }
}

static void PreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    LoadPreferences();
}

// MARK: - Контейнер GIF-часов
@implementation LSClockContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.tag = LSCLOCK_VIEW_TAG;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        _digitImageViews = [[NSMutableArray alloc] init];
        _lastTimeString = @"";
        
        // Контейнер для цифр
        _digitsContainerView = [[UIView alloc] initWithFrame:CGRectZero];
        _digitsContainerView.backgroundColor = [UIColor clearColor];
        [self addSubview:_digitsContainerView];
        
        // Дата
        _dateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _dateLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9f];
        _dateLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
        _dateLabel.textAlignment = NSTextAlignmentCenter;
        _dateLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        _dateLabel.layer.shadowOffset = CGSizeMake(0, 1.0);
        _dateLabel.layer.shadowRadius = 2.0f;
        _dateLabel.layer.shadowOpacity = 0.35f;
        [self addSubview:_dateLabel];
        
        // Батарея
        _batteryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _batteryLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8f];
        _batteryLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        _batteryLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_batteryLabel];
        
        [self applyConfiguration];
        [self updateClock];
        [self startTimer];
    }
    return self;
}

- (void)applyConfiguration {
    self.hidden = !gPrefs.enabled;
    self.dateLabel.hidden = !gPrefs.showDate;
    self.batteryLabel.hidden = !gPrefs.showBattery;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGRect bounds = [self bounds];
    if (CGRectIsEmpty(bounds)) return;
    
    CGFloat availableWidth = bounds.size.width;
    CGFloat digitH = gPrefs.digitHeight;
    CGFloat spacing = gPrefs.digitSpacing;
    NSUInteger count = self.digitImageViews.count;
    
    if (count == 0) return;
    
    // Расчет ширины каждой гифки на основе пропорций аспекта
    CGFloat totalDigitsWidth = 0.0f;
    NSMutableArray<NSNumber *> *widths = [NSMutableArray arrayWithCapacity:count];
    
    for (NSUInteger i = 0; i < count; i++) {
        UIImageView *iv = self.digitImageViews[i];
        UIImage *img = iv.image;
        CGFloat w = digitH * 0.65f; // стандартная пропорция по умолчанию
        if (img && img.size.height > 0) {
            w = digitH * (img.size.width / img.size.height);
        }
        [widths addObject:@(w)];
        totalDigitsWidth += w;
    }
    totalDigitsWidth += (count - 1) * spacing;
    
    // Центрирование контейнера цифр
    CGFloat startX = (availableWidth - totalDigitsWidth) / 2.0f;
    self.digitsContainerView.frame = CGRectMake(startX, 0, totalDigitsWidth, digitH);
    
    CGFloat curX = 0.0f;
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat w = [widths[i] floatValue];
        UIImageView *iv = self.digitImageViews[i];
        iv.frame = CGRectMake(curX, 0, w, digitH);
        curX += w + spacing;
    }
    
    CGFloat currentY = digitH + 6.0f;
    
    // Лейаут даты
    if (gPrefs.showDate && self.dateLabel.text.length > 0) {
        CGSize dateSize = [self.dateLabel sizeThatFits:CGSizeMake(availableWidth - 32, CGFLOAT_MAX)];
        self.dateLabel.frame = CGRectMake(16, currentY, availableWidth - 32, dateSize.height);
        currentY += dateSize.height + 4.0f;
    }
    
    // Лейаут батареи
    if (gPrefs.showBattery && self.batteryLabel.text.length > 0) {
        CGSize batSize = [self.batteryLabel sizeThatFits:CGSizeMake(availableWidth - 32, CGFLOAT_MAX)];
        self.batteryLabel.frame = CGRectMake(16, currentY, availableWidth - 32, batSize.height);
    }
}

- (void)startTimer {
    [self stopTimer];
    if (!gPrefs.enabled) return;
    
    NSTimeInterval interval = gPrefs.showSeconds ? 1.0 : 30.0;
    __weak typeof(self) weakSelf = self;
    
    self.timer = [NSTimer timerWithTimeInterval:interval repeats:YES block:^(NSTimer * _Nonnull timer) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf updateClock];
        }
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stopTimer {
    if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
    }
}

- (void)updateClock {
    if (!gPrefs.enabled) return;
    
    NSDate *now = [NSDate date];
    
    // Форматирование времени в строку (например "12:48:05" или "12:48")
    static NSDateFormatter *sTimeFormatter = nil;
    static NSDateFormatter *sDateFormatter = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sTimeFormatter = [[NSDateFormatter alloc] init];
        sDateFormatter = [[NSDateFormatter alloc] init];
    });
    
    [sTimeFormatter setLocale:[NSLocale currentLocale]];
    [sTimeFormatter setDateFormat:gPrefs.showSeconds ? @"HH:mm:ss" : @"HH:mm"];
    NSString *timeStr = [sTimeFormatter stringFromDate:now];
    
    // Обновляем гифки только если строка времени изменилась
    if (![timeStr isEqualToString:self.lastTimeString] || self.digitImageViews.count != timeStr.length) {
        self.lastTimeString = timeStr;
        NSUInteger len = timeStr.length;
        
        // Синхронизация количества UIImageView с количеством символов
        while (self.digitImageViews.count < len) {
            UIImageView *iv = [[UIImageView alloc] init];
            iv.contentMode = UIViewContentModeScaleAspectFit;
            [self.digitsContainerView addSubview:iv];
            [self.digitImageViews addObject:iv];
        }
        while (self.digitImageViews.count > len) {
            UIImageView *iv = [self.digitImageViews lastObject];
            [iv removeFromSuperview];
            [self.digitImageViews removeLastObject];
        }
        
        // Установка нужной GIF-картинки для каждого символа
        for (NSUInteger i = 0; i < len; i++) {
            unichar c = [timeStr characterAtIndex:i];
            NSString *resourceName = nil;
            if (c == ':') {
                resourceName = @"colon";
            } else if (c >= '0' && c <= '9') {
                resourceName = [NSString stringWithFormat:@"%C", c];
            } else {
                resourceName = @"space";
            }
            
            UIImage *targetImage = LSGetAnimatedGIF(resourceName);
            UIImageView *iv = self.digitImageViews[i];
            
            // ВАЖНО: Присваиваем image только если он изменился, чтобы не сбрасывать цикл GIF-анимации!
            if (iv.image != targetImage) {
                iv.image = targetImage;
            }
        }
        [self setNeedsLayout];
    }
    
    // Обновление даты
    if (gPrefs.showDate) {
        [sDateFormatter setLocale:[NSLocale currentLocale]];
        [sDateFormatter setDateFormat:@"EEEE, d MMMM"];
        self.dateLabel.text = [[sDateFormatter stringFromDate:now] capitalizedString];
    }
    
    // Обновление батареи
    if (gPrefs.showBattery) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float batLevel = [UIDevice currentDevice].batteryLevel;
        UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
        if (batLevel >= 0.0f) {
            NSInteger batPercent = (NSInteger)roundf(batLevel * 100.0f);
            NSString *stateGlyph = (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull) ? @" ⚡︎" : @"";
            self.batteryLabel.text = [NSString stringWithFormat:@"%ld%%%@", (long)batPercent, stateGlyph];
        }
    }
}

- (void)dealloc {
    [self stopTimer];
}

@end

// MARK: - Хуки SpringBoard

%hook SBFLockScreenDateView

- (void)layoutSubviews {
    %orig;
    if (!self) return;
    
    UIView *selfView = (UIView *)self;
    
    if (!gPrefs.enabled) {
        for (UIView *subview in [selfView subviews]) {
            if (subview.tag == LSCLOCK_VIEW_TAG) {
                [subview removeFromSuperview];
            } else {
                subview.alpha = 1.0f;
            }
        }
        return;
    }
    
    // Скрываем нативные часы
    for (UIView *subview in [selfView subviews]) {
        if (subview.tag != LSCLOCK_VIEW_TAG) {
            subview.alpha = 0.0f;
        }
    }
    
    LSClockContainerView *customView = (LSClockContainerView *)[selfView viewWithTag:LSCLOCK_VIEW_TAG];
    if (!customView) {
        customView = [[LSClockContainerView alloc] initWithFrame:[selfView bounds]];
        [selfView addSubview:customView];
        gActiveClockView = customView;
    } else {
        customView.frame = [selfView bounds];
        [customView setNeedsLayout];
    }
}

- (void)didMoveToWindow {
    %orig;
    if (!self) return;
    
    UIView *selfView = (UIView *)self;
    LSClockContainerView *customView = (LSClockContainerView *)[selfView viewWithTag:LSCLOCK_VIEW_TAG];
    
    if ([selfView window]) {
        [customView startTimer];
        [customView updateClock];
    } else {
        [customView stopTimer];
    }
}

%end

// MARK: - Управление состоянием экрана
%hook CSCoverSheetViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (gActiveClockView) {
        LS_EXECUTE_ON_MAIN_THREAD(^{
            if (gActiveClockView) {
                [gActiveClockView startTimer];
                [gActiveClockView updateClock];
            }
        });
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (gActiveClockView) {
        LS_EXECUTE_ON_MAIN_THREAD(^{
            if (gActiveClockView) {
                [gActiveClockView stopTimer];
            }
        });
    }
}

%end

// MARK: - Конструктор
%ctor {
    @autoreleasepool {
        LoadPreferences();
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            PreferencesChangedCallback,
            CFSTR(NOTIFY_PREFS_CHANGED),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        %init;
    }
}
