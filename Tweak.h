#import <UIKit/UIKit.h>

@class LSClockContainerView;

@interface CSProminentTimeView : UIView
@property (nonatomic, strong) LSClockContainerView *lsClockContainer;
- (void)ls_hideSystemSubviews;
- (void)ls_setupCustomClock;
@end
