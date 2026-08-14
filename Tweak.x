#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <rootless.h>

static WKWebView *lsClockWebView = nil;
static UIView *lsClockContainer = nil;

static NSString *lsClockHTMLPath(void) {
    return ROOT_PATH_NS(@"/Library/Application Support/LSClock/index.html");
}

static void LSShowClockInView(UIView *parent) {
    if (!parent || lsClockContainer) return;

    lsClockContainer = [[UIView alloc] init];
    lsClockContainer.backgroundColor = [UIColor clearColor];
    lsClockContainer.userInteractionEnabled = NO;
    lsClockContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:lsClockContainer];

    // Позиция: по центру, чуть выше середины
    [NSLayoutConstraint activateConstraints:@[
        [lsClockContainer.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
        [lsClockContainer.topAnchor constraintEqualToAnchor:parent.topAnchor constant:140],
        [lsClockContainer.widthAnchor constraintEqualToConstant:300],
        [lsClockContainer.heightAnchor constraintEqualToConstant:120],
    ]];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    [cfg.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    [cfg.preferences setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];

    lsClockWebView = [[WKWebView alloc] initWithFrame:lsClockContainer.bounds configuration:cfg];
    lsClockWebView.translatesAutoresizingMaskIntoConstraints = NO;
    lsClockWebView.scrollView.scrollEnabled = NO;
    lsClockWebView.userInteractionEnabled = NO;
    lsClockWebView.opaque = NO;
    lsClockWebView.backgroundColor = [UIColor clearColor];
    [lsClockContainer addSubview:lsClockWebView];

    [NSLayoutConstraint activateConstraints:@[
        [lsClockWebView.topAnchor constraintEqualToAnchor:lsClockContainer.topAnchor],
        [lsClockWebView.bottomAnchor constraintEqualToAnchor:lsClockContainer.bottomAnchor],
        [lsClockWebView.leadingAnchor constraintEqualToAnchor:lsClockContainer.leadingAnchor],
        [lsClockWebView.trailingAnchor constraintEqualToAnchor:lsClockContainer.trailingAnchor],
    ]];

    NSURL *htmlURL = [NSURL fileURLWithPath:lsClockHTMLPath()];
    NSURL *baseDir = [htmlURL URLByDeletingLastPathComponent];
    [lsClockWebView loadFileURL:htmlURL allowingReadAccessToURL:baseDir];
}

static void LSHideClock(void) {
    [lsClockContainer removeFromSuperview];
    lsClockContainer = nil;
    lsClockWebView = nil;
}

%hook SBFLockScreenViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *v = self.view;
        if (v) LSShowClockInView(v);
    });
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    LSHideClock();
}
%end
