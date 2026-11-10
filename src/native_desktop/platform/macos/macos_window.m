#import <Cocoa/Cocoa.h>

void nd_window_move(void *handle, double x, double y) {
    [(NSWindow *)handle setFrameOrigin:NSMakePoint(x, y)];
}

double nd_window_position_x(void *handle) {
    return [(NSWindow *)handle frame].origin.x;
}

double nd_window_position_y(void *handle) {
    return [(NSWindow *)handle frame].origin.y;
}

void nd_window_set_alpha(void *handle, double value) {
    [(NSWindow *)handle setAlphaValue:value];
}

void nd_window_order_front(void *handle) {
    [(NSWindow *)handle makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

void nd_window_show(void *handle) {
    [NSApp activateIgnoringOtherApps:YES];
    [(NSWindow *)handle makeKeyAndOrderFront:nil];
}

void nd_window_hide(void *handle) {
    [(NSWindow *)handle orderOut:nil];
}

void nd_window_minimize(void *handle) {
    [(NSWindow *)handle miniaturize:nil];
}

void nd_window_maximize(void *handle) {
    [(NSWindow *)handle performZoom:nil];
}

void nd_window_restore(void *handle) {
    if ([(NSWindow *)handle isMiniaturized]) {
        [(NSWindow *)handle deminiaturize:nil];
    } else if ([(NSWindow *)handle isZoomed]) {
        [(NSWindow *)handle performZoom:nil];
    }
}

int nd_window_is_minimized(void *handle) {
    return [(NSWindow *)handle isMiniaturized] ? 1 : 0;
}

int nd_window_is_maximized(void *handle) {
    return [(NSWindow *)handle isZoomed] ? 1 : 0;
}

int nd_window_is_fullscreen(void *handle) {
    NSWindow *window = (NSWindow *)handle;
    NSUInteger mask = [window styleMask];
    return (mask & NSWindowStyleMaskFullScreen) ? 1 : 0;
}

void nd_window_toggle_fullscreen(void *handle) {
    [(NSWindow *)handle toggleFullScreen:nil];
}

void nd_window_set_fullscreen(void *handle, int fullscreen) {
    int current = nd_window_is_fullscreen(handle);
    if (current != fullscreen) {
        [(NSWindow *)handle toggleFullScreen:nil];
    }
}

void nd_window_set_frameless(void *handle, int frameless) {
    NSWindow *window = (NSWindow *)handle;
    NSUInteger mask = [window styleMask];
    if (frameless) {
        mask &= ~(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable);
        mask |= NSWindowStyleMaskFullSizeContentView;
    } else {
        mask |= NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                NSWindowStyleMaskFullSizeContentView;
    }
    [window setStyleMask:mask];
    [window display];
}

int nd_window_is_frameless(void *handle) {
    NSWindow *window = (NSWindow *)handle;
    NSUInteger mask = [window styleMask];
    return (mask & NSWindowStyleMaskTitled) == 0 ? 1 : 0;
}

void nd_window_set_transparent(void *handle, int transparent) {
    NSWindow *window = (NSWindow *)handle;
    if (transparent) {
        [window setOpaque:NO];
        [window setBackgroundColor:[NSColor clearColor]];
    } else {
        [window setOpaque:YES];
        [window setBackgroundColor:[NSColor windowBackgroundColor]];
    }
}

void nd_window_set_modal(void *parent, void *child, int modal) {
    [(NSWindow *)parent setIgnoresMouseEvents:modal ? YES : NO];
}

void nd_window_set_accepts_mouse_events(void *handle, int accepts) {
    [(NSWindow *)handle setIgnoresMouseEvents:accepts ? NO : YES];
}
