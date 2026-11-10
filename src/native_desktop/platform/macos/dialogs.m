#import <AppKit/AppKit.h>
#include <stdint.h>

int64_t native_desktop_run_panel(void *raw_panel, void *raw_owner) {
    @autoreleasepool {
        NSSavePanel *panel = (__bridge NSSavePanel *)raw_panel;
        if (raw_owner == NULL) {
            return (int64_t)[panel runModal];
        }

        NSWindow *owner = (__bridge NSWindow *)raw_owner;
        __block NSInteger response = NSModalResponseCancel;
        __block BOOL finished = NO;
        [panel beginSheetModalForWindow:owner completionHandler:^(NSInteger result) {
            response = result;
            finished = YES;
        }];

        while (!finished) {
            [[NSRunLoop currentRunLoop]
                runMode:NSDefaultRunLoopMode
                beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        return (int64_t)response;
    }
}
