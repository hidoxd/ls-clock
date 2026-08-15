#import "Tweak.h"

static LSClockPreferences gPrefs;
static LSClockContainerView *gActiveClockView = nil;

// MARK: - Загрузка настроек
static void LoadPreferences(void) {
    @autoreleasepool {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
        
        // Дефолтные значения (детерминированный фоллбек)
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

// MARK: - Реализация LSClockContainerView
@implementation LSClockContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.tag = LSCLOCK_VIEW_TAG;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        // Метка Времени
        _timeLabel = [[UILabel alloc] init];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _timeLabel.textColor = [UIColor whiteColor];
        _timeLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        _timeLabel.layer.shadowOffset = CGSizeMake(0, 1.5);
        _timeLabel.layer.shadowRadius = 3.0f;
        _timeLabel.layer.shadowOpacity = 0.35f;
        [self addSubview:_timeLabel];
        
        // Метка Даты
        _dateLabel = [[UILabel alloc] init];
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.9f];
        _dateLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        _dateLabel.layer.shadowOffset = CGSizeMake(0, 1.0);
        _dateLabel.layer.shadowRadius = 2.0f;
        _dateLabel.layer.shadowOpacity = 0.30f;
        [self addSubview:_dateLabel];
        
        // Метка Батареи
        _batteryLabel = [[UILabel alloc] init];
        _batteryLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _batteryLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8f];
        _batteryLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        [self addSubview:_batteryLabel];
        
        // Layout Constraints (AutoLayout предотвращает сбои ориентации на iPad/iPhone)
        [NSLayoutConstraint activateConstraints:@[
            [_timeLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_timeLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_timeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            
            [_dateLabel.topAnchor constraintEqualToAnchor:_timeLabel.bottomAnchor constant:4],
            [_dateLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_dateLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            
            [_batteryLabel.topAnchor constraintEqualToAnchor:_dateLabel.bottomAnchor constant:4],
            [_batteryLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_batteryLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [_batteryLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor]
        ]];
        
        [self applyConfiguration];
        [self updateClock];
        [self startTimer];
    }
    return self;
}

- (void)applyConfiguration {
    self.timeLabel.textAlignment = gPrefs.alignment;
    self.dateLabel.textAlignment = gPrefs.alignment;
    self.batteryLabel.textAlignment = gPrefs.alignment;
    
    // В iOS 18 используем моноширинные цифры для предотвращения дёргания лейаута при обновлении секунд
    self.timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:gPrefs.timeFontSize weight:UIFontWeightBold];
    self.dateLabel.font = [UIFont systemFontOfSize:gPrefs.dateFontSize weight:UIFontWeightMedium];
    
    self.batteryLabel.hidden = !gPrefs.showBattery;
    self.hidden = !gPrefs.enabled;
}

- (void)startTimer {
    [self stopTimer];
    if (!gPrefs.enabled) return;
    
    NSTimeInterval interval = gPrefs.showSeconds ? 1.0 : 60.0;
    __weak typeof(self) weakSelf = self;
    
    // Использование блока предотвращает retain cycle и краш при деаллокации
    self.timer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf updateClock];
    }];
    
    // NSRunLoopCommonModes гарантирует обновление часов во время скролла уведомлений
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
    
    // Форматирование времени
    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
    [timeFormatter setLocale:[NSLocale currentLocale]];
    [timeFormatter setDateFormat:gPrefs.showSeconds ? @"HH:mm:ss" : @"HH:mm"];
    self.timeLabel.text = [timeFormatter stringFromDate:now];
    
    // Форматирование даты
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:[NSLocale currentLocale]];
    [dateFormatter setDateFormat:gPrefs.customDateFormatEnabled ? @"EEEE, d MMMM" : @"d MMMM"];
    self.dateLabel.text = [[dateFormatter stringFromDate:now] capitalizedString];
    
    // Обновление батареи
    if (gPrefs.showBattery) {
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
        float batLevel = [UIDevice currentDevice].batteryLevel;
        NSInteger batPercent = (NSInteger)(batLevel * 100);
        UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
        
        NSString *stateGlyph = (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull) ? @" ⚡︎" : @"";
        if (batLevel < 0) {
            self.batteryLabel.text = @"";
        } else {
            self.batteryLabel.text = [NSString stringWithFormat:@"%ld%%%@", (long)batPercent, stateGlyph];
        }
    }
}

- (void)dealloc {
    [self stopTimer];
}

@end

// MARK: - Хуки SpringBoard / CoverSheet

%hook SBFLockScreenDateView

- (void)layoutSubviews {
    %orig;
    
    if (!self) return;
    
    LS_EXECUTE_ON_MAIN_THREAD(^{
        if (!gPrefs.enabled) {
            // Восстановление видимости нативных элементов при отключении твика
            for (UIView *subview in self.subviews) {
                if (subview.tag == LSCLOCK_VIEW_TAG) {
                    [subview removeFromSuperview];
                } else {
                    subview.alpha = 1.0f;
                }
            }
            return;
        }
        
        // Скрытие стандартных меток iOS 18 без разрушения структуры PosterKit
        if (gPrefs.hideOriginalClock) {
            for (UIView *subview in self.subviews) {
                if (subview.tag != LSCLOCK_VIEW_TAG) {
                    subview.alpha = 0.0f;
                }
            }
        }
        
        // Поиск или создание единственного экземпляра нашего вью
        LSClockContainerView *customView = (LSClockContainerView *)[self viewWithTag:LSCLOCK_VIEW_TAG];
        if (!customView) {
            customView = [[LSClockContainerView alloc] initWithFrame:self.bounds];
            [self addSubview:customView];
            gActiveClockView = customView;
        } else {
            customView.frame = self.bounds;
        }
    });
}

- (void)didMoveToWindow {
    %orig;
    if (!self) return;
    
    LS_EXECUTE_ON_MAIN_THREAD(^{
        LSClockContainerView *customView = (LSClockContainerView *)[self viewWithTag:LSCLOCK_VIEW_TAG];
        if (self.window) {
            [customView startTimer];
            [customView updateClock];
        } else {
            [customView stopTimer];
        }
    });
}

%end

// MARK: - Управление жизненным циклом (AOD и блокировка экрана)
%hook CSCoverSheetViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (gActiveClockView) {
        LS_EXECUTE_ON_MAIN_THREAD(^{
            [gActiveClockView startTimer];
            [gActiveClockView updateClock];
        });
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    // Остановка таймера при разблокировке устройства экономит заряд аккумулятора
    if (gActiveClockView) {
        LS_EXECUTE_ON_MAIN_THREAD(^{
            [gActiveClockView stopTimer];
        });
    }
}

%end

// MARK: - Инициализация твика
%ctor {
    @autoreleasepool {
        LoadPreferences();
        
        // Регистрация слушателя изменения настроек через Darwin Notification Center
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            PreferencesChangedCallback,
            CFSTR(NOTIFY_PREFS_CHANGED),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        %init(
            SBFLockScreenDateView = objc_getClass("SBFLockScreenDateView"),
            CSCoverSheetViewController = objc_getClass("CSCoverSheetViewController")
        );
    }
}
