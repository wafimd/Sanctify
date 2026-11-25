#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>

static NSString *gToken = nil;
static NSString *gLastError = nil;

static void notifyTokenReady(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"SanctifyTokenReady" object:nil];
    });
}

// ── Token capture 1: OauthAccessTokenBridge (fires early at auth init) ────────

static NSString *(*orig_tokenGetter)(id, SEL);
static NSString *hook_tokenGetter(id self, SEL _cmd) {
    NSString *tok = orig_tokenGetter ? orig_tokenGetter(self, _cmd) : nil;
    if (tok.length > 0 && ![tok isEqualToString:gToken]) {
        gToken = tok;
        notifyTokenReady();
    }
    return tok;
}

static void installTokenHook(void) {
    Class cls = NSClassFromString(@"_TtC24Connectivity_SessionImplP33_831B98CC28223E431E21CD27ADD20AF222OauthAccessTokenBridge");
    if (!cls) {
        int count = objc_getClassList(NULL, 0);
        Class *buf = (Class *)malloc(sizeof(Class) * count);
        objc_getClassList(buf, count);
        for (int i = 0; i < count; i++) {
            const char *name = class_getName(buf[i]);
            if (name && strstr(name, "OauthAccessTokenBridge")) {
                cls = buf[i];
                break;
            }
        }
        free(buf);
    }
    if (!cls) return;
    SEL candidates[] = { @selector(accessToken), @selector(token) };
    for (int i = 0; i < 2; i++) {
        Method m = class_getInstanceMethod(cls, candidates[i]);
        if (!m) continue;
        orig_tokenGetter = (NSString *(*)(id, SEL))method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_tokenGetter);
        return;
    }
}

// ── Token capture 2: NSURLSessionTask.resume (fires on every Spotify request) ─
// Intercepts the Authorization header from outgoing requests — more reliable
// than waiting for the bridge selector to be called.

static IMP orig_taskResume = nil;
static void hook_taskResume(NSURLSessionTask *self, SEL _cmd) {
    NSString *auth = self.originalRequest.allHTTPHeaderFields[@"Authorization"];
    if ([auth hasPrefix:@"Bearer "]) {
        NSString *tok = [auth substringFromIndex:7];
        if (tok.length > 0 && ![tok isEqualToString:gToken]) {
            gToken = tok;
            notifyTokenReady();
        }
    }
    ((void (*)(id, SEL))orig_taskResume)(self, _cmd);
}

static void installURLSessionHook(void) {
    Class cls = [NSURLSessionTask class];
    SEL sel = @selector(resume);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    orig_taskResume = method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_taskResume);
}

// ── Spotify Web API fetch ─────────────────────────────────────────────────────

static void spotifyGET(NSString *path, void (^callback)(NSArray *items, NSString *error)) {
    if (!gToken) {
        dispatch_async(dispatch_get_main_queue(), ^{ callback(nil, @"No token yet"); });
        return;
    }
    NSURL *url = [NSURL URLWithString:
        [NSString stringWithFormat:@"https://api.spotify.com/v1%@", path]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", gToken]
       forHTTPHeaderField:@"Authorization"];
    [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSInteger status = [(NSHTTPURLResponse *)r statusCode];
        if (e || !d) {
            NSString *msg = [NSString stringWithFormat:@"Network error: %@", e.localizedDescription];
            dispatch_async(dispatch_get_main_queue(), ^{ callback(nil, msg); });
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        NSArray *items = json[@"items"];
        if (items) {
            dispatch_async(dispatch_get_main_queue(), ^{ callback(items, nil); });
        } else {
            NSString *msg = [NSString stringWithFormat:@"HTTP %ld: %@",
                (long)status, json[@"error"][@"message"] ?: [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]];
            dispatch_async(dispatch_get_main_queue(), ^{ callback(nil, msg); });
        }
    }] resume];
}

static void sanctifyPlay(NSString *uri) {
    if (!uri.length) return;
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:uri]
                                       options:@{}
                                   completionHandler:nil];
}

