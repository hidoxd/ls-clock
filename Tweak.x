#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <rootless.h>

@interface SBFLockScreenDateView : UIView
@property (nonatomic, retain) WKWebView *lsClockWebView;
- (void)setupLSClockWebView;
- (void)reloadLSClockContent;
@end

// Встраиваем гифки прямо в HTML в формате Base64, чтобы обойти песочницу WebKit
static NSString *inlinedHTMLContent(NSString *htmlPath, NSString *baseDir) {
    NSError *error = nil;
    NSString *html = [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:&error];
    if (!html) return nil;

    NSMutableString *result = [html mutableCopy];
    NSArray *gifFiles = @[@"0.gif", @"1.gif", @"2.gif", @"3.gif", @"4.gif", @"5.gif", @"6.gif", @"7.gif", @"8.gif", @"9.gif", @"colon.gif"];

    for (NSString *fileName in gifFiles) {
        NSString *filePath = [baseDir stringByAppendingPathComponent:fileName];
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (data) {
            NSString *base64 = [data base64EncodedStringWithOptions:0];
            NSString *dataURI = [NSString stringWithFormat:@"data:image/gif;base64,%@", base64];
            [result replaceOccurrencesOfString:fileName withString:dataURI options:NSLiteralSearch range:NSMakeRange(0, result.length)];
        }
    }
    return result;
}

%hook SBFLockScreenDateView

%property (nonatomic, retain) WKWebView *lsClockWebView;

- (void)layoutSubviews {
    %orig;

    // 1. Скрываем только родные лейблы даты и времени внутри контейнера
    for (UIView *subview in self.subviews) {
        if (subview != self.lsClockWebView) {
            subview.hidden = YES;
            subview.alpha = 0.0;
        }
    }

    // 2. Инициализируем WebView при первом появлении
    if (!self.lsClockWebView) {
        [self setupLSClockWebView];
    }

    // 3. Растягиваем WebView точно по размеру блока часов
    if (self.lsClockWebView) {
        self.lsClockWebView.frame = self.bounds;
    }
}

%new
- (void)setupLSClockWebView {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.preferences.javaScriptEnabled = YES;

    self.lsClockWebView = [[WKWebView alloc] initWithFrame:self.bounds configuration:config];
    self.lsClockWebView.opaque = NO;
    self.lsClockWebView.backgroundColor = [UIColor clearColor];
    self.lsClockWebView.scrollView.backgroundColor = [UIColor clearColor];
    self.lsClockWebView.scrollView.scrollEnabled = NO;
    self.lsClockWebView.scrollView.bounces = NO;
    self.lsClockWebView.userInteractionEnabled = NO;
    self.lsClockWebView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [self addSubview:self.lsClockWebView];
    [self reloadLSClockContent];
}

%new
- (void)reloadLSClockContent {
    NSString *htmlPath = ROOT_PATH_NS(@"/Library/Application Support/LSClock/index.html");
    NSString *baseDir = ROOT_PATH_NS(@"/Library/Application Support/LSClock");

    if (![[NSFileManager defaultManager] fileExistsAtPath:htmlPath]) {
        return;
    }

    NSString *inlinedHTML = inlinedHTMLContent(htmlPath, baseDir);
    if (inlinedHTML) {
        [self.lsClockWebView loadHTMLString:inlinedHTML baseURL:nil];
    }
}

%end
