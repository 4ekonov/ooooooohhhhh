#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "OPCCView.h"

@interface SBControlCenterController : NSObject
+ (id)sharedInstance; - (void)dismissAnimated:(BOOL)a;
@end
@interface CCUIModularControlCenterOverlayViewController : UIViewController
- (void)opcc_sync;
@end

static const void *kOPCC = &kOPCC;

%hook CCUIModularControlCenterOverlayViewController

- (void)viewDidLoad {
    %orig;
    __weak UIViewController *weakSelf = self;
    OPCCView *v = [[OPCCView alloc] initWithFrame:self.view.bounds];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.dismissBlock = ^{
        id cc = [objc_getClass("SBControlCenterController") sharedInstance];
        if ([cc respondsToSelector:@selector(dismissAnimated:)]) [cc dismissAnimated:YES];
        else [weakSelf dismissViewControllerAnimated:YES completion:nil];
    };
    v.presentBlock = ^(UIViewController *vc) { [weakSelf presentViewController:vc animated:YES completion:nil]; };
    objc_setAssociatedObject(self, kOPCC, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.view addSubview:v];
}

- (void)viewDidLayoutSubviews { %orig; [self opcc_sync]; }

%new
- (void)opcc_sync {
    OPCCView *v = objc_getAssociatedObject(self, kOPCC);
    if (!v) return;
    for (UIView *s in self.view.subviews) if (s != v) s.hidden = YES;   // прячем оригинальный iOS CC
    v.frame = self.view.bounds;
    [self.view bringSubviewToFront:v];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self opcc_sync];
    [(OPCCView *)objc_getAssociatedObject(self, kOPCC) present];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [(OPCCView *)objc_getAssociatedObject(self, kOPCC) stop];
}

%end