// ── Item cell ─────────────────────────────────────────────────────────────────

@interface SanctifyCell : UITableViewCell
- (void)configure:(NSDictionary *)item;
@end

@implementation SanctifyCell

- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:r];
    self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.textLabel.textColor = [UIColor whiteColor];
    self.detailTextLabel.textColor = [UIColor lightGrayColor];
    self.imageView.layer.cornerRadius = 4;
    self.imageView.clipsToBounds = YES;
    return self;
}

- (void)configure:(NSDictionary *)item {
    self.textLabel.text = item[@"name"];

    NSArray *artists = item[@"artists"];
    NSDictionary *owner = item[@"owner"];
    if (artists.count)
        self.detailTextLabel.text = [[artists valueForKey:@"name"] componentsJoinedByString:@", "];
    else if (owner)
        self.detailTextLabel.text = owner[@"display_name"];
    else
        self.detailTextLabel.text = item[@"type"];

    NSArray *images = item[@"images"] ?: item[@"album"][@"images"];
    NSString *imgUrl = [images lastObject][@"url"] ?: [images firstObject][@"url"];
    if (imgUrl) {
        NSURL *u = [NSURL URLWithString:imgUrl];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            NSData *d = [NSData dataWithContentsOfURL:u];
            if (d) dispatch_async(dispatch_get_main_queue(), ^{
                self.imageView.image = [UIImage imageWithData:d];
                [self setNeedsLayout];
            });
        });
    }
}

@end

// ── Generic list VC ───────────────────────────────────────────────────────────

@interface SanctifyListVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic) UITableView *table;
@property (nonatomic) NSMutableArray *rows;
@property (nonatomic, copy) NSString *endpoint;
@end

@implementation SanctifyListVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.rows = [NSMutableArray new];
    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = [UIColor clearColor];
    self.table.separatorColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.table.rowHeight = 64;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:[SanctifyCell class] forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.table];

    [self load];
    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"SanctifyTokenReady" object:nil queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) { [self load]; }];
}

- (void)load {
    if (!self.endpoint) return;
    spotifyGET(self.endpoint, ^(NSArray *items, NSString *error) {
        if (items) {
            [self.rows removeAllObjects];
            [self.rows addObjectsFromArray:items];
            [self.table reloadData];
        } else {
            self.title = [NSString stringWithFormat:@"%@ (%@)", self.title, error ?: @"empty"];
        }
    });
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SanctifyCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    [cell configure:self.rows[ip.row]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    sanctifyPlay(self.rows[ip.row][@"uri"]);
}

@end

// ── Home VC ───────────────────────────────────────────────────────────────────

static const void *kCardURIKey = &kCardURIKey;

@interface SanctifyHomeVC : UIViewController
@property (nonatomic) UIScrollView *scroll;
@property (nonatomic) UILabel *debugLabel;
@end

@implementation SanctifyHomeVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Home";
    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];

    // Debug label — shows token status and errors so we can diagnose silently-failing API calls
    self.debugLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 36)];
    self.debugLabel.textAlignment = NSTextAlignmentCenter;
    self.debugLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.debugLabel.textColor = [UIColor colorWithRed:1 green:0.8 blue:0 alpha:1];
    self.debugLabel.numberOfLines = 2;
    self.debugLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.debugLabel];
    [self updateDebug:@"Waiting for token…"];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
        target:self action:@selector(reload)];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"SanctifyTokenReady" object:nil queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) { [self reload]; }];

    if (gToken) [self reload];
}

- (void)updateDebug:(NSString *)msg {
    NSString *tokenStatus = gToken ? [NSString stringWithFormat:@"token: %@…", [gToken substringToIndex:MIN(8, gToken.length)]] : @"token: nil";
    self.debugLabel.text = [NSString stringWithFormat:@"%@ | %@", tokenStatus, msg];
}

