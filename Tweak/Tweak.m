#import <UIKit/UIKit.h>

static void showBanner(void) {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;

    UIWindow *topWin = nil;
    for (UIWindow *w in scene.windows) {
        if (!topWin || w.windowLevel >= topWin.windowLevel) topWin = w;
    }
    if (!topWin) return;

    CGFloat W = topWin.bounds.size.width;
    UIView *banner = [[UIView alloc] initWithFrame:CGRectMake(0, 80, W, 56)];
    banner.backgroundColor = [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0];
    banner.layer.zPosition = 9999;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, W, 56)];
    lbl.text = @"⚡ Sanctify loaded";
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont boldSystemFontOfSize:20];
    [banner addSubview:lbl];

    [topWin addSubview:banner];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [banner removeFromSuperview];
    });
}

__attribute__((constructor))
static void SanctifyInit(void) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{ showBanner(); }
    );
}
