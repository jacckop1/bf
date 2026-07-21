#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "WGTranslations.h"
#import "WGKiraBadge.h"

/*
 * WhitegramArabic NodeFix v3
 *
 * Whitegram's settings rows are drawn by Telegram's Texture/AsyncDisplayKit
 * text nodes. Their Swift attributedText property is not exposed as an
 * Objective-C setAttributedText: selector, so Safe v2 could translate page
 * titles but not the rows themselves.
 *
 * This build keeps the stable UIKit hooks and adds a narrowly-scoped visible
 * node scanner. It only reads the known `attributedText` ivar from exact
 * Telegram text-node classes, replaces it when the complete source string is
 * present in our dictionary, then asks that node to redraw. It does not scan
 * every app class and it does not hook Swift initializers or login objects.
 */

#pragma mark - Runtime helpers

static void WGSendVoid(id object, SEL selector) {
    if (object && [object respondsToSelector:selector]) {
        ((void (*)(id, SEL))objc_msgSend)(object, selector);
    }
}

static id WGSendObject(id object, SEL selector) {
    if (object && [object respondsToSelector:selector]) {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    }
    return nil;
}

static Ivar WGFindIvar(Class cls, const char *name) {
    Class cursor = cls;
    while (cursor) {
        Ivar ivar = class_getInstanceVariable(cursor, name);
        if (ivar) {
            return ivar;
        }
        cursor = class_getSuperclass(cursor);
    }
    return NULL;
}

typedef void (*WGStrongIvarSetter)(id object, Ivar ivar, id value);

static void WGSetStrongObjectIvar(id object, Ivar ivar, id value) {
    static WGStrongIvarSetter strongSetter = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        strongSetter = (WGStrongIvarSetter)dlsym(RTLD_DEFAULT, "object_setIvarWithStrongDefault");
    });

    if (strongSetter) {
        strongSetter(object, ivar, value);
    } else {
        object_setIvar(object, ivar, value);
    }
}

static BOOL WGObjectIsKindOfRuntimeClass(id object, const char *className) {
    Class cls = objc_getClass(className);
    return cls && object && [object isKindOfClass:cls];
}

static BOOL WGIsKnownTextRenderable(id object) {
    if (!object) {
        return NO;
    }

    return WGObjectIsKindOfRuntimeClass(object, "_TtC7Display17ImmediateTextNode") ||
           WGObjectIsKindOfRuntimeClass(object, "_TtC20TextNodeWithEntities29ImmediateTextNodeWithEntities") ||
           WGObjectIsKindOfRuntimeClass(object, "_TtC7Display17ImmediateTextView") ||
           WGObjectIsKindOfRuntimeClass(object, "_TtCC22MultilineTextComponent22MultilineTextComponent4View") ||
           WGObjectIsKindOfRuntimeClass(object, "_TtCC13ComponentFlow4TextP33_C336015A3F4BB8AB8C7F5EBEFE5DB6BF12MeasureState");
}

static void WGRefreshRenderable(id object) {
    if (!object) {
        return;
    }

    WGSendVoid(object, NSSelectorFromString(@"invalidateCalculatedLayout"));
    WGSendVoid(object, NSSelectorFromString(@"setNeedsLayout"));
    WGSendVoid(object, NSSelectorFromString(@"setNeedsDisplay"));
    WGSendVoid(object, NSSelectorFromString(@"__setNeedsLayout"));
    WGSendVoid(object, NSSelectorFromString(@"__setNeedsDisplay"));

    id view = WGSendObject(object, NSSelectorFromString(@"view"));
    if ([view isKindOfClass:UIView.class]) {
        [(UIView *)view setNeedsLayout];
        [(UIView *)view setNeedsDisplay];
    }
}

static BOOL WGTranslateAttributedTextIvar(id object) {
    if (!WGIsKnownTextRenderable(object)) {
        return NO;
    }

    Ivar ivar = WGFindIvar(object_getClass(object), "attributedText");
    if (!ivar) {
        return NO;
    }

    id value = object_getIvar(object, ivar);
    if (![value isKindOfClass:NSAttributedString.class]) {
        return NO;
    }

    NSAttributedString *source = (NSAttributedString *)value;
    NSAttributedString *translated = WGArabicTranslateAttributedString(source);
    if (!translated || [translated.string isEqualToString:source.string]) {
        return NO;
    }

    WGSetStrongObjectIvar(object, ivar, translated);
    WGRefreshRenderable(object);
    return YES;
}

