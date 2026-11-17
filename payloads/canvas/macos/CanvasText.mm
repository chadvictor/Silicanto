#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#include <cmath>
#include <vector>

// Float32 LE: advance, ink left, top, right, bottom, font ascent, font descent,
// mask width, mask height, followed by 8-bit glyph coverage in top-down rows.
extern "C" const unsigned char *sil_canvas_text(const char *family, float size,
                                                bool bold, bool italic,
                                                const char *utf8, float stroke,
                                                bool raster, int *length) {
  static thread_local std::vector<unsigned char> result;
  @autoreleasepool {
    CTFontRef base = CTFontCreateWithName(
        (__bridge CFStringRef)[NSString stringWithUTF8String:family], size,
        nullptr);
    auto traits =
        (bold ? kCTFontBoldTrait : 0) | (italic ? kCTFontItalicTrait : 0);
    CTFontRef font = traits ? CTFontCreateCopyWithSymbolicTraits(
                                  base, 0, nullptr, traits, traits)
                            : nullptr;
    if (!font)
      font = (CTFontRef)CFRetain(base);
    NSAttributedString *s = [[NSAttributedString alloc]
        initWithString:[NSString stringWithUTF8String:utf8]
            attributes:@{
              (__bridge NSString *)kCTFontAttributeName : (__bridge id)font,
              (__bridge NSString *)
              kCTForegroundColorFromContextAttributeName : @YES
            }];
    CTLineRef line =
        CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)s);
    CGRect ink =
        CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
    if (CGRectIsNull(ink))
      ink = CGRectZero;
    const float margin = stroke > 0 ? stroke / 2 : 0;
    const float left = floor(CGRectGetMinX(ink) - margin),
                top = floor(-CGRectGetMaxY(ink) - margin);
    const int width = ceil(CGRectGetMaxX(ink) + margin) - left,
              height = ceil(-CGRectGetMinY(ink) + margin) - top;
    bool valid = width >= 0 && height >= 0 && 1LL * width * height <= 16777216;
    const float header[] = {
        float(CTLineGetTypographicBounds(line, nullptr, nullptr, nullptr)),
        left,
        top,
        left + width,
        top + height,
        float(CTFontGetAscent(font)),
        float(CTFontGetDescent(font)),
        float(width),
        float(height)};
    result.assign(sizeof header + (raster && valid ? width * height : 0), 0);
    memcpy(result.data(), header, sizeof header);
    if (raster && valid && width && height) {
      CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
      CGContextRef ctx =
          CGBitmapContextCreate(result.data() + sizeof header, width, height, 8,
                                width, gray, kCGImageAlphaNone);
      if (ctx) {
        CGContextSetGrayFillColor(ctx, 1, 1);
        CGContextSetGrayStrokeColor(ctx, 1, 1);
        CGContextSetShouldSmoothFonts(ctx, false);
        if (stroke > 0) {
          CGContextSetTextDrawingMode(ctx, kCGTextStroke);
          CGContextSetLineWidth(ctx, stroke);
        }
        CGContextSetTextPosition(ctx, -left, height + top);
        CTLineDraw(line, ctx);
        CGContextRelease(ctx);
      }
      CGColorSpaceRelease(gray);
    }
    CFRelease(line);
    CFRelease(font);
    CFRelease(base);
    *length = valid ? (int)result.size() : 0;
    return result.data();
  }
}
