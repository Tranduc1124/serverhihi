#import "TserverUUIDCallback.h"
#import "TserverCallbackDedup.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static Class gTserverDelegateClass = Nil;
static IMP gOpenURLOptionsOriginal = NULL;
static IMP gOpenURLSourceOriginal = NULL;
static IMP gHandleURLOldOriginal = NULL;
static IMP gDidFinishLaunchingOriginal = NULL;
static NSMutableDictionary<NSString *, NSValue *> *gTserverSceneOpenURLContextsOriginals = nil;
static NSMutableDictionary<NSString *, NSValue *> *gTserverSceneWillConnectOriginals = nil;
static NSMutableSet<NSString *> *gTserverSceneDelegateClasses = nil;
static BOOL gTserverCallbackBridgeObserverInstalled = NO;

static BOOL TserverHandleCallbackURL(NSURL *url) {
    if (!TserverCallbackURLShouldProcess(url)) return NO;
    BOOL accepted = [TserverUUIDCallback handleIncomingURL:url];
    TserverCallbackURLCommit(url, accepted);
    return accepted;
}

static BOOL TserverApplicationOpenURLOptions(id target, SEL command, UIApplication *application, NSURL *url, NSDictionary *options) {
    BOOL originalResult = NO;
    if (gOpenURLOptionsOriginal) {
        originalResult = ((BOOL (*)(id, SEL, UIApplication *, NSURL *, NSDictionary *))gOpenURLOptionsOriginal)(target, command, application, url, options);
    }
    BOOL tserverResult = TserverHandleCallbackURL(url);
    return originalResult || tserverResult;
}

static BOOL TserverApplicationOpenURLSource(id target,
                                             SEL command,
                                             UIApplication *application,
                                             NSURL *url,
                                             NSString *sourceApplication,
                                             id annotation) {
    BOOL originalResult = NO;
    if (gOpenURLSourceOriginal) {
        originalResult = ((BOOL (*)(id, SEL, UIApplication *, NSURL *, NSString *, id))gOpenURLSourceOriginal)(target,
                                                                                                                  command,
                                                                                                                  application,
                                                                                                                  url,
                                                                                                                  sourceApplication,
                                                                                                                  annotation);
    }
    BOOL tserverResult = TserverHandleCallbackURL(url);
    return originalResult || tserverResult;
}

static BOOL TserverApplicationHandleURL(id target, SEL command, UIApplication *application, NSURL *url) {
    BOOL originalResult = NO;
    if (gHandleURLOldOriginal) {
        originalResult = ((BOOL (*)(id, SEL, UIApplication *, NSURL *))gHandleURLOldOriginal)(target, command, application, url);
    }
    BOOL tserverResult = TserverHandleCallbackURL(url);
    return originalResult || tserverResult;
}

static BOOL TserverDidFinishLaunching(id target, SEL command, UIApplication *application, NSDictionary *options) {
    BOOL originalResult = YES;
    if (gDidFinishLaunchingOriginal) {
        originalResult = ((BOOL (*)(id, SEL, UIApplication *, NSDictionary *))gDidFinishLaunchingOriginal)(target,
                                                                                                               command,
                                                                                                               application,
                                                                                                               options);
    }
    NSURL *url = [options[UIApplicationLaunchOptionsURLKey] isKindOfClass:NSURL.class]
        ? options[UIApplicationLaunchOptionsURLKey]
        : nil;
    if (url) {
        dispatch_async(dispatch_get_main_queue(), ^{
            TserverHandleCallbackURL(url);
        });
    }
    return originalResult;
}

static void TserverSceneOpenURLContexts(id target, SEL command, id scene, NSSet *urlContexts) {
    IMP original = (IMP)[gTserverSceneOpenURLContextsOriginals[NSStringFromClass([target class])] pointerValue];
    if (original) {
        ((void (*)(id, SEL, id, NSSet *))original)(target, command, scene, urlContexts);
    }
    for (id context in urlContexts) {
        NSURL *url = [context valueForKey:@"URL"];
        TserverHandleCallbackURL(url);
    }
}

static void TserverSceneWillConnect(id target, SEL command, id scene, id session, id connectionOptions) {
    IMP original = (IMP)[gTserverSceneWillConnectOriginals[NSStringFromClass([target class])] pointerValue];
    if (original) {
        ((void (*)(id, SEL, id, id, id))original)(target, command, scene, session, connectionOptions);
    }
    @try {
        NSSet *urlContexts = [connectionOptions valueForKey:@"URLContexts"];
        for (id context in urlContexts) {
            NSURL *url = [context valueForKey:@"URL"];
            TserverHandleCallbackURL(url);
        }
    } @catch (__unused NSException *exception) {
    }
}

