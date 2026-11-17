#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#include <litehtml.h>
#include <litehtml/el_image.h>
#include <litehtml/render_item.h>

using namespace litehtml;
static CGRect rect(const position &p) {
  return CGRectMake(p.x, p.y, p.width, p.height);
}
static NSColor *color(const web_color &c) {
  return [NSColor colorWithSRGBRed:c.red / 255.
                             green:c.green / 255.
                              blue:c.blue / 255.
                             alpha:c.alpha / 255.];
}
static NSString *str(const char *s) {
  return [NSString stringWithUTF8String:s ?: ""] ?: @"";
}

class Page : public document_container {
public:
  position viewport;
  document::ptr doc;
  NSString *markup = nil;
  NSDictionary *images = nil;
  CGContextRef graphics = nullptr;
  uint_ptr create_font(const font_description &d, const document *,
                       font_metrics *m) override {
    NSString *family =
        [[str(d.family.c_str()) componentsSeparatedByString:@","] firstObject];
    NSFont *font = [NSFont fontWithName:family size:d.size]
                       ?: [NSFont systemFontOfSize:d.size];
    if (d.weight >= 600)
      font = [NSFontManager.sharedFontManager convertFont:font
                                              toHaveTrait:NSBoldFontMask];
    if (d.style == font_style_italic)
      font = [NSFontManager.sharedFontManager convertFont:font
                                              toHaveTrait:NSItalicFontMask];
    m->font_size = d.size;
    m->ascent = ceil(font.ascender);
    m->descent = ceil(-font.descender);
    m->height = m->ascent + m->descent;
    m->x_height = font.xHeight;
    m->ch_width = [@"0" sizeWithAttributes:@{NSFontAttributeName : font}].width;
    return (uint_ptr)CFBridgingRetain(font);
  }
  void delete_font(uint_ptr f) override {
    if (f)
      CFRelease((CFTypeRef)f);
  }
  pixel_t text_width(const char *s, uint_ptr f) override {
    return [str(s) sizeWithAttributes:@{
             NSFontAttributeName : (__bridge NSFont *)(void *)f
           }]
        .width;
  }
  void draw_text(uint_ptr, const char *s, uint_ptr f, web_color c,
                 const position &p) override {
    NSFont *font = (__bridge NSFont *)(void *)f;
    NSAttributedString *text = [[NSAttributedString alloc]
        initWithString:str(s)
            attributes:@{
              NSFontAttributeName : font,
              NSForegroundColorAttributeName : color(c)
            }];
    CTLineRef line =
        CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
    CGContextSaveGState(graphics);
    CGContextTranslateCTM(graphics, p.x, p.y + font.ascender);
    CGContextScaleCTM(graphics, 1, -1);
    CGContextSetTextMatrix(graphics, CGAffineTransformIdentity);
    CGContextSetTextPosition(graphics, 0, 0);
    CTLineDraw(line, graphics);
    CGContextRestoreGState(graphics);
    CFRelease(line);
  }
  pixel_t pt_to_px(float pt) const override { return pt * 96 / 72; }
  pixel_t get_default_font_size() const override { return 16; }
  const char *get_default_font_name() const override { return "Times"; }
  void draw_list_marker(uint_ptr, const list_marker &m) override {
    CGContextSetFillColorWithColor(graphics, color(m.color).CGColor);
    CGContextFillEllipseInRect(graphics, rect(m.pos));
  }
  void load_image(const char *, const char *, bool) override {}
  void get_image_size(const char *s, const char *, size &sz) override {
    NSArray *image = images[str(s)];
    if (image)
      sz = size([image[0] intValue], [image[1] intValue]);
  }
  void draw_image(uint_ptr, const background_layer &l, const std::string &s,
                  const std::string &) override {
    NSArray *img = images[str(s.c_str())];
    if (img.count < 3)
      return;
    size_t w = [img[0] intValue], h = [img[1] intValue];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:img[2]
                                                       options:0];
    if (!w || !h || data.length != w * h * 4)
      return;
    CGDataProviderRef provider =
        CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image =
        CGImageCreate(w, h, 8, 32, w * 4, space, kCGImageAlphaLast, provider,
                      nullptr, false, kCGRenderingIntentDefault);
    CGContextSaveGState(graphics);
    CGContextClipToRect(graphics, rect(l.clip_box));
    CGRect r = rect(l.origin_box);
    CGContextTranslateCTM(graphics, r.origin.x, r.origin.y + r.size.height);
    CGContextScaleCTM(graphics, 1, -1);
    CGContextDrawImage(graphics, CGRectMake(0, 0, r.size.width, r.size.height),
                       image);
    CGContextRestoreGState(graphics);
    CGImageRelease(image);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(space);
  }
  void draw_solid_fill(uint_ptr, const background_layer &l,
                       const web_color &c) override {
    CGContextSetFillColorWithColor(graphics, color(c).CGColor);
    CGContextFillRect(graphics, rect(l.clip_box));
  }
  CGGradientRef gradient(const background_layer::gradient_base &g) {
    NSMutableArray *colors = [NSMutableArray new];
    std::vector<CGFloat> stops;
    for (auto &p : g.color_points) {
      [colors addObject:(__bridge id)color(p.color).CGColor];
      stops.push_back(p.offset);
    }
    if (colors.count < 2)
      return nullptr;
    return CGGradientCreateWithColors(nullptr, (__bridge CFArrayRef)colors,
                                      stops.data());
  }
  void
  draw_linear_gradient(uint_ptr, const background_layer &l,
                       const background_layer::linear_gradient &g) override {
    auto gr = gradient(g);
    if (!gr)
      return;
    CGContextSaveGState(graphics);
    CGContextClipToRect(graphics, rect(l.clip_box));
    CGContextDrawLinearGradient(graphics, gr, CGPointMake(g.start.x, g.start.y),
                                CGPointMake(g.end.x, g.end.y), 3);
    CGContextRestoreGState(graphics);
    CGGradientRelease(gr);
  }
  void
  draw_radial_gradient(uint_ptr, const background_layer &l,
                       const background_layer::radial_gradient &g) override {
    auto gr = gradient(g);
    if (!gr)
      return;
    CGContextSaveGState(graphics);
    CGContextClipToRect(graphics, rect(l.clip_box));
    CGContextTranslateCTM(graphics, g.position.x, g.position.y);
    CGContextScaleCTM(graphics, 1, g.radius.y / std::max(1.f, g.radius.x));
    CGContextDrawRadialGradient(graphics, gr, CGPointZero, 0, CGPointZero,
                                g.radius.x, 3);
    CGContextRestoreGState(graphics);
    CGGradientRelease(gr);
  }
  void draw_conic_gradient(uint_ptr, const background_layer &l,
                           const background_layer::conic_gradient &g) override {
    auto gr = gradient(g);
    if (!gr)
      return;
    CGContextSaveGState(graphics);
    CGContextClipToRect(graphics, rect(l.clip_box));
    const CGFloat start = (g.angle - 90) * M_PI / 180;
    if (@available(macOS 14.0, *)) {
      CGContextDrawConicGradient(
          graphics, gr, CGPointMake(g.position.x, g.position.y), start);
    } else {
      // Older Core Graphics has no angular shading primitive. Draw adjacent
      // color-interpolated sectors.
      const auto clip = rect(l.clip_box);
      const CGFloat dx = std::max(fabs(CGRectGetMinX(clip) - g.position.x),
                                  fabs(CGRectGetMaxX(clip) - g.position.x));
      const CGFloat dy = std::max(fabs(CGRectGetMinY(clip) - g.position.y),
                                  fabs(CGRectGetMaxY(clip) - g.position.y));
      const CGFloat radius = std::hypot(dx, dy);
      size_t stop = 0;
      for (int i = 0; i < 720; i++) {
        const double t = (i + 0.5) / 720.;
        while (stop + 1 < g.color_points.size() - 1 &&
               g.color_points[stop + 1].offset < t)
          ++stop;
        const auto &lo = g.color_points[stop], &hi = g.color_points[stop + 1];
        const double mix =
            hi.offset <= lo.offset
                ? 1
                : std::clamp((t - lo.offset) / (hi.offset - lo.offset), 0., 1.);
        auto blend = [&](int a, int b) {
          return (a * (1 - mix) + b * mix) / 255.;
        };
        CGContextSetRGBFillColor(graphics, blend(lo.color.red, hi.color.red),
                                 blend(lo.color.green, hi.color.green),
                                 blend(lo.color.blue, hi.color.blue),
                                 blend(lo.color.alpha, hi.color.alpha));
        CGContextMoveToPoint(graphics, g.position.x, g.position.y);
        CGContextAddArc(graphics, g.position.x, g.position.y, radius,
                        start + 2 * M_PI * i / 720,
                        start + 2 * M_PI * (i + 1) / 720, false);
        CGContextClosePath(graphics);
        CGContextFillPath(graphics);
      }
    }
    CGContextRestoreGState(graphics);
    CGGradientRelease(gr);
  }
  void draw_borders(uint_ptr, const borders &b, const position &p,
                    bool) override {
    auto fill = [&](const border &v, CGRect r) {
      if (v.width > 0 && v.style != border_style_none &&
          v.style != border_style_hidden) {
        CGContextSetFillColorWithColor(graphics, color(v.color).CGColor);
        CGContextFillRect(graphics, r);
      }
    };
    fill(b.top, CGRectMake(p.x, p.y, p.width, b.top.width));
    fill(b.bottom,
         CGRectMake(p.x, p.bottom() - b.bottom.width, p.width, b.bottom.width));
    fill(b.left, CGRectMake(p.x, p.y, b.left.width, p.height));
    fill(b.right,
         CGRectMake(p.right() - b.right.width, p.y, b.right.width, p.height));
  }
  void set_caption(const char *) override {}
  void set_base_url(const char *) override {}
  void link(const document::ptr &, const element::ptr &) override {}
  void on_anchor_click(const char *, const element::ptr &) override {}
  void on_mouse_event(const element::ptr &, mouse_event) override {}
  void set_cursor(const char *) override {}
  void transform_text(string &s, text_transform t) override {
    NSString *n = str(s.c_str());
    if (t == text_transform_uppercase)
      s = n.uppercaseString.UTF8String;
    else if (t == text_transform_lowercase)
      s = n.lowercaseString.UTF8String;
    else if (t == text_transform_capitalize)
      s = n.capitalizedString.UTF8String;
  }
  void import_css(string &, const string &, string &) override {}
  void set_clip(const position &p, const border_radiuses &) override {
    CGContextSaveGState(graphics);
    CGContextClipToRect(graphics, rect(p));
  }
  void del_clip() override { CGContextRestoreGState(graphics); }
  void get_viewport(position &v) const override { v = viewport; }
  element::ptr create_element(const char *tag, const string_map &,
                              const document::ptr &doc) override {
    if (strcmp(tag, "canvas") == 0)
      return std::make_shared<el_image>(doc);
    return nullptr;
  }
  void get_media_features(media_features &m) const override {
    m.type = media_type_screen;
    m.width = m.device_width = viewport.width;
    m.height = m.device_height = viewport.height;
    m.color = 8;
    m.resolution = 96;
  }
  void get_language(string &l, string &c) const override {
    l = "en";
    c = "US";
  }
};
static void boxes(element::ptr el, NSMutableDictionary *result) {
  const char *key = el->get_attr("data-silicanto-node", nullptr);
  if (key) {
    auto p = el->get_placement();
    result[str(key)] = @[ @(p.x), @(p.y), @(p.width), @(p.height) ];
  }
  for (auto &child : el->children())
    boxes(child, result);
}
id sil_layout(NSString *op, NSArray *args) {
  static Page page;
  int w = [args[1] intValue], h = [args[2] intValue];
  if (w < 1 || h < 1 || 1LL * w * h > 16777216)
    [NSException raise:@"Layout" format:@"Invalid viewport"];
  page.images = args[3];
  if (![page.markup isEqual:args[0]] || page.viewport.width != w ||
      page.viewport.height != h) {
    page.markup = args[0];
    page.viewport = position(0, 0, w, h);
    page.doc = document::createFromString([page.markup UTF8String], &page);
    page.doc->render(w);
  }
  if ([op isEqual:@"boxes"]) {
    NSMutableDictionary *result = [NSMutableDictionary new];
    boxes(page.doc->root(), result);
    return result;
  }
  if ([op isEqual:@"hit"]) {
    float x = [args[6][0] floatValue], y = [args[6][1] floatValue];
    for (auto el =
             page.doc->root_render()->get_element_by_point(x, y, x, y, nullptr);
         el; el = el->parent()) {
      const char *id = el->get_attr("data-silicanto-node", nullptr);
      if (id)
        return @(atoi(id));
    }
    return @(-1);
  }
  if ([op isEqual:@"query"] || [op isEqual:@"computed"]) {
    auto root = page.doc->root();
    int index = [args[4] intValue];
    if (index == -2)
      return [op isEqual:@"query"] ? (id) @[] : (id) @{};
    auto scope = index <= 0 ? root
                            : root->select_one("[data-silicanto-node=\"" +
                                               std::to_string(index) + "\"]");
    if ([op isEqual:@"query"]) {
      NSMutableArray *ids = [NSMutableArray new];
      if (scope)
        for (const auto &e : scope->select_all([args[5] UTF8String])) {
          const char *id = e->get_attr("data-silicanto-node", nullptr);
          if (id && (index < 0 || e != scope))
            [ids addObject:@(atoi(id))];
        }
      return ids;
    }
    if (!scope)
      return @{};
    const auto &css = scope->css();
    auto rect = scope->get_placement();
    auto px = [](double n) { return [NSString stringWithFormat:@"%gpx", n]; };
    auto keyword = [](const char *words, int i) {
      return [str(words) componentsSeparatedByString:@";"][i];
    };
    auto rgba = [](web_color c) {
      return c.alpha == 255
                 ? [NSString stringWithFormat:@"rgb(%d, %d, %d)", c.red,
                                              c.green, c.blue]
                 : [NSString stringWithFormat:@"rgba(%d, %d, %d, %g)", c.red,
                                              c.green, c.blue, c.alpha / 255.];
    };
    return @{
      @"width" : px(rect.width),
      @"height" : px(rect.height),
      @"fontSize" : px(css.get_font_size()),
      @"color" : rgba(css.get_color()),
      @"backgroundColor" : rgba(css.get_bg().m_color),
      @"display" : keyword(style_display_strings, css.get_display()),
      @"position" : keyword(element_position_strings, css.get_position()),
      @"textAlign" : keyword(text_align_strings, css.get_text_align()),
      @"boxSizing" : keyword(box_sizing_strings, css.get_box_sizing()),
      @"flexGrow" : [@(css.get_flex_grow()) stringValue],
      @"flexShrink" : [@(css.get_flex_shrink()) stringValue]
    };
  }
  if (![op isEqual:@"paint"])
    [NSException raise:@"Layout" format:@"Unknown operation %@", op];
  NSMutableData *pixels = [NSMutableData dataWithLength:w * h * 4];
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  page.graphics = CGBitmapContextCreate(
      pixels.mutableBytes, w, h, 8, w * 4, space,
      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(space);
  CGContextSetRGBFillColor(page.graphics, 1, 1, 1, 1);
  CGContextFillRect(page.graphics, CGRectMake(0, 0, w, h));
  CGContextTranslateCTM(page.graphics, 0, h);
  CGContextScaleCTM(page.graphics, 1, -1);
  page.doc->draw(1, 0, 0, &page.viewport);
  CGContextRelease(page.graphics);
  page.graphics = nullptr;
  return [pixels base64EncodedStringWithOptions:0];
}