static void WGTranslateComponentTextView(id view) {
    if (!WGObjectIsKindOfRuntimeClass(view, "_TtCC13ComponentFlow4Text4View")) {
        return;
    }

    Ivar stateIvar = WGFindIvar(object_getClass(view), "measureState");
    if (!stateIvar) {
        return;
    }

    id state = object_getIvar(view, stateIvar);
    if (WGTranslateAttributedTextIvar(state)) {
        WGRefreshRenderable(view);
    }
}

#pragma mark - Visible Texture node scanner

static void WGScanDisplayNode(id node, NSMutableSet<NSValue *> *visited, NSUInteger depth) {
    if (!node || depth > 80 || visited.count > 3000) {
        return;
    }

    NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)node];
    if ([visited containsObject:identity]) {
        return;
    }
    [visited addObject:identity];

    WGTranslateAttributedTextIvar(node);

    id subnodes = WGSendObject(node, NSSelectorFromString(@"subnodes"));
    if ([subnodes isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)subnodes) {
            WGScanDisplayNode(child, visited, depth + 1);
        }
    }
}

static void WGTranslateExistingUIKitView(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.attributedText.length > 0) {
            NSAttributedString *translated = WGArabicTranslateAttributedString(label.attributedText);
            if (![translated.string isEqualToString:label.attributedText.string]) {
                label.attributedText = translated;
                label.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
                label.textAlignment = NSTextAlignmentNatural;
            }
        } else if (label.text.length > 0) {
            NSString *translated = WGArabicTranslateString(label.text);
            if (![translated isEqualToString:label.text]) {
                label.text = translated;
                label.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
                label.textAlignment = NSTextAlignmentNatural;
            }
        }
    } else if ([view isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)view;
        if (field.placeholder.length > 0) {
            NSString *translated = WGArabicTranslateString(field.placeholder);
            if (![translated isEqualToString:field.placeholder]) {
                field.placeholder = translated;
            }
        }
    } else if ([view isKindOfClass:UISearchBar.class]) {
        UISearchBar *searchBar = (UISearchBar *)view;
        if (searchBar.placeholder.length > 0) {
            NSString *translated = WGArabicTranslateString(searchBar.placeholder);
            if (![translated isEqualToString:searchBar.placeholder]) {
                searchBar.placeholder = translated;
            }
        }
    }
}

static void WGScanViewTree(UIView *view, NSMutableSet<NSValue *> *visitedNodes, NSUInteger depth) {
    if (!view || depth > 100) {
        return;
    }

    WGTranslateExistingUIKitView(view);
    WGTranslateAttributedTextIvar(view);
    WGTranslateComponentTextView(view);

    id node = WGSendObject(view, NSSelectorFromString(@"asyncdisplaykit_node"));
    if (node) {
        WGScanDisplayNode(node, visitedNodes, 0);
    }

    for (UIView *subview in view.subviews) {
        WGScanViewTree(subview, visitedNodes, depth + 1);
    }
}

static void WGScanAllVisibleWindows(void) {
    // Keep the credit badge independent from the selected translation language.
    WGUpdateKiraBadgeVisibility();

    if (!WGArabicLocalizationEnabled()) {
        return;
    }

    UIApplication *application = UIApplication.sharedApplication;
    NSMutableSet<NSValue *> *visitedNodes = [NSMutableSet set];

    for (UIWindow *window in application.windows) {
        if (!window.hidden && window.alpha > 0.01) {
            WGScanViewTree(window, visitedNodes, 0);
        }
    }
}

static BOOL WGScanScheduled = NO;

static void WGScheduleVisibleScan(void) {
    @synchronized (UIApplication.class) {
        if (WGScanScheduled) {
            return;
        }
        WGScanScheduled = YES;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        WGScanAllVisibleWindows();
        @synchronized (UIApplication.class) {
            WGScanScheduled = NO;
        }
    });
}

static void WGScheduleScanBurst(void) {
    WGScheduleVisibleScan();
    const NSTimeInterval delays[] = {0.05, 0.20, 0.60, 1.50};
    for (NSUInteger i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WGScheduleVisibleScan();
        });
    }
}

