#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ── Token capture ─────────────────────────────────────────────────────────────

static NSString *gToken = nil;
static NSMutableSet *gSeenTokens = nil;

// Capture Bearer tokens from every *.spotify.com request.
// Validate each new token against the Web API; keep the first that returns 200.
static void tryToken(NSString *tok) {
    if (!tok || [gSeenTokens containsObject:tok]) return;
    [gSeenTokens addObject:tok];

    NSURL *url = [NSURL URLWithString:@"https://api.spotify.com/v1/me"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", tok]
       forHTTPHeaderField:@"Authorization"];
    // tag so our hook ignores this probe
    [req setValue:@"1" forHTTPHeaderField:@"X-Sanctify-Probe"];

    NSURLSession *s = [NSURLSession sharedSession];
    [[s dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)r;
        if (http.statusCode == 200 && !gToken) {
            gToken = tok;
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:@"SanctifyTokenReady" object:nil];
            });
        }
    }] resume];
}

typedef NSURLSessionDataTask *(*dataTaskIMP)(id, SEL, NSURLRequest *, void(^)(NSData*, NSURLResponse*, NSError*));
static dataTaskIMP orig_dataTask;

static NSURLSessionDataTask *hook_dataTask(id self, SEL _cmd, NSURLRequest *req,
                                            void (^handler)(NSData*, NSURLResponse*, NSError*)) {
    // Skip our own probe requests
    if (![req valueForHTTPHeaderField:@"X-Sanctify-Probe"]) {
        NSString *host = req.URL.host;
        if ([host hasSuffix:@"spotify.com"]) {
            NSString *auth = [req valueForHTTPHeaderField:@"Authorization"];
            if ([auth hasPrefix:@"Bearer "]) {
                NSString *tok = [auth substringFromIndex:7];
                dispatch_async(dispatch_get_global_queue(0, 0), ^{ tryToken(tok); });
            }
        }
    }
    return orig_dataTask(self, _cmd, req, handler);
}

static void installTokenHook(void) {
    gSeenTokens = [NSMutableSet new];
    Class cls = [[NSURLSession sharedSession] class];
    SEL sel = @selector(dataTaskWithRequest:completionHandler:);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        orig_dataTask = (dataTaskIMP)method_getImplementation(m);
        method_setImplementation(m, (IMP)hook_dataTask);
    }
}

// ── Spotify Web API fetch ─────────────────────────────────────────────────────

static void spotifyGET(NSString *path, void (^callback)(NSArray *items)) {
    if (!gToken) return;
    NSURL *url = [NSURL URLWithString:
        [NSString stringWithFormat:@"https://api.spotify.com/v1%@", path]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", gToken]
       forHTTPHeaderField:@"Authorization"];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (!d) return;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        NSArray *items = json[@"items"] ?: json[@"artists"][@"items"];
        if (items) dispatch_async(dispatch_get_main_queue(), ^{ callback(items); });
    }] resume];
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

    // subtitle: artist names or owner
    NSArray *artists = item[@"artists"];
    NSDictionary *owner = item[@"owner"];
    if (artists.count)
        self.detailTextLabel.text = [[artists valueForKey:@"name"] componentsJoinedByString:@", "];
    else if (owner)
        self.detailTextLabel.text = owner[@"display_name"];
    else
        self.detailTextLabel.text = item[@"type"];

    // thumbnail
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
    if (!gToken || !self.endpoint) return;
    spotifyGET(self.endpoint, ^(NSArray *items) {
        [self.rows removeAllObjects];
        [self.rows addObjectsFromArray:items];
        [self.table reloadData];
    });
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    SanctifyCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    [cell configure:self.rows[ip.row]];
    return cell;
}

@end

// ── Home VC (recently played + top artists) ───────────────────────────────────

@interface SanctifyHomeVC : UIViewController
@property (nonatomic) UIScrollView *scroll;
@end

@implementation SanctifyHomeVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Home";
    self.view.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"SanctifyTokenReady" object:nil queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) { [self loadAll]; }];

    if (gToken) [self loadAll];
}

- (void)loadAll {
    spotifyGET(@"/me/player/recently-played?limit=10", ^(NSArray *items) {
        [self addSection:@"Recently Played" items:items keyPath:@"track"];
    });
    spotifyGET(@"/me/top/artists?limit=10", ^(NSArray *items) {
        [self addSection:@"Your Top Artists" items:items keyPath:nil];
    });
}

- (void)addSection:(NSString *)title items:(NSArray *)rawItems keyPath:(NSString *)kp {
    NSArray *items = kp ? [rawItems valueForKeyPath:kp] : rawItems;

    // section label
    UILabel *hdr = [UILabel new];
    hdr.text = title;
    hdr.textColor = [UIColor whiteColor];
    hdr.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    hdr.translatesAutoresizingMaskIntoConstraints = NO;

    // horizontal scroll of thumbnails
    UIScrollView *row = [[UIScrollView alloc] init];
    row.showsHorizontalScrollIndicator = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    if (!self.scroll) {
        self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
        self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.scroll];
    }

    // Simple stack-based layout
    CGFloat y = self.scroll.subviews.lastObject ?
        CGRectGetMaxY(self.scroll.subviews.lastObject.frame) + 8 : 16;
    CGFloat W = self.view.bounds.size.width;

    hdr.frame = CGRectMake(16, y, W - 32, 28);
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
                if (d) dispatch_async(dispatch_get_main_queue(), ^{
                    img.image = [UIImage imageWithData:d];
                });
            });
        }

        UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(6, itemW + 4, itemW - 12, 36)];
        name.text = item[@"name"];
        name.textColor = [UIColor whiteColor];
        name.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        name.numberOfLines = 2;
        [card addSubview:name];

        [self.scroll addSubview:card];
        x += itemW + 12;
    }
    y += itemH + 20;
    self.scroll.contentSize = CGSizeMake(W, y);
}

@end

// ── Root tab bar ─────────────────────────────────────────────────────────────

static UINavigationController *navWrap(UIViewController *vc, NSString *title, NSString *icon) {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
                                                   image:[UIImage systemImageNamed:icon]
                                                     tag:0];
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

// ── Entry point ───────────────────────────────────────────────────────────────

static BOOL gTookOver = NO;

static void takeOver(void) {
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

__attribute__((constructor))
static void SanctifyInit(void) {
    installTokenHook();
    // Take over only after a valid token is confirmed — lets Spotify's
    // login flow complete first so the session is live when our UI appears.
    [[NSNotificationCenter defaultCenter]
        addObserverForName:@"SanctifyTokenReady"
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *n) { takeOver(); }];
}