static void TserverInstallMethod(Class cls,
                                 SEL selector,
                                 IMP replacement,
                                 IMP *originalStorage,
                                 const char *fallbackTypes) {
    Method method = class_getInstanceMethod(cls, selector);
    const char *types = method ? method_getTypeEncoding(method) : fallbackTypes;
    if (class_addMethod(cls, selector, replacement, types)) {
        *originalStorage = method ? method_getImplementation(method) : NULL;
        return;
    }
    if (!method) {
        *originalStorage = NULL;
        return;
    }
    *originalStorage = method_getImplementation(method);
    method_setImplementation(method, replacement);
}

static void TserverInstallCallbackBridge(void) {
    id delegate = UIApplication.sharedApplication.delegate;
    if (!delegate) return;
    Class delegateClass = [delegate class];
    if (gTserverDelegateClass == delegateClass) return;
    if (gTserverDelegateClass != Nil) return;

    gTserverDelegateClass = delegateClass;
    TserverInstallMethod(delegateClass,
                         @selector(application:openURL:options:),
                         (IMP)TserverApplicationOpenURLOptions,
                         &gOpenURLOptionsOriginal,
                         "B@:@@@");
    TserverInstallMethod(delegateClass,
                         @selector(application:openURL:sourceApplication:annotation:),
                         (IMP)TserverApplicationOpenURLSource,
                         &gOpenURLSourceOriginal,
                         "B@:@@@@");
    TserverInstallMethod(delegateClass,
                         @selector(application:handleOpenURL:),
                         (IMP)TserverApplicationHandleURL,
                         &gHandleURLOldOriginal,
                         "B@:@@");
    TserverInstallMethod(delegateClass,
                         @selector(application:didFinishLaunchingWithOptions:),
                         (IMP)TserverDidFinishLaunching,
                         &gDidFinishLaunchingOriginal,
                         "B@:@@");
}

static void TserverInstallSceneCallbackBridge(void) {
    UIApplication *application = UIApplication.sharedApplication;
    if (![application respondsToSelector:@selector(connectedScenes)]) return;
    gTserverSceneOpenURLContextsOriginals = gTserverSceneOpenURLContextsOriginals ?: [NSMutableDictionary dictionary];
    gTserverSceneWillConnectOriginals = gTserverSceneWillConnectOriginals ?: [NSMutableDictionary dictionary];
    gTserverSceneDelegateClasses = gTserverSceneDelegateClasses ?: [NSMutableSet set];
    NSSet *scenes = [application valueForKey:@"connectedScenes"];
    for (id scene in scenes) {
        id delegate = [scene valueForKey:@"delegate"];
        if (!delegate) continue;
        Class delegateClass = [delegate class];
        NSString *className = NSStringFromClass(delegateClass);
        if ([gTserverSceneDelegateClasses containsObject:className]) continue;

        IMP openOriginal = NULL;
        IMP connectOriginal = NULL;
        TserverInstallMethod(delegateClass,
                             @selector(scene:openURLContexts:),
                             (IMP)TserverSceneOpenURLContexts,
                             &openOriginal,
                             "v@:@@");
        TserverInstallMethod(delegateClass,
                             @selector(scene:willConnectToSession:options:),
                             (IMP)TserverSceneWillConnect,
                             &connectOriginal,
                             "v@:@@@");
        if (openOriginal) gTserverSceneOpenURLContextsOriginals[className] = [NSValue valueWithPointer:(const void *)openOriginal];
        if (connectOriginal) gTserverSceneWillConnectOriginals[className] = [NSValue valueWithPointer:(const void *)connectOriginal];
        [gTserverSceneDelegateClasses addObject:className];
    }
}

static void TserverCallbackBridgeInstallOnMainThread(void) {
    TserverInstallCallbackBridge();
    TserverInstallSceneCallbackBridge();
    if (!gTserverCallbackBridgeObserverInstalled) {
        gTserverCallbackBridgeObserverInstalled = YES;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *note) {
            TserverInstallCallbackBridge();
            TserverInstallSceneCallbackBridge();
        }];
    }
}

extern "C" void TserverCallbackBridgePrepare(void) {
    if (NSThread.isMainThread) {
        TserverCallbackBridgeInstallOnMainThread();
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        TserverCallbackBridgeInstallOnMainThread();
    });
}