#pragma mark - Stable UIKit hooks

@interface NSBundle (WGArabicNodeFix)
- (NSString *)wg_nf_localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName;
@end

@implementation NSBundle (WGArabicNodeFix)
- (NSString *)wg_nf_localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName {
    NSString *result = [self wg_nf_localizedStringForKey:key value:value table:tableName];
    return WGArabicTranslateString(result);
}
@end

@interface UILabel (WGArabicNodeFix)
- (void)wg_nf_setText:(NSString *)text;
- (void)wg_nf_setAttributedText:(NSAttributedString *)text;
@end

@implementation UILabel (WGArabicNodeFix)
- (void)wg_nf_setText:(NSString *)text {
    NSString *translated = WGArabicTranslateString(text);
    [self wg_nf_setText:translated];
    if (text && ![translated isEqualToString:text]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        self.textAlignment = NSTextAlignmentNatural;
    }
}
- (void)wg_nf_setAttributedText:(NSAttributedString *)text {
    NSAttributedString *translated = WGArabicTranslateAttributedString(text);
    [self wg_nf_setAttributedText:translated];
    if (text && ![translated.string isEqualToString:text.string]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        self.textAlignment = NSTextAlignmentNatural;
    }
}
@end

@interface UIButton (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title forState:(UIControlState)state;
- (void)wg_nf_setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state;
@end

@implementation UIButton (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title forState:(UIControlState)state {
    NSString *translated = WGArabicTranslateString(title);
    [self wg_nf_setTitle:translated forState:state];
    if (title && ![translated isEqualToString:title]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    }
}
- (void)wg_nf_setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state {
    NSAttributedString *translated = WGArabicTranslateAttributedString(title);
    [self wg_nf_setAttributedTitle:translated forState:state];
    if (title && ![translated.string isEqualToString:title.string]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    }
}
@end

@interface UITextField (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder;
@end

@implementation UITextField (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder {
    [self wg_nf_setPlaceholder:WGArabicTranslateString(placeholder)];
}
@end

@interface UITextView (WGArabicNodeFix)
- (void)wg_nf_setText:(NSString *)text;
- (void)wg_nf_setAttributedText:(NSAttributedString *)text;
@end

@implementation UITextView (WGArabicNodeFix)
- (void)wg_nf_setText:(NSString *)text {
    [self wg_nf_setText:WGArabicTranslateString(text)];
}
- (void)wg_nf_setAttributedText:(NSAttributedString *)text {
    [self wg_nf_setAttributedText:WGArabicTranslateAttributedString(text)];
}
@end

@interface UINavigationItem (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title;
@end

@implementation UINavigationItem (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title {
    [self wg_nf_setTitle:WGArabicTranslateString(title)];
}
@end

@interface UIViewController (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title;
- (void)wg_nf_viewDidAppear:(BOOL)animated;
@end

@implementation UIViewController (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title {
    [self wg_nf_setTitle:WGArabicTranslateString(title)];
}
- (void)wg_nf_viewDidAppear:(BOOL)animated {
    [self wg_nf_viewDidAppear:animated];
    WGScheduleScanBurst();
}
@end

@interface UISearchBar (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder;
@end

@implementation UISearchBar (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder {
    [self wg_nf_setPlaceholder:WGArabicTranslateString(placeholder)];
}
@end

@interface UIAlertController (WGArabicNodeFix)
+ (instancetype)wg_nf_alertControllerWithTitle:(NSString *)title
                                        message:(NSString *)message
                                 preferredStyle:(UIAlertControllerStyle)preferredStyle;
@end

@implementation UIAlertController (WGArabicNodeFix)
+ (instancetype)wg_nf_alertControllerWithTitle:(NSString *)title
                                        message:(NSString *)message
                                 preferredStyle:(UIAlertControllerStyle)preferredStyle {
    return [self wg_nf_alertControllerWithTitle:WGArabicTranslateString(title)
                                        message:WGArabicTranslateString(message)
                                 preferredStyle:preferredStyle];
}
@end

@interface UIBarButtonItem (WGArabicNodeFix)
- (instancetype)wg_nf_initWithTitle:(NSString *)title
                              style:(UIBarButtonItemStyle)style
                             target:(id)target
                             action:(SEL)action;
@end

@implementation UIBarButtonItem (WGArabicNodeFix)
- (instancetype)wg_nf_initWithTitle:(NSString *)title
                              style:(UIBarButtonItemStyle)style
                             target:(id)target
                             action:(SEL)action {
    return [self wg_nf_initWithTitle:WGArabicTranslateString(title)
                               style:style
                              target:target
                              action:action];
}
@end

static void WGSwizzle(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) {
        return;
    }

    BOOL added = class_addMethod(cls,
                                 original,
                                 method_getImplementation(replacementMethod),
                                 method_getTypeEncoding(replacementMethod));
    if (added) {
        class_replaceMethod(cls,
                            replacement,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}

static void WGSwizzleClass(Class cls, SEL original, SEL replacement) {
    WGSwizzle(object_getClass(cls), original, replacement);
}

static void WGInstallUIKitHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WGSwizzle(NSBundle.class,
                  @selector(localizedStringForKey:value:table:),
                  @selector(wg_nf_localizedStringForKey:value:table:));

        WGSwizzle(UILabel.class, @selector(setText:), @selector(wg_nf_setText:));
        WGSwizzle(UILabel.class, @selector(setAttributedText:), @selector(wg_nf_setAttributedText:));
        WGSwizzle(UIButton.class, @selector(setTitle:forState:), @selector(wg_nf_setTitle:forState:));
        WGSwizzle(UIButton.class,
                  @selector(setAttributedTitle:forState:),
                  @selector(wg_nf_setAttributedTitle:forState:));
        WGSwizzle(UITextField.class, @selector(setPlaceholder:), @selector(wg_nf_setPlaceholder:));
        WGSwizzle(UITextView.class, @selector(setText:), @selector(wg_nf_setText:));
        WGSwizzle(UITextView.class, @selector(setAttributedText:), @selector(wg_nf_setAttributedText:));
        WGSwizzle(UINavigationItem.class, @selector(setTitle:), @selector(wg_nf_setTitle:));
        WGSwizzle(UIViewController.class, @selector(setTitle:), @selector(wg_nf_setTitle:));
        WGSwizzle(UIViewController.class, @selector(viewDidAppear:), @selector(wg_nf_viewDidAppear:));
        WGSwizzle(UISearchBar.class, @selector(setPlaceholder:), @selector(wg_nf_setPlaceholder:));
        WGSwizzleClass(UIAlertController.class,
                       @selector(alertControllerWithTitle:message:preferredStyle:),
                       @selector(wg_nf_alertControllerWithTitle:message:preferredStyle:));
        WGSwizzle(UIBarButtonItem.class,
                  @selector(initWithTitle:style:target:action:),
                  @selector(wg_nf_initWithTitle:style:target:action:));
    });
}

#pragma mark - Exact _ASDisplayView hook

static IMP WGOriginalASDisplayViewDidMoveToWindow = NULL;
static BOOL WGASDisplayViewHookInstalled = NO;

static void WGASDisplayViewDidMoveToWindow(id self, SEL _cmd) {
    if (WGOriginalASDisplayViewDidMoveToWindow) {
        ((void (*)(id, SEL))WGOriginalASDisplayViewDidMoveToWindow)(self, _cmd);
    }
    WGScheduleScanBurst();
}

static void WGInstallASDisplayViewHook(void) {
    @synchronized (UIApplication.class) {
        if (WGASDisplayViewHookInstalled) {
            return;
        }

        Class cls = objc_getClass("_ASDisplayView");
        SEL selector = sel_registerName("didMoveToWindow");
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        if (!method) {
            return;
        }

        WGOriginalASDisplayViewDidMoveToWindow = method_getImplementation(method);
        const char *types = method_getTypeEncoding(method);
        class_replaceMethod(cls, selector, (IMP)WGASDisplayViewDidMoveToWindow, types);
        WGASDisplayViewHookInstalled = YES;
    }
}

#pragma mark - Entry point

__attribute__((constructor))
static void WGArabicNodeFixEntryPoint(void) {
    @autoreleasepool {
        WGInstallUIKitHooks();
        WGInstallASDisplayViewHook();

        dispatch_async(dispatch_get_main_queue(), ^{
            WGInstallASDisplayViewHook();
            WGScheduleScanBurst();

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WGInstallASDisplayViewHook();
                WGScheduleScanBurst();
            });
        });
    }
}
