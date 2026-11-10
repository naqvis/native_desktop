#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

@interface NativeDesktopNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

typedef void (*NativeDesktopNotificationEventCallback)(const char *identifier, const char *actionIdentifier);
static NativeDesktopNotificationEventCallback eventCallback = NULL;

@implementation NativeDesktopNotificationDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    if (completionHandler) {
        completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    if (eventCallback) {
        NSString *identifier = response.notification.request.identifier ?: @"";
        NSString *action = response.actionIdentifier ?: @"";
        if ([action isEqualToString:UNNotificationDefaultActionIdentifier]) {
            action = @"";
        }
        eventCallback(identifier.UTF8String, action.UTF8String);
    }
    if (completionHandler) {
        completionHandler();
    }
}
@end

static NativeDesktopNotificationDelegate *sharedDelegate = nil;

static void native_desktop_ensure_notification_delegate(void) {
    if (!sharedDelegate) {
        sharedDelegate = [[NativeDesktopNotificationDelegate alloc] init];
        [UNUserNotificationCenter currentNotificationCenter].delegate = sharedDelegate;
    }
}

extern "C" void native_desktop_notifications_set_event_callback(NativeDesktopNotificationEventCallback callback) {
    eventCallback = callback;
}

extern "C" int native_desktop_notifications_request_permission(void) {
    native_desktop_ensure_notification_delegate();

    __block int granted = 0;
    __block BOOL done = NO;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound;
    [center requestAuthorizationWithOptions:options completionHandler:^(BOOL success, NSError *error) {
        granted = success ? 1 : 0;
        done = YES;
    }];

    while (!done) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return granted;
}

extern "C" int native_desktop_notifications_permission_granted(void) {
    native_desktop_ensure_notification_delegate();

    __block int granted = 0;
    __block BOOL done = NO;
    [[UNUserNotificationCenter currentNotificationCenter]
        getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
            granted = settings.authorizationStatus == UNAuthorizationStatusAuthorized ? 1 : 0;
            done = YES;
        }];

    while (!done) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return granted;
}
