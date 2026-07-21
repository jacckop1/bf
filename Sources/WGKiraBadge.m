#import "WGKiraBadge.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static NSString *const WGKiraTelegramUsername = @"iKiraPlus";
static NSString *const WGKiraBadgeCenterXKey = @"WGKiraBadgeCenterXRatio";
static NSString *const WGKiraBadgeCenterYKey = @"WGKiraBadgeCenterYRatio";

#pragma mark - Page detection

static NSString *WGKiraNormalizedText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) {
        return @"";
    }

    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.lowercaseString;
}

static BOOL WGKiraIsFeaturesTitle(NSString *text) {
    NSString *normalized = WGKiraNormalizedText(text);
    if (normalized.length == 0) {
        return NO;
    }

    static NSSet<NSString *> *titles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        titles = [NSSet setWithArray:@[
            @"whitegram features",
            @"مميزات وايت كرام",
            @"ميزات وايت كرام"
        ]];
    });
    return [titles containsObject:normalized];
}

static UIViewController *WGKiraTopViewController(UIViewController *controller) {
    if (!controller) {
        return nil;
    }

    UIViewController *presented = controller.presentedViewController;
    if (presented && !presented.isBeingDismissed) {
        return WGKiraTopViewController(presented);
    }

    if ([controller isKindOfClass:UINavigationController.class]) {
        return WGKiraTopViewController(((UINavigationController *)controller).visibleViewController);
    }

    if ([controller isKindOfClass:UITabBarController.class]) {
        return WGKiraTopViewController(((UITabBarController *)controller).selectedViewController);
    }

    NSArray<UIViewController *> *children = controller.childViewControllers;
    for (UIViewController *child in [children reverseObjectEnumerator]) {
        if (child.viewIfLoaded.window) {
            return WGKiraTopViewController(child);
        }
    }

    return controller;
}

static NSString *WGKiraTextFromView(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        return label.attributedText.string ?: label.text;
    }

    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        return [button attributedTitleForState:UIControlStateNormal].string ?: [button titleForState:UIControlStateNormal];
    }

    // Telegram/Whitegram may draw the navigation title through a Texture text view.
    static NSArray<NSString *> *knownTextClasses;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        knownTextClasses = @[
            @"_TtC7Display17ImmediateTextView",
            @"_TtC7Display17ImmediateTextNode",
            @"_TtC20TextNodeWithEntities29ImmediateTextNodeWithEntities"
        ];
    });

    BOOL knownClass = NO;
    for (NSString *className in knownTextClasses) {
        Class cls = objc_getClass(className.UTF8String);
        if (cls && [view isKindOfClass:cls]) {
            knownClass = YES;
            break;
        }
    }
    if (!knownClass) {
        return nil;
    }

    Class cursor = object_getClass(view);
    Ivar attributedTextIvar = NULL;
    while (cursor && !attributedTextIvar) {
        attributedTextIvar = class_getInstanceVariable(cursor, "attributedText");
        cursor = class_getSuperclass(cursor);
    }
    if (!attributedTextIvar) {
        return nil;
    }

    id value = object_getIvar(view, attributedTextIvar);
    return [value isKindOfClass:NSAttributedString.class] ? ((NSAttributedString *)value).string : nil;
}

