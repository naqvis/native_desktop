#import <LocalAuthentication/LocalAuthentication.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>

int native_desktop_biometric_available(int *type_out) {
    @autoreleasepool {
        LAContext *context = [[LAContext alloc] init];
        NSError *error = nil;
        BOOL available = [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error];
        if (available && type_out) {
            *type_out = (int)[context biometryType];
        }
        [context release];
        return available ? 1 : 0;
    }
}

int native_desktop_biometric_authenticate(const char *reason_cstr, char **error_out) {
    @autoreleasepool {
        if (error_out) {
            *error_out = NULL;
        }

        LAContext *context = [[LAContext alloc] init];
        NSString *reason = [[NSString alloc] initWithUTF8String:reason_cstr];
        __block int result = 0;
        __block char *message = NULL;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                localizedReason:reason
                          reply:^(BOOL success, NSError *error) {
            result = success ? 1 : 0;
            if (!success && error) {
                message = strdup([[error localizedDescription] UTF8String]);
            }
            dispatch_semaphore_signal(semaphore);
        }];

        [reason release];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        dispatch_release(semaphore);
        [context release];

        if (error_out) {
            *error_out = message;
        } else if (message) {
            free(message);
        }
        return result;
    }
}