- (void)reload {
    if (self.scroll) { [self.scroll removeFromSuperview]; self.scroll = nil; }
    [self updateDebug:@"Loading…"];
    [self loadAll];
}

- (void)loadAll {
    spotifyGET(@"/me/player/recently-played?limit=10", ^(NSArray *items, NSString *error) {
        if (error) { [self updateDebug:[NSString stringWithFormat:@"recently-played: %@", error]]; return; }
        [self addSection:@"Recently Played" items:items keyPath:@"track"];
    });
    spotifyGET(@"/me/top/artists?limit=10", ^(NSArray *items, NSString *error) {
        if (error) { [self updateDebug:[NSString stringWithFormat:@"top-artists: %@", error]]; return; }
        [self addSection:@"Your Top Artists" items:items keyPath:nil];
    });
}

- (void)addSection:(NSString *)title items:(NSArray *)rawItems keyPath:(NSString *)kp {
    NSArray *items = kp ? [rawItems valueForKeyPath:kp] : rawItems;
    if (!items.count) return;

    if (!self.scroll) {
        CGRect frame = self.view.bounds;
        frame.origin.y = 40; frame.size.height -= 40;
        self.scroll = [[UIScrollView alloc] initWithFrame:frame];
        self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.scroll];
        [self.view bringSubviewToFront:self.debugLabel];
    }

    CGFloat y = self.scroll.subviews.lastObject ?
        CGRectGetMaxY([(UIView *)self.scroll.subviews.lastObject frame]) + 8 : 16;
    CGFloat W = self.view.bounds.size.width;

    UILabel *hdr = [[UILabel alloc] initWithFrame:CGRectMake(16, y, W - 32, 28)];
    hdr.text = title;
    hdr.textColor = [UIColor whiteColor];
    hdr.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    [self.scroll addSubview:hdr];
    y += 36;

    CGFloat x = 16, itemW = 120, itemH = 148;
    for (NSDictionary *item in items) {
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(x, y, itemW, itemH)];
        card.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        card.layer.cornerRadius = 8;

        UIImageView *img = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, itemW, itemW)];
        img.contentMode = UIViewContentModeScaleAspectFill;
        img.clipsToBounds = YES;
        img.layer.cornerRadius = 8;
        img.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        img.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        [card addSubview:img];

        NSArray *images = item[@"images"];
        NSString *imgUrl = [images lastObject][@"url"] ?: [images firstObject][@"url"];
        if (imgUrl) {
            NSURL *u = [NSURL URLWithString:imgUrl];
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                NSData *d = [NSData dataWithContentsOfURL:u];
                if (d) dispatch_async(dispatch_get_main_queue(), ^{ img.image = [UIImage imageWithData:d]; });
            });
        }

        UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(6, itemW + 4, itemW - 12, 36)];
        name.text = item[@"name"];
        name.textColor = [UIColor whiteColor];
        name.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        name.numberOfLines = 2;
        [card addSubview:name];

        if (item[@"uri"]) {
            objc_setAssociatedObject(card, kCardURIKey, item[@"uri"], OBJC_ASSOCIATION_COPY_NONATOMIC);
            [card addGestureRecognizer:[[UITapGestureRecognizer alloc]
                initWithTarget:self action:@selector(cardTapped:)]];
        }

        [self.scroll addSubview:card];
        x += itemW + 12;
    }
    y += itemH + 20;
    self.scroll.contentSize = CGSizeMake(W, y);
}

- (void)cardTapped:(UITapGestureRecognizer *)gr {
    sanctifyPlay(objc_getAssociatedObject(gr.view, kCardURIKey));
}

@end

// ── Root tab bar ─────────────────────────────────────────────────────────────

static UINavigationController *navWrap(UIViewController *vc, NSString *title, NSString *icon) {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
                                                   image:[UIImage systemImageNamed:icon] tag:0];
    nav.navigationBar.prefersLargeTitles = YES;
    UINavigationBarAppearance *a = [UINavigationBarAppearance new];
    [a configureWithOpaqueBackground];
    a.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];
    a.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    a.largeTitleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    nav.navigationBar.standardAppearance = a;
    nav.navigationBar.scrollEdgeAppearance = a;
    return nav;
}

