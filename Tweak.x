#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <rootless.h>

// Объявляем интерфейсы с родительскими классами UIKit, чтобы Clang знал свойства .view, .bounds и т.д.
@interface SBFLockScreenViewController : UIViewController
@property (nonatomic, retain) WKWebView *lsClockWebView;
@end

@interface SBFLockScreenDateView : UIView
@end

static WKWebView *clockWebView = nil;

%hook SBFLockScreenViewController

%property (nonatomic, retain) WKWebView *lsClockWebView;

- (void)viewDidLoad {
    %orig;

    // Проверяем, не создан ли уже WebView
    if (!self.lsClockWebView) {
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        
        // Корректный rootless-путь через макрос ROOT_PATH_NS
        NSString *htmlPath = ROOT_PATH_NS(@"/Library/Application Support/LSClock/index.html");
        NSString *baseDir = ROOT_PATH_NS(@"/Library/Application Support/LSClock");
        
        NSURL *fileURL = [NSURL fileURLWithPath:htmlPath];
        NSURL *readAccessURL = [NSURL fileURLWithPath:baseDir];

        // Размеры под область часов
        CGRect frame = CGRectMake(0, 100, self.view.bounds.size.width, 180);
        
        self.lsClockWebView = [[WKWebView alloc] initWithFrame:frame configuration:config];
        self.lsClockWebView.opaque = NO;
        self.lsClockWebView.backgroundColor = [UIColor clearColor];
        self.lsClockWebView.scrollView.backgroundColor = [UIColor clearColor];
        self.lsClockWebView.scrollView.scrollEnabled = NO;
        self.lsClockWebView.userInteractionEnabled = NO;
        self.lsClockWebView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        // Загружаем локальный HTML
        if ([[NSFileManager defaultManager] fileExistsAtPath:htmlPath]) {
            [self.lsClockWebView loadFileURL:fileURL allowingReadAccessToURL:readAccessURL];
        }

        [self.view addSubview:self.lsClockWebView];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (self.lsClockWebView) {
        self.lsClockWebView.frame = CGRectMake(0, 100, self.view.bounds.size.width, 180);
    }
}

%end

// Скрываем стандартные часы на экране блокировки
%hook SBFLockScreenDateView
- (void)setHidden:(BOOL)hidden {
    %orig(YES);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(0.0);
}
%end
