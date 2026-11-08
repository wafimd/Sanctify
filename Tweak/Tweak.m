#import <UIKit/UIKit.h>

// ── Tab content placeholder ──────────────────────────────────────────────────

@interface SanctifyPlaceholderVC : UIViewController
@property (nonatomic, copy) NSString *tabName;
@end

@implementation SanctifyPlaceholderVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];

    UILabel *lbl = [UILabel new];
    lbl.text = self.tabName;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:lbl];
    [NSLayoutConstraint activateConstraints:@[
        [lbl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [lbl.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}
@end

// ── Root tab bar ─────────────────────────────────────────────────────────────

@interface SanctifyRootVC : UITabBarController
@end

@implementation SanctifyRootVC

- (void)viewDidLoad {
    [super viewDidLoad];

    NSArray *tabs = @[
        @[@"Home",    @"house.fill"],
        @[@"Search",  @"magnifyingglass"],
        @[@"Library", @"books.vertical.fill"],
    ];

    NSMutableArray *vcs = [NSMutableArray new];
    for (NSArray *tab in tabs) {
        SanctifyPlaceholderVC *vc = [SanctifyPlaceholderVC new];
        vc.tabName = tab[0];
        vc.title   = tab[0];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.tabBarItem = [[UITabBarItem alloc]
            initWithTitle:tab[0]
                    image:[UIImage systemImageNamed:tab[1]]
                      tag:0];
        nav.navigationBar.prefersLargeTitles = YES;
        nav.navigationBar.barStyle = UIBarStyleBlack;
        nav.navigationBar.translucent = YES;
        [vcs addObject:nav];
    }
    self.viewControllers = vcs;

    // Appearance
    UITabBarAppearance *app = [UITabBarAppearance new];
    [app configureWithOpaqueBackground];
    app.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.tabBar.standardAppearance = app;
    if (@available(iOS 15, *)) self.tabBar.scrollEdgeAppearance = app;
    self.tabBar.tintColor = [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0];
}

@end

// ── Takeover ─────────────────────────────────────────────────────────────────

static void takeOver(void) {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    }
    if (!scene) return;

    UIWindow *win = nil;
    for (UIWindow *w in scene.windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = scene.windows.firstObject;
    if (!win) return;

    win.rootViewController = [SanctifyRootVC new];
}

__attribute__((constructor))
static void SanctifyInit(void) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{ takeOver(); }
    );
}