static BOOL WGKiraViewContainsTitleNearTop(UIView *view, UIWindow *window, NSUInteger depth) {
    if (!view || !window || depth > 60 || view.hidden || view.alpha < 0.01) {
        return NO;
    }

    NSString *text = WGKiraTextFromView(view);
    if (WGKiraIsFeaturesTitle(text)) {
        CGRect frame = [view convertRect:view.bounds toView:window];
        CGFloat maximumTitleY = window.safeAreaInsets.top + 82.0;
        if (CGRectGetMidY(frame) <= maximumTitleY) {
            return YES;
        }
    }

    for (UIView *subview in view.subviews) {
        if (WGKiraViewContainsTitleNearTop(subview, window, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static UIWindow *WGKiraContentWindow(void) {
    UIApplication *application = UIApplication.sharedApplication;
    for (UIWindow *window in application.windows.reverseObjectEnumerator) {
        if (!window.hidden && window.alpha > 0.01 &&
            window.windowLevel == UIWindowLevelNormal && window.rootViewController) {
            return window;
        }
    }
    return nil;
}

static BOOL WGKiraFeaturesPageIsActive(UIWindow *window) {
    UIViewController *top = WGKiraTopViewController(window.rootViewController);
    if (WGKiraIsFeaturesTitle(top.title) || WGKiraIsFeaturesTitle(top.navigationItem.title)) {
        return YES;
    }

    UIView *titleView = top.navigationItem.titleView;
    if (titleView && WGKiraViewContainsTitleNearTop(titleView, window, 0)) {
        return YES;
    }

    // Safe fallback for Telegram builds that use a custom navigation bar and do not set UIViewController.title.
    return WGKiraViewContainsTitleNearTop(window, window, 0);
}

#pragma mark - Movable credit badge

@interface WGKiraBadgeView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, assign) CGPoint panStartCenter;
@property (nonatomic, strong) UILabel *markLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *usernameLabel;
@end

@implementation WGKiraBadgeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }

    self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    self.layer.cornerRadius = 18.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.22;
    self.layer.shadowRadius = 10.0;
    self.layer.shadowOffset = CGSizeMake(0.0, 4.0);
    self.clipsToBounds = NO;

    _markLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _markLabel.text = @"K+";
    _markLabel.textAlignment = NSTextAlignmentCenter;
    _markLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightHeavy];
    _markLabel.textColor = UIColor.whiteColor;
    _markLabel.backgroundColor = [UIColor colorWithRed:0.20 green:0.55 blue:1.0 alpha:1.0];
    _markLabel.layer.cornerRadius = 16.0;
    _markLabel.clipsToBounds = YES;
    [self addSubview:_markLabel];

    _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _nameLabel.text = @"كيرا بلس";
    _nameLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    _nameLabel.textColor = UIColor.whiteColor;
    _nameLabel.textAlignment = NSTextAlignmentNatural;
    _nameLabel.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self addSubview:_nameLabel];

    _usernameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _usernameLabel.text = @"@iKiraPlus";
    _usernameLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightMedium];
    _usernameLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.68];
    _usernameLabel.textAlignment = NSTextAlignmentLeft;
    [self addSubview:_usernameLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(wg_openTelegram:)];
    tap.delegate = self;
    [self addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(wg_handlePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.delegate = self;
    [self addGestureRecognizer:pan];

    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"كيرا بلس، @iKiraPlus";
    self.accessibilityHint = @"اضغط لفتح حساب تيليغرام، أو اسحب لتحريك الشعار";
    self.accessibilityTraits = UIAccessibilityTraitButton;

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat height = CGRectGetHeight(self.bounds);
    self.markLabel.frame = CGRectMake(10.0, (height - 32.0) * 0.5, 32.0, 32.0);
    CGFloat textX = 50.0;
    CGFloat textWidth = MAX(0.0, CGRectGetWidth(self.bounds) - textX - 12.0);
    self.nameLabel.frame = CGRectMake(textX, 8.0, textWidth, 19.0);
    self.usernameLabel.frame = CGRectMake(textX, 27.0, textWidth, 16.0);
}

- (void)wg_openTelegram:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) {
        return;
    }

    UIApplication *application = UIApplication.sharedApplication;
    NSURL *telegramURL = [NSURL URLWithString:[NSString stringWithFormat:@"tg://resolve?domain=%@", WGKiraTelegramUsername]];
    NSURL *webURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://t.me/%@", WGKiraTelegramUsername]];

    [application openURL:telegramURL options:@{} completionHandler:^(BOOL success) {
        if (!success) {
            [application openURL:webURL options:@{} completionHandler:nil];
        }
    }];
}