@interface SanctifyRootVC : UITabBarController
@end

@implementation SanctifyRootVC

- (void)viewDidLoad {
    [super viewDidLoad];

    SanctifyHomeVC *home = [SanctifyHomeVC new];

    SanctifyListVC *artists = [SanctifyListVC new];
    artists.title = @"Top Artists";
    artists.endpoint = @"/me/top/artists?limit=20";

    SanctifyListVC *library = [SanctifyListVC new];
    library.title = @"Library";
    library.endpoint = @"/me/playlists?limit=50";

    self.viewControllers = @[
        navWrap(home,    @"Home",    @"house.fill"),
        navWrap(artists, @"Artists", @"music.mic"),
        navWrap(library, @"Library", @"books.vertical.fill"),
    ];

    UITabBarAppearance *app = [UITabBarAppearance new];
    [app configureWithOpaqueBackground];
    app.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.tabBar.standardAppearance = app;
    if (@available(iOS 15, *)) self.tabBar.scrollEdgeAppearance = app;
    self.tabBar.tintColor = [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0];
}

@end

// ── Takeover ──────────────────────────────────────────────────────────────────

static BOOL gTookOver = NO;

static void sanctifyTakeOver(void) {
    if (gTookOver) return;
    gTookOver = YES;

    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    if (!scene) return;

    UIWindow *win = nil;
    for (UIWindow *w in scene.windows) if (w.isKeyWindow) { win = w; break; }
    if (!win) win = scene.windows.firstObject;
    if (!win) return;

    win.rootViewController = [SanctifyRootVC new];
}

// ── Settings injection ────────────────────────────────────────────────────────

@interface SanctifyLauncher : NSObject
+ (instancetype)shared;
- (void)openSanctify;
@end

@implementation SanctifyLauncher
+ (instancetype)shared {
    static SanctifyLauncher *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [SanctifyLauncher new]; });
    return s;
}
- (void)openSanctify {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"SanctifyAutoLaunch"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    sanctifyTakeOver();
}
@end

static void hookSpotifySettings(void) {
    // SPTSettingsViewController is legacy and no longer exists in modern Spotify.
    // RootSettingsViewController is the current class (confirmed from EeveeSpotify dossier § 2.8).
    Class cls = NSClassFromString(@"RootSettingsViewController");
    if (!cls) return;

    SEL sel = @selector(viewDidLoad);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;

    IMP orig = method_getImplementation(m);
    IMP hook = imp_implementationWithBlock(^(UIViewController *vc) {
        ((void (*)(id, SEL))orig)(vc, sel);

        UIBarButtonItem *btn = [[UIBarButtonItem alloc]
            initWithTitle:@"⚡ Sanctify"
                    style:UIBarButtonItemStylePlain
                   target:[SanctifyLauncher shared]
                   action:@selector(openSanctify)];
        btn.tintColor = [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0];
        vc.navigationItem.rightBarButtonItem = btn;
    });
    method_setImplementation(m, hook);
}

// ── Entry point ───────────────────────────────────────────────────────────────

__attribute__((constructor))
static void SanctifyInit(void) {
    installTokenHook();
    installURLSessionHook();
    hookSpotifySettings();

    // Auto-takeover only if user has already opted in via the settings button.
    // First-time users go through Settings → ⚡ Sanctify instead, which avoids
    // any timing conflict with iOS permission prompts on fresh installs.
    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"SanctifyTokenReady"
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) {
            if (![[NSUserDefaults standardUserDefaults] boolForKey:@"SanctifyAutoLaunch"]) return;
            // 1.5s delay lets Spotify finish rootViewController init before we replace it.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{ sanctifyTakeOver(); });
        }];
}
