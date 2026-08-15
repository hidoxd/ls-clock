#import "Tweak.h"

static LSClockPreferences gPrefs;
// __weak предотвращает краш при обращении к деаллоцированному экземпляру часов
static __weak LSClockContainerView *gActiveClockView = nil;

// MARK: - Загрузка настроек
static void LoadPreferences(void) {
    @autoreleasepool {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
        
        // Дефолтные безопасные значения
        gPrefs.enabled = dict[@"enabled"] ? [dict[@"enabled"] boolValue] : YES;
        gPrefs.showSeconds = dict[@"showSeconds"] ? [dict[@"showSeconds"] boolValue] : YES;
        gPrefs.customDateFormatEnabled = dict[@"customDateFormatEnabled"] ? [dict[@"customDateFormatEnabled"] boolValue] : YES;
        gPrefs.hideOriginalClock = dict[@"hideOriginalClock"] ? [dict[@"hideOriginalClock"] boolValue] : YES;
        gPrefs.showBattery = dict[@"showBattery"] ? [dict[@"showBattery"] boolValue] : YES;
        
        NSInteger alignVal = dict[@"alignment"] ? [dict[@"alignment"] integerValue] : 1; // 0: Left, 1: Center, 2: Right
        gPrefs.alignment = (alignVal == 0) ? NSTextAlignmentLeft : ((alignVal == 2) ? NSTextAlignmentRight : NSTextAlignmentCenter);
        
        gPrefs.timeFontSize = dict[@"timeFontSize"] ? [dict[@"timeFontSize"] floatValue] : 68.0f;
        gPrefs.dateFontSize = dict[@"dateFontSize"] ? [dict[@"dateFontSize"] floatValue] : 17.0f;
        
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

// MARK: - Контейнер кастомных часов
@implementation LSClockContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.tag = LSCLOCK_VIEW_TAG;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        // Лейбл времени
        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.textColor = [UIColor whiteColor];
        _timeLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        _timeLabel.layer.shadowOffset = CGSizeMake(0, 1.5);
        _timeLabel.layer.shadowRadius = 3.0f;
        _timeLabel.layer.shadowOpacity = 0.35f;
        [self addSubview:_timeLabel];
        
        // Лейбл даты
        _dateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _dateLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9f];
        _dateLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        _dateLabel.layer.shadowOffset = CGSizeMake(0, 1.0);
        _dateLabel.layer.shadowRadius = 2.0f;
        _dateLabel.layer.shadowOpacity = 0.30f;
        [self addSubview:_dateLabel];
        
        // Лейбл батареи
        _batteryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _batteryLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8f];
        _batteryLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        [self addSubview:_batteryLabel];
        
        [self applyConfiguration];
        [self updateClock];
        [self startTimer];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGRect bounds = [self bounds];
    if (CGRectIsEmpty(bounds)) return;
    
    CGFloat padding = 16.0f;
    CGFloat contentWidth = bounds.size.width - (padding * 2.0f);
    if (contentWidth <= 0) return;
    
    CGFloat currentY = 0.0f;
    
    // Расчет фрейма времени
    CGSize timeSize = [self.timeLabel sizeThatFits:CGSizeMake(contentWidth, CGFLOAT_MAX)];
    self.timeLabel.frame = CGRectMake(padding, currentY, contentWidth, timeSize.height);
    currentY += timeSize.height + 2.0f;
    
    // Расчет фрейма даты
    if (self.dateLabel.text.length > 0) {
        CGSize dateSize = [self.dateLabel sizeThatFits:CGSizeMake(contentWidth, CGFLOAT_MAX)];
        self.dateLabel.frame = CGRectMake(padding, currentY, contentWidth, dateSize.height);
        currentY += dateSize.height + 4.0f;
    }
    
    // Расчет фрейма батареи
    if (gPrefs.showBattery && self.batteryLabel.text.length > 0) {
        CGSize batSize = [self.batteryLabel sizeThatFits:CGSizeMake(contentWidth, CGFLOAT_MAX)];
        self.batteryLabel.frame = CGRectMake(padding, currentY, contentWidth, batSize.height);
    }
}

- (void)applyConfiguration {
    self.timeLabel.textAlignment = gPrefs.alignment;
    self.dateLabel.textAlignment = gPrefs.alignment;
    self.batteryLabel.textAlignment = gPrefs.alignment;
    
    // Моноширинные цифры исключают дрожание текста при смене секунд
    self.timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:gPrefs.timeFontSize weight:UIFontWeightBold];
    self.dateLabel.font = [UIFont systemFontOfSize:gPrefs.dateFontSize weight:UIFontWeightMedium];
    
    self.batteryLabel.hidden = !gPrefs.showBattery;
    self.hidden = !gPrefs.enabled;
    [self setNeedsLayout];
}

- (void)startTimer {
    [self stopTimer];
    if (!gPrefs.enabled) return;
    
    NSTimeInterval interval = gPrefs.showSeconds ? 1.0 : 60.0;
    __weak typeof(self) weakSelf = self;
    
    self.timer = [NSTimer timerWithTimeInterval:interval repeats:YES block:^(NSTimer * _Nonnull timer) {
        typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf updateClock];
        }
    }];
    
    // Регистрация в общем режиме RunLoop для непрерывного тика при скролле
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
    
    // Кэширование форматтеров снижает нагрузку на CPU
    static NSDateFormatter *sTimeFormatter = nil;
    static NSDateFormatter *sDateFormatter = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sTimeFormatter = [[NSDateFormatter alloc] init];
        sDateFormatter = [[NSDateFormatter alloc] init];
    });
    
    [sTimeFormatter setLocale:[NSLocale currentLocale]];
    [sTimeFormatter setDateFormat:gPrefs.showSeconds ? @"HH:mm:ss" : @"HH:mm"];
    self.timeLabel.text = [sTimeFormatter stringFromDate:now];
    
    [sDateFormatter setLocale:[NSLocale currentLocale]];
    [sDateFormatter setDateFormat:gPrefs.customDateFormatEnabled ? @"EEEE, d MMMM" : @"d MMMM"];
    self.dateLabel.text = [[sDateFormatter stringFromDate:now] capitalizedString];
    
    if (gPrefs.showBattery) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float batLevel = [UIDevice currentDevice].batteryLevel;
        UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
        
        if (batLevel < 0.0f) {
            self.batteryLabel.text = @"";
        } else {
            NSInteger batPercent = (NSInteger)roundf(batLevel * 100.0f);
            NSString *stateGlyph = (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull) ? @" ⚡︎" : @"";
            self.batteryLabel.text = [NSString stringWithFormat:@"%ld%%%@", (long)batPercent, stateGlyph];
        }
    } else {
        self.batteryLabel.text = @"";
    }
    
    [self setNeedsLayout];
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
    
    // Явное приведение self к UIView исключает ошибку компиляции dot-синтаксиса
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
    
    if (gPrefs.hideOriginalClock) {
        for (UIView *subview in [selfView subviews]) {
            if (subview.tag != LSCLOCK_VIEW_TAG) {
                subview.alpha = 0.0f;
            }
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

// MARK: - Управление состоянием экрана (AOD / LockScreen)
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

// MARK: - Инициализация твика
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
