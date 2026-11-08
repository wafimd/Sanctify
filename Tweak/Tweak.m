#import <UIKit/UIKit.h>

static UIWindow *activeWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static void showAlert(void) {
    UIWindow *window = activeWindow();
    if (!window.rootViewController) return;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Sanctify"
        message:@"Step 1: Injection works."
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault
        handler:nil]];

    [window.rootViewController presentViewController:alert animated:YES completion:nil];
}

__attribute__((constructor))
static void SanctifyInit(void) {
    static BOOL shown = NO;
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            if (shown) return;
            shown = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                showAlert();
            });
        }];
}
