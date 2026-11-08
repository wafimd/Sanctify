#import <UIKit/UIKit.h>

__attribute__((constructor))
static void SanctifyInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        if (!window) return;

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Sanctify"
            message:@"Step 1: Injection works."
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction
            actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault
            handler:nil]];

        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}
