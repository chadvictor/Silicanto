#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include "EXGLNativeApi.h"
#include "EXGLContextManager.h"
#include "EXGLNativeContext.h"
#include "EXPlatformUtils.h"
#include <hermes/hermes.h>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <vector>

namespace jsi = facebook::jsi;
using Clock = std::chrono::steady_clock;
extern "C" SHUnit *sh_export_app();
namespace expo::gl_cpp {
void EXiOSLog(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
  fputc('\n', stderr);
}
EXiOSOperatingSystemVersion EXiOSGetOperatingSystemVersion() {
  auto v = [[NSProcessInfo processInfo] operatingSystemVersion];
  return {v.majorVersion, v.minorVersion, v.patchVersion};
}
}

static void requireEGL(bool ok, const char *operation) {
  if (!ok) throw std::runtime_error(std::string(operation) + " failed, EGL " + std::to_string(eglGetError()));
}

struct Surface {
  NSWindow *window = nil;
  CAMetalLayer *layer = nil;
  EGLDisplay display = EGL_NO_DISPLAY;
  EGLContext context = EGL_NO_CONTEXT;
  EGLSurface surface = EGL_NO_SURFACE;
  EGLConfig config = nullptr;
  int width = 300, height = 150;
  EXGLContextId id = 0;

  explicit Surface(bool visible) {
    if (visible) {
      [NSApplication sharedApplication];
      [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
      window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,width,height)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
      [window setReleasedWhenClosed:NO];
      [window setTitle:[[NSProcessInfo processInfo] processName]];
      layer = [CAMetalLayer layer];
      window.contentView.wantsLayer = YES;
      window.contentView.layer = layer;
      [window center];
    }
  }

  void initialize(jsi::Runtime &rt, bool antialias) {
    const EGLint attrs[] = {EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE, EGL_NONE};
    auto platform = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(eglGetProcAddress("eglGetPlatformDisplayEXT"));
    if (!platform) throw std::runtime_error("ANGLE platform unavailable");
    display = platform(EGL_PLATFORM_ANGLE_ANGLE, nullptr, attrs);
    requireEGL(eglInitialize(display, nullptr, nullptr), "eglInitialize(Metal)");
    EGLint configAttrs[] = {EGL_SURFACE_TYPE, window ? EGL_WINDOW_BIT : EGL_PBUFFER_BIT,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
      EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 24, EGL_STENCIL_SIZE, 8,
      EGL_SAMPLES, antialias ? 4 : 0, EGL_NONE};
    EGLint count = 0;
    requireEGL(eglChooseConfig(display, configAttrs, &config, 1, &count), "eglChooseConfig");
    if (!count && antialias) {
      configAttrs[17] = 0;
      requireEGL(eglChooseConfig(display, configAttrs, &config, 1, &count), "eglChooseConfig");
    }
    if (!count) throw std::runtime_error("Missing ES3 Metal pixel format");
    const EGLint ctxAttrs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, ctxAttrs);
    requireEGL(context != EGL_NO_CONTEXT, "eglCreateContext");
    if (window) surface = eglCreateWindowSurface(display, config, (__bridge void *)layer, nullptr);
    resize(width, height);
    fprintf(stderr, "GPU %s\n", glGetString(GL_RENDERER));
    id = EXGLContextCreate();
    auto [state, lock] = expo::gl_cpp::ContextGet(id);
    state->prepareContext(rt, [state] { state->flush(); });
  }

  void resize(int w, int h) {
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384) throw std::runtime_error("Canvas size outside supported range (1..16384)");
    width = w; height = h;
    if (window) {
      [window setContentSize:NSMakeSize(w,h)];
      layer.drawableSize = CGSizeMake(w,h);
    }
    if (context == EGL_NO_CONTEXT) return;
    if (!window) {
      if (surface != EGL_NO_SURFACE) {
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroySurface(display, surface);
      }
      const EGLint attrs[] = {EGL_WIDTH,w,EGL_HEIGHT,h,EGL_NONE};
      surface = eglCreatePbufferSurface(display, config, attrs);
    }
    requireEGL(surface != EGL_NO_SURFACE, "eglCreateSurface");
    requireEGL(eglMakeCurrent(display, surface, surface, context), "eglMakeCurrent");
  }

  void capture(const char *path) {
    std::vector<uint8_t> rgba(size_t(width)*height*4), row(size_t(width)*3);
    glReadPixels(0,0,width,height,GL_RGBA,GL_UNSIGNED_BYTE,rgba.data());
    if (auto err = glGetError()) throw std::runtime_error("glReadPixels/previous GL command error " + std::to_string(err));
    std::ofstream out(path, std::ios::binary);
    out << "P6\n" << width << " " << height << "\n255\n";
    for (int y = height-1; y >= 0; --y) {
      for (int x = 0; x < width; ++x) memcpy(row.data()+x*3, rgba.data()+(size_t(y)*width+x)*4, 3);
      out.write(reinterpret_cast<const char *>(row.data()), row.size());
    }
    if (!out) throw std::runtime_error("Could not write framebuffer");
  }

  ~Surface() {
    if (id) EXGLContextDestroy(id);
    if (display != EGL_NO_DISPLAY) {
      eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
      if (surface != EGL_NO_SURFACE) eglDestroySurface(display,surface);
      if (context != EGL_NO_CONTEXT) eglDestroyContext(display,context);
      eglTerminate(display);
    }
  }
};

