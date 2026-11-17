#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

// Called by the Haxe main thread. The graphics surface has no JS or engine API.
static NSWindow *window;
extern "C" bool sil_canvas_present(int width,int height,const unsigned char *pixels) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        if (!window) {
            [app setActivationPolicy:NSApplicationActivationPolicyRegular];
            [app finishLaunching];
            window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,width,height)
                styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable)
                backing:NSBackingStoreBuffered defer:NO];
            window.releasedWhenClosed=NO; window.title=@"Silicanto";
            window.contentView.wantsLayer=YES;
            window.contentView.layer.backgroundColor=NSColor.blackColor.CGColor;
            window.contentView.layer.contentsGravity=kCAGravityResizeAspect;
            [window center]; [window makeKeyAndOrderFront:nil]; [app activateIgnoringOtherApps:YES];
        }
        NSEvent *event;
        while ((event=[app nextEventMatchingMask:NSEventMaskAny untilDate:NSDate.distantPast
                                           inMode:NSDefaultRunLoopMode dequeue:YES])) [app sendEvent:event];
        if (!window.isVisible) return false;
        NSData *data=[NSData dataWithBytes:pixels length:(NSUInteger)width*height*4];
        CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
        CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGImageRef image=CGImageCreate(width,height,8,32,width*4,color,
            (CGBitmapInfo)(kCGImageAlphaLast|kCGBitmapByteOrder32Big),provider,nullptr,false,kCGRenderingIntentDefault);
        window.contentView.layer.contents=(__bridge id)image;
        CGImageRelease(image); CGColorSpaceRelease(color); CGDataProviderRelease(provider);
        [CATransaction flush]; [app updateWindows]; return true;
    }
}
extern "C" void sil_canvas_close() { [window close]; }
