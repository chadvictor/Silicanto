#pragma once
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <EGL/eglext_angle.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <memory>
#include <unordered_map>

namespace silicanto {
struct Context {
  EGLDisplay display;
  EGLConfig config = nullptr;
  EGLContext context = EGL_NO_CONTEXT;
  EGLSurface surface = EGL_NO_SURFACE;
  int width = 0, height = 0;
  bool alpha = true, depth = true, stencil = false;

  explicit Context(EGLDisplay display) : display(display) {}
  ~Context() {
    if (eglGetCurrentContext() == context)
      eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (surface)
      eglDestroySurface(display, surface);
    if (context)
      eglDestroyContext(display, context);
  }
  bool resize(int w, int h) {
    if (w < 0 || h < 0 || w > 16384 || h > 16384 || 1LL * w * h > 16777216)
      return false;
    const EGLint attr[] = {EGL_WIDTH, std::max(1, w), EGL_HEIGHT,
                           std::max(1, h), EGL_NONE};
    EGLSurface next = eglCreatePbufferSurface(display, config, attr);
    if (!next)
      return false;
    if (!eglMakeCurrent(display, next, next, context)) {
      eglDestroySurface(display, next);
      return false;
    }
    if (surface)
      eglDestroySurface(display, surface);
    surface = next;
    width = w;
    height = h;
    return true;
  }
  bool current() {
    return eglGetCurrentContext() == context ||
           eglMakeCurrent(display, surface, surface, context);
  }
};
inline EGLDisplay metalDisplay() {
  static EGLDisplay display = [] {
    auto get = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress(
        "eglGetPlatformDisplayEXT");
    if (!get)
      return EGL_NO_DISPLAY;
    const EGLint attr[] = {EGL_PLATFORM_ANGLE_TYPE_ANGLE,
                           EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE, EGL_NONE};
    EGLDisplay d = get(EGL_PLATFORM_ANGLE_ANGLE, nullptr, attr);
    if (!d || !eglInitialize(d, nullptr, nullptr))
      return EGL_NO_DISPLAY;
    return d;
  }();
  return display;
}
inline std::unique_ptr<Context> createContext(int w, int h, bool alpha,
                                              bool depth, bool stencil) {
  auto d = metalDisplay();
  if (!d || !eglBindAPI(EGL_OPENGL_ES_API))
    return {};
  auto c = std::make_unique<Context>(d);
  c->alpha = alpha;
  c->depth = depth;
  c->stencil = stencil;
  EGLint n = 0;
  const EGLint config[] = {EGL_SURFACE_TYPE,
                           EGL_PBUFFER_BIT,
                           EGL_RENDERABLE_TYPE,
                           EGL_OPENGL_ES2_BIT,
                           EGL_RED_SIZE,
                           8,
                           EGL_GREEN_SIZE,
                           8,
                           EGL_BLUE_SIZE,
                           8,
                           EGL_ALPHA_SIZE,
                           alpha ? 8 : 0,
                           EGL_DEPTH_SIZE,
                           depth ? 16 : 0,
                           EGL_STENCIL_SIZE,
                           stencil ? 8 : 0,
                           EGL_NONE};
  if (!eglChooseConfig(d, config, &c->config, 1, &n) || !n)
    return {};
  const EGLint attr[] = {EGL_CONTEXT_CLIENT_VERSION,
                         2,
                         EGL_CONTEXT_WEBGL_COMPATIBILITY_ANGLE,
                         EGL_TRUE,
                         EGL_CONTEXT_BIND_GENERATES_RESOURCE_CHROMIUM,
                         EGL_FALSE,
                         EGL_CONTEXT_CLIENT_ARRAYS_ENABLED_ANGLE,
                         EGL_FALSE,
                         EGL_ROBUST_RESOURCE_INITIALIZATION_ANGLE,
                         EGL_TRUE,
                         EGL_NONE};
  c->context = eglCreateContext(d, c->config, EGL_NO_CONTEXT, attr);
  if (!c->context || !c->resize(w, h))
    return {};
  glViewport(0, 0, w, h);
  return c;
}
} // namespace silicanto
