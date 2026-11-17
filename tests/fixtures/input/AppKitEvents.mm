#import <AppKit/AppKit.h>
extern "C" bool sil_canvas_present(int, int, const unsigned char *);
extern "C" const char *sil_canvas_events();
extern "C" void sil_canvas_close();

int main() {
  @autoreleasepool {
    static unsigned char pixels[96 * 64 * 4] = {};
    if (!sil_canvas_present(96, 64, pixels))
      return 1;
    NSWindow *window = NSApp.keyWindow ?: NSApp.windows.firstObject;
    if (!window)
      return 2;
    sil_canvas_events();
    // Post into this application's Cocoa queue, with window-local coordinates.
    for (NSNumber *type in
         @[ @(NSEventTypeLeftMouseDown), @(NSEventTypeLeftMouseUp) ]) {
      NSEvent *e = [NSEvent mouseEventWithType:(NSEventType)type.integerValue
                                      location:NSMakePoint(12, 50)
                                 modifierFlags:0
                                     timestamp:1
                                  windowNumber:window.windowNumber
                                       context:nil
                                   eventNumber:0
                                    clickCount:1
                                      pressure:1];
      [NSApp postEvent:e atStart:NO];
    }
    [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown
                                            location:NSZeroPoint
                                       modifierFlags:NSEventModifierFlagShift
                                           timestamp:2
                                        windowNumber:window.windowNumber
                                             context:nil
                                          characters:@"A"
                         charactersIgnoringModifiers:@"a"
                                           isARepeat:NO
                                             keyCode:0]
             atStart:NO];
    sil_canvas_present(96, 64, pixels);
    puts(sil_canvas_events());
    sil_canvas_close();
  }
}
