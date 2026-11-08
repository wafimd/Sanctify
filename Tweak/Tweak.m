#import <UIKit/UIKit.h>

static UIWindow *gAlertWindow = nil;

static void showAlert(void) {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;

    gAlertWindow = [[UIWindow alloc] initWithWindowScene:scene];
    gAlertWindow.rootViewController = [UIViewController new];
    gAlertWindow.windowLevel = UIWindowLevelAlert + 1;
    [gAlertWindow makeKeyAndVisible];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Sanctify"
        message:@"Step 1: Injection works."
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) { gAlertWindow = nil; }]];

    [gAlertWindow.rootViewController presentViewController:alert animated:YES completion:nil];
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