static int run(int argc, const char **argv) {
  const char *capture = nullptr;
  int frames = 0;
  double timeMs = -1;
  for (int i=1; i<argc; i++) {
    std::string flag = argv[i];
    if (i+1 >= argc) throw std::runtime_error("Missing value for " + flag);
    if (flag == "--capture") capture = argv[++i];
    else if (flag == "--frames") { frames = std::stoi(argv[++i]); if (frames < 1) throw std::runtime_error("Invalid frame count"); }
    else if (flag == "--time-ms") timeMs = std::stod(argv[++i]);
    else throw std::runtime_error("Unknown option " + flag);
  }
  if (capture && !frames) frames = 1;
  Surface gpu(!frames);
  auto rt = facebook::hermes::makeHermesRuntime(::hermes::vm::RuntimeConfig::Builder().withEnableEval(false).build());
  auto global = rt->global();
  auto bind = [&](const char *name, int arity, jsi::HostFunctionType fn) {
    auto key = jsi::PropNameID::forAscii(*rt,name);
    global.setProperty(*rt, key, jsi::Function::createFromHostFunction(*rt,key,arity,std::move(fn)));
  };
  auto started = Clock::now();
  auto now = [&] { return std::chrono::duration<double,std::milli>(Clock::now()-started).count(); };
  bind("__nativeNow",0,[&](auto &,auto &,auto *,size_t){ return now(); });
  bind("__nativeLog",2,[&](auto &r,auto &,auto a,size_t){
    fprintf(stderr,"%s %s\n",a[0].asString(r).utf8(r).c_str(),a[1].asString(r).utf8(r).c_str()); return jsi::Value::undefined();
  });
  bind("__nativeResize",2,[&](auto &r,auto &,auto a,size_t){
    gpu.resize(a[0].asNumber(),a[1].asNumber());
    return jsi::Array::createWithElements(r, {gpu.width, gpu.height});
  });
  bind("__nativeContext",1,[&](auto &r,auto &,auto a,size_t){
    auto aa = a[0].asObject(r).getProperty(r,"antialias");
    gpu.initialize(r, aa.isBool() && aa.getBool());
    return global.getPropertyAsObject(r,"__EXGLContexts").getProperty(r,std::to_string(gpu.id).c_str());
  });
  rt->evaluateSHUnit(sh_export_app);
  if (gpu.window) {
    [gpu.window center];
    [gpu.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp finishLaunching];
  }
  auto frame = global.getPropertyAsFunction(*rt,"__nativeFrame");
  auto key = global.getPropertyAsFunction(*rt,"__nativeKey");
  const double firstFrame = now();
  for (int i=0; frames ? i<frames : gpu.window.visible; ++i) {
    @autoreleasepool {
      if (gpu.window) {
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantPast] inMode:NSDefaultRunLoopMode dequeue:YES])) {
          if (event.type == NSEventTypeKeyDown || event.type == NSEventTypeKeyUp) {
            const char *chars = (event.characters ?: @"").UTF8String;
            key.call(*rt,event.type == NSEventTypeKeyDown ? "keydown" : "keyup",event.keyCode == 49 ? "Space" : "", chars, (bool)event.isARepeat);
          }
          [NSApp sendEvent:event];
        }
        [NSApp updateWindows];
      }
      bool drew = frame.call(*rt,timeMs >= 0 ? timeMs : frames ? i*(1000.0/60.0) : now()-firstFrame).getBool();
      rt->drainMicrotasks();
      if (gpu.context != EGL_NO_CONTEXT) {
        if (capture && i==frames-1) gpu.capture(capture);
        if (gpu.window && drew) requireEGL(eglSwapBuffers(gpu.display,gpu.surface),"eglSwapBuffers");
      } else if (capture) throw std::runtime_error("Program did not create a WebGL context");
      if (gpu.window) [NSThread sleepForTimeInterval:1.0/120.0];
    }
  }
  return 0;
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    try { return run(argc,argv); }
    catch (const std::exception &e) { fprintf(stderr,"%s\n",e.what()); return 1; }
  }
}
