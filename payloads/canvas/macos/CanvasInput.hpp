#import <AppKit/AppKit.h>
#include <string>

static NSMutableArray *silEvents;
static NSSize drawableSize, lastWindowSize;
static void silPush(NSDictionary *event) {
  if (!silEvents)
    silEvents = [NSMutableArray new];
  [silEvents addObject:event];
}
static NSString *silCode(unsigned k) {
  static NSDictionary *codes = @{
    @0 : @"KeyA",
    @1 : @"KeyS",
    @2 : @"KeyD",
    @3 : @"KeyF",
    @4 : @"KeyH",
    @5 : @"KeyG",
    @6 : @"KeyZ",
    @7 : @"KeyX",
    @8 : @"KeyC",
    @9 : @"KeyV",
    @11 : @"KeyB",
    @12 : @"KeyQ",
    @13 : @"KeyW",
    @14 : @"KeyE",
    @15 : @"KeyR",
    @16 : @"KeyY",
    @17 : @"KeyT",
    @18 : @"Digit1",
    @19 : @"Digit2",
    @20 : @"Digit3",
    @21 : @"Digit4",
    @22 : @"Digit6",
    @23 : @"Digit5",
    @24 : @"Equal",
    @25 : @"Digit9",
    @26 : @"Digit7",
    @27 : @"Minus",
    @28 : @"Digit8",
    @29 : @"Digit0",
    @30 : @"BracketRight",
    @31 : @"KeyO",
    @32 : @"KeyU",
    @33 : @"BracketLeft",
    @34 : @"KeyI",
    @35 : @"KeyP",
    @36 : @"Enter",
    @37 : @"KeyL",
    @38 : @"KeyJ",
    @39 : @"Quote",
    @40 : @"KeyK",
    @41 : @"Semicolon",
    @42 : @"Backslash",
    @43 : @"Comma",
    @44 : @"Slash",
    @45 : @"KeyN",
    @46 : @"KeyM",
    @47 : @"Period",
    @48 : @"Tab",
    @49 : @"Space",
    @50 : @"Backquote",
    @51 : @"Backspace",
    @53 : @"Escape",
    @54 : @"MetaRight",
    @55 : @"MetaLeft",
    @56 : @"ShiftLeft",
    @57 : @"CapsLock",
    @58 : @"AltLeft",
    @59 : @"ControlLeft",
    @60 : @"ShiftRight",
    @61 : @"AltRight",
    @62 : @"ControlRight",
    @76 : @"NumpadEnter",
    @115 : @"Home",
    @116 : @"PageUp",
    @117 : @"Delete",
    @119 : @"End",
    @121 : @"PageDown",
    @123 : @"ArrowLeft",
    @124 : @"ArrowRight",
    @125 : @"ArrowDown",
    @126 : @"ArrowUp",
    @122 : @"F1",
    @120 : @"F2",
    @99 : @"F3",
    @118 : @"F4",
    @96 : @"F5",
    @97 : @"F6",
    @98 : @"F7",
    @100 : @"F8",
    @101 : @"F9",
    @109 : @"F10",
    @103 : @"F11",
    @111 : @"F12"
  };
  return codes[@(k)] ?: @"Unidentified";
}
static void silInput(NSWindow *window, NSEvent *e) {
  if (e.window != window)
    return;
  NSString *type = nil;
  BOOL key = NO, flags = NO;
  switch (e.type) {
  case NSEventTypeKeyDown:
    key = YES;
    type = @"keydown";
    break;
  case NSEventTypeKeyUp:
    key = YES;
    type = @"keyup";
    break;
  case NSEventTypeFlagsChanged:
    key = flags = YES;
    break;
  case NSEventTypeLeftMouseDown:
  case NSEventTypeRightMouseDown:
  case NSEventTypeOtherMouseDown:
    type = @"pointerdown";
    break;
  case NSEventTypeLeftMouseUp:
  case NSEventTypeRightMouseUp:
  case NSEventTypeOtherMouseUp:
    type = @"pointerup";
    break;
  case NSEventTypeMouseMoved:
  case NSEventTypeLeftMouseDragged:
  case NSEventTypeRightMouseDragged:
  case NSEventTypeOtherMouseDragged:
    type = @"pointermove";
    break;
  case NSEventTypeScrollWheel:
    type = @"wheel";
    break;
  default:
    return;
  }
  auto bits = e.modifierFlags;
  NSMutableDictionary *v = [@{
    @"ctrlKey" : @((bits & NSEventModifierFlagControl) != 0),
    @"altKey" : @((bits & NSEventModifierFlagOption) != 0),
    @"shiftKey" : @((bits & NSEventModifierFlagShift) != 0),
    @"metaKey" : @((bits & NSEventModifierFlagCommand) != 0)
  } mutableCopy];
  if (key) {
    NSString *code = silCode(e.keyCode), *name = code;
    int legacy = 0;
    static NSDictionary *special = @{
      @"Escape" : @27,
      @"Enter" : @13,
      @"Space" : @32,
      @"ArrowLeft" : @37,
      @"ArrowRight" : @39,
      @"ArrowUp" : @38,
      @"ArrowDown" : @40,
      @"Tab" : @9,
      @"Backspace" : @8,
      @"Delete" : @46,
      @"Home" : @36,
      @"End" : @35,
      @"PageUp" : @33,
      @"PageDown" : @34
    };
    if (flags) {
      auto mask = NSEventModifierFlagCapsLock;
      if ([code hasPrefix:@"Shift"]) {
        name = @"Shift";
        mask = NSEventModifierFlagShift;
        legacy = 16;
      } else if ([code hasPrefix:@"Control"]) {
        name = @"Control";
        mask = NSEventModifierFlagControl;
        legacy = 17;
      } else if ([code hasPrefix:@"Meta"]) {
        name = @"Meta";
        mask = NSEventModifierFlagCommand;
        legacy = 91;
      } else if ([code hasPrefix:@"Alt"]) {
        name = @"Alt";
        mask = NSEventModifierFlagOption;
        legacy = 18;
      }
      type = (bits & mask) ? @"keydown" : @"keyup";
    } else if (special[code]) {
      legacy = [special[code] intValue];
      if ([code isEqual:@"Space"])
        name = @" ";
    } else if ([code hasPrefix:@"F"] && code.length <= 3) {
      legacy = 111 + [[code substringFromIndex:1] intValue];
    } else {
      name = e.characters.length ? e.characters : code;
      NSString *plain = e.charactersIgnoringModifiers.uppercaseString;
      if (plain.length)
        legacy = [plain characterAtIndex:0];
    }
    v[@"key"] = name;
    v[@"code"] = code;
    v[@"keyCode"] = @(legacy);
    v[@"repeat"] = @(!flags && e.isARepeat);
  } else {
    NSView *view = window.contentView;
    NSPoint p = [view convertPoint:e.locationInWindow fromView:nil];
    NSSize sz = view.bounds.size;
    if (!drawableSize.width || !drawableSize.height)
      return;
    double scale = std::min(sz.width / drawableSize.width,
                            sz.height / drawableSize.height);
    if (scale <= 0)
      return;
    v[@"x"] = @((p.x - (sz.width - drawableSize.width * scale) / 2) / scale);
    v[@"y"] =
        @((sz.height - p.y - (sz.height - drawableSize.height * scale) / 2) /
          scale);
    const NSInteger b = e.buttonNumber;
    v[@"button"] = @([type isEqual:@"pointermove"] ? -1
                     : b == 1                      ? 2
                     : b == 2                      ? 1
                                                   : b);
    v[@"buttons"] = @(NSEvent.pressedMouseButtons);
    if ([type isEqual:@"wheel"]) {
      v[@"deltaX"] = @(-e.scrollingDeltaX);
      v[@"deltaY"] = @(-e.scrollingDeltaY);
      v[@"deltaMode"] = @(e.hasPreciseScrollingDeltas ? 0 : 1);
    }
  }
  v[@"type"] = type;
  silPush(v);
}
extern "C" const char *sil_canvas_events() {
  static thread_local std::string result;
  @autoreleasepool {
    NSData *d = [NSJSONSerialization dataWithJSONObject:(silEvents ?: @[])
                                                options:0
                                                  error:nil];
    result.assign((const char *)d.bytes, d.length);
    [silEvents removeAllObjects];
  }
  return result.c_str();
}
