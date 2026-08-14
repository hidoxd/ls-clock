#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <rootless.h>

@interface SBFLockScreenDateView : UIView
@property (nonatomic, retain) WKWebView *lsClockWebView;
- (void)setupLSClock;
@end

// Вшиваем гифки в HTML через Base64, чтобы обойти песочницу WebKit
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

// 1. Создаем WebView один раз при появлении вью на экране (без рекурсии и крашей)
- (void)didMoveToWindow {
    %orig;
    if (self.window && !self.lsClockWebView) {
        [self setupLSClock];
    }
}

// 2. В layoutSubviews только скрываем родные цифры и задаем координаты
- (void)layoutSubviews {
    %orig;

    for (UIView *subview in self.subviews) {
        if (subview != self.lsClockWebView) {
            subview.hidden = YES;
            subview.alpha = 0.0;
        }
    }

    if (self.lsClockWebView) {
        self.lsClockWebView.frame = self.bounds;
    }
}

%new
- (void)setupLSClock {
    if (self.lsClockWebView) return;

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    if (@available(iOS 14.0, *)) {
        config.defaultWebpagePreferences.allowsContentJavaScript = YES;
    }

    WKWebView *webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:config];
    webView.opaque = NO;
    webView.backgroundColor = [UIColor clearColor];
    webView.scrollView.backgroundColor = [UIColor clearColor];
    webView.scrollView.scrollEnabled = NO;
    webView.scrollView.bounces = NO;
    webView.userInteractionEnabled = NO;
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    self.lsClockWebView = webView;
    [self addSubview:webView];

    NSString *htmlPath = ROOT_PATH_NS(@"/Library/Application Support/LSClock/index.html");
    NSString *baseDir = ROOT_PATH_NS(@"/Library/Application Support/LSClock");

    if ([[NSFileManager defaultManager] fileExistsAtPath:htmlPath]) {
        NSString *inlinedHTML = inlinedHTMLContent(htmlPath, baseDir);
        if (inlinedHTML) {
            [webView loadHTMLString:inlinedHTML baseURL:nil];
        }
    }
}

%end