- (void)wg_handlePan:(UIPanGestureRecognizer *)recognizer {
    UIView *container = self.superview;
    if (!container) {
        return;
    }

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.panStartCenter = self.center;
        [UIView animateWithDuration:0.12 animations:^{
            self.transform = CGAffineTransformMakeScale(1.04, 1.04);
        }];
    }

    if (recognizer.state == UIGestureRecognizerStateChanged ||
        recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled) {
        CGPoint translation = [recognizer translationInView:container];
        CGPoint proposed = CGPointMake(self.panStartCenter.x + translation.x,
                                       self.panStartCenter.y + translation.y);
        self.center = [self wg_clampedCenter:proposed inView:container];
    }

    if (recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.16 animations:^{
            self.transform = CGAffineTransformIdentity;
        }];
        [self wg_savePositionInView:container];
    }
}

- (CGPoint)wg_clampedCenter:(CGPoint)center inView:(UIView *)container {
    UIEdgeInsets safe = container.safeAreaInsets;
    CGFloat margin = 10.0;
    CGFloat halfWidth = CGRectGetWidth(self.bounds) * 0.5;
    CGFloat halfHeight = CGRectGetHeight(self.bounds) * 0.5;

    CGFloat minimumX = safe.left + margin + halfWidth;
    CGFloat maximumX = CGRectGetWidth(container.bounds) - safe.right - margin - halfWidth;
    CGFloat minimumY = safe.top + margin + halfHeight;
    CGFloat maximumY = CGRectGetHeight(container.bounds) - safe.bottom - margin - halfHeight;

    if (maximumX < minimumX) {
        maximumX = minimumX;
    }
    if (maximumY < minimumY) {
        maximumY = minimumY;
    }

    return CGPointMake(MIN(MAX(center.x, minimumX), maximumX),
                       MIN(MAX(center.y, minimumY), maximumY));
}

- (void)wg_restoreOrSetDefaultPositionInView:(UIView *)container {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id savedX = [defaults objectForKey:WGKiraBadgeCenterXKey];
    id savedY = [defaults objectForKey:WGKiraBadgeCenterYKey];

    CGPoint center;
    if (savedX && savedY) {
        CGFloat xRatio = MIN(MAX([savedX doubleValue], 0.0), 1.0);
        CGFloat yRatio = MIN(MAX([savedY doubleValue], 0.0), 1.0);
        center = CGPointMake(CGRectGetWidth(container.bounds) * xRatio,
                             CGRectGetHeight(container.bounds) * yRatio);
    } else {
        UIEdgeInsets safe = container.safeAreaInsets;
        center = CGPointMake(CGRectGetWidth(container.bounds) - safe.right - CGRectGetWidth(self.bounds) * 0.5 - 12.0,
                             safe.top + CGRectGetHeight(self.bounds) * 0.5 + 62.0);
    }

    self.center = [self wg_clampedCenter:center inView:container];
}

- (void)wg_savePositionInView:(UIView *)container {
    CGFloat width = MAX(CGRectGetWidth(container.bounds), 1.0);
    CGFloat height = MAX(CGRectGetHeight(container.bounds), 1.0);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:self.center.x / width forKey:WGKiraBadgeCenterXKey];
    [defaults setDouble:self.center.y / height forKey:WGKiraBadgeCenterYKey];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

@end

static WGKiraBadgeView *WGKiraBadge = nil;

void WGUpdateKiraBadgeVisibility(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            WGUpdateKiraBadgeVisibility();
        });
        return;
    }

    UIWindow *window = WGKiraContentWindow();
    BOOL shouldShow = window && WGKiraFeaturesPageIsActive(window);

    if (!shouldShow) {
        WGKiraBadge.hidden = YES;
        return;
    }

    if (!WGKiraBadge) {
        WGKiraBadge = [[WGKiraBadgeView alloc] initWithFrame:CGRectMake(0.0, 0.0, 154.0, 50.0)];
    }

    if (WGKiraBadge.superview != window) {
        [WGKiraBadge removeFromSuperview];
        [window addSubview:WGKiraBadge];
        [WGKiraBadge wg_restoreOrSetDefaultPositionInView:window];
    } else {
        WGKiraBadge.center = [WGKiraBadge wg_clampedCenter:WGKiraBadge.center inView:window];
    }

    WGKiraBadge.hidden = NO;
    [window bringSubviewToFront:WGKiraBadge];
}
