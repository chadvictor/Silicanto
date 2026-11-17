#include "Context.hpp"
#import <Foundation/Foundation.h>
#include <GLES2/gl2ext_angle.h>
#include <string>
#include <vector>

using namespace silicanto;
static thread_local std::unordered_map<int, std::unique_ptr<Context>> contexts;
static thread_local int nextContext = 1;
static id none() { return NSNull.null; }
static NSString *stringValue(const char *s) {
  return s ? [NSString stringWithUTF8String:s] : @"";
}
static NSData *decode(id arg) {
  if (arg == none())
    return nil;
  NSData *d = [[NSData alloc] initWithBase64EncodedString:arg options:0];
  if (!d)
    @throw [NSException exceptionWithName:@"WebGL"
                                   reason:@"Invalid binary transfer"
                                 userInfo:nil];
  return d;
}
template <class T> static T entry(const char *s) {
  T p = reinterpret_cast<T>(eglGetProcAddress(s));
  if (!p)
    @throw [NSException exceptionWithName:@"WebGL"
                                   reason:stringValue(s)
                                 userInfo:nil];
  return p;
}
static id state(GLenum key) {
  switch (key) {
  case GL_VERSION:
    return @"WebGL 1.0 (OpenGL ES 2.0)";
  case GL_SHADING_LANGUAGE_VERSION:
    return @"WebGL GLSL ES 1.0";
  case GL_VENDOR:
  case GL_RENDERER:
    return stringValue((const char *)glGetString(key));
  }
  // Robust variants bound writes even for unknown enum values.
  GLint count = 0;
  if (key == GL_COMPRESSED_TEXTURE_FORMATS)
    glGetIntegerv(GL_NUM_COMPRESSED_TEXTURE_FORMATS, &count);
  std::vector<GLint> v(std::max(16, std::min(count, 4096)));
  auto query =
      entry<PFNGLGETINTEGERVROBUSTANGLEPROC>("glGetIntegervRobustANGLE");
  if (key == GL_COLOR_CLEAR_VALUE || key == GL_BLEND_COLOR ||
      key == GL_DEPTH_RANGE || key == GL_DEPTH_CLEAR_VALUE ||
      key == GL_LINE_WIDTH || key == GL_ALIASED_LINE_WIDTH_RANGE ||
      key == GL_ALIASED_POINT_SIZE_RANGE || key == GL_POLYGON_OFFSET_FACTOR ||
      key == GL_POLYGON_OFFSET_UNITS || key == GL_SAMPLE_COVERAGE_VALUE) {
    GLfloat f[4] = {};
    entry<PFNGLGETFLOATVROBUSTANGLEPROC>("glGetFloatvRobustANGLE")(key, 4,
                                                                   &count, f);
    if (count == 1)
      return @(f[0]);
    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < count && i < 4; ++i)
      [out addObject:@(f[i])];
    return out;
  }
  query(key, (GLsizei)v.size(), &count, v.data());
  if (key == GL_BLEND || key == GL_CULL_FACE || key == GL_DEPTH_TEST ||
      key == GL_DEPTH_WRITEMASK || key == GL_DITHER ||
      key == GL_POLYGON_OFFSET_FILL || key == GL_SAMPLE_COVERAGE ||
      key == GL_SCISSOR_TEST || key == GL_STENCIL_TEST)
    return @(v[0] != 0);
  if (count == 1 && key != GL_COMPRESSED_TEXTURE_FORMATS)
    return @(v[0]);
  NSMutableArray *out = [NSMutableArray array];
  for (int i = 0; i < count && i < (int)v.size(); ++i)
    [out addObject:@(v[i])];
  return out;
}
static id dispatch(int handle, NSString *op, NSArray *a) {
  auto arg = [&](NSUInteger i) -> id {
    return i < a.count && a[i] != none() ? a[i] : nil;
  };
  auto I = [&](NSUInteger i) { return [arg(i) intValue]; };
  auto F = [&](NSUInteger i) { return [arg(i) floatValue]; };
  auto B = [&](NSUInteger i) { return (GLboolean)[arg(i) boolValue]; };
  auto S = [&](NSUInteger i) { return [arg(i) UTF8String] ?: ""; };
#define IS(name) [op isEqualToString:@ #name]
  if (IS(createContext)) {
    auto ctx = createContext(I(0), I(1), B(2), B(3), B(4));
    if (!ctx)
      return @(0);
    const int n = nextContext++;
    contexts.emplace(n, std::move(ctx));
    return @(n);
  }
  auto it = contexts.find(handle);
  if (it == contexts.end() || !it->second->current())
    @throw [NSException exceptionWithName:@"WebGL"
                                   reason:@"Context is unavailable"
                                 userInfo:nil];
  auto &ctx = *it->second;
  if (IS(destroyContext)) {
    contexts.erase(it);
    return none();
  }
  if (IS(resize))
    return @(ctx.resize(I(0), I(1)));
#define VOID_CALL(name, expr)                                                  \
  if (IS(name)) {                                                              \
    expr;                                                                      \
    return none();                                                             \
  }
#define VALUE_CALL(name, expr)                                                 \
  if (IS(name))                                                                \
    return @(expr);
#include "ScalarCalls.inc"
#define RESOURCE(name)                                                         \
  if (IS(create##name)) {                                                      \
    GLuint n = 0;                                                              \
    glGen##name##s(1, &n);                                                     \
    return @(n);                                                               \
  }                                                                            \
  if (IS(delete##name)) {                                                      \
    GLuint n = I(0);                                                           \
    glDelete##name##s(1, &n);                                                  \
    return none();                                                             \
  }
  RESOURCE(Buffer)
  RESOURCE(Texture) RESOURCE(Framebuffer)
      RESOURCE(Renderbuffer) if (IS(extensions)) {
    NSString *enabled = stringValue((const char *)glGetString(GL_EXTENSIONS));
    NSString *available =
        stringValue((const char *)glGetString(GL_REQUESTABLE_EXTENSIONS_ANGLE));
    return [[enabled stringByAppendingFormat:@" %@", available]
        componentsSeparatedByString:@" "];
  }
  if (IS(enableExtension)) {
    NSString *ext = arg(0);
    if (![ext hasPrefix:@"GL_"])
      return @NO;
    auto enabled = [stringValue((const char *)glGetString(GL_EXTENSIONS))
        componentsSeparatedByString:@" "];
    if (![enabled containsObject:ext])
      entry<PFNGLREQUESTEXTENSIONANGLEPROC>("glRequestExtensionANGLE")(S(0));
    return @([[stringValue((const char *)glGetString(GL_EXTENSIONS))
        componentsSeparatedByString:@" "] containsObject:ext]);
  }
  if (IS(createVertexArrayOES)) {
    GLuint n = 0;
    entry<PFNGLGENVERTEXARRAYSOESPROC>("glGenVertexArraysOES")(1, &n);
    return @(n);
  }
  if (IS(deleteVertexArrayOES)) {
    GLuint n = I(0);
    entry<PFNGLDELETEVERTEXARRAYSOESPROC>("glDeleteVertexArraysOES")(1, &n);
    return none();
  }
  VOID_CALL(bindVertexArrayOES,
            entry<PFNGLBINDVERTEXARRAYOESPROC>("glBindVertexArrayOES")(I(0)))
  VALUE_CALL(isVertexArrayOES, entry<PFNGLISVERTEXARRAYOESPROC>(
                                   "glIsVertexArrayOES")(I(0)) != GL_FALSE)
  VOID_CALL(vertexAttribDivisorANGLE,
            entry<PFNGLVERTEXATTRIBDIVISORANGLEPROC>(
                "glVertexAttribDivisorANGLE")(I(0), I(1)))
  VOID_CALL(drawArraysInstancedANGLE,
            entry<PFNGLDRAWARRAYSINSTANCEDANGLEPROC>(
                "glDrawArraysInstancedANGLE")(I(0), I(1), I(2), I(3)))
  if (IS(drawElements) || IS(drawElementsInstancedANGLE) ||
      IS(vertexAttribPointer)) {
    const bool vertex = IS(vertexAttribPointer);
    GLint bound = 0;
    glGetIntegerv(vertex ? GL_ARRAY_BUFFER_BINDING
                         : GL_ELEMENT_ARRAY_BUFFER_BINDING,
                  &bound);
    const GLint off = I(vertex ? 5 : 3);
    if (!bound || off < 0)
      return @"INVALID_OPERATION";
    const void *p = reinterpret_cast<const void *>(static_cast<uintptr_t>(off));
    if (vertex)
      glVertexAttribPointer(I(0), I(1), I(2), B(3), I(4), p);
    else if (IS(drawElements))
      glDrawElements(I(0), I(1), I(2), p);
    else
      entry<PFNGLDRAWELEMENTSINSTANCEDANGLEPROC>(
          "glDrawElementsInstancedANGLE")(I(0), I(1), I(2), p, I(4));
    return none();
  }
  if (IS(getParameter))
    return state(I(0));
  if (IS(shaderSource)) {
    const char *s = S(1);
    glShaderSource(I(0), 1, &s, nullptr);
    return none();
  }
  if (IS(getShaderParameter) || IS(getProgramParameter)) {
    GLint n = 0;
    if (IS(getShaderParameter))
      glGetShaderiv(I(0), I(1), &n);
    else
      glGetProgramiv(I(0), I(1), &n);
    switch (I(1)) {
    case GL_COMPILE_STATUS:
    case GL_LINK_STATUS:
    case GL_DELETE_STATUS:
    case GL_VALIDATE_STATUS:
      return @(n != 0);
    default:
      return @(n);
    }
  }
  if (IS(getShaderInfoLog) || IS(getProgramInfoLog) || IS(getShaderSource)) {
    GLint n = 0;
    if (IS(getProgramInfoLog))
      glGetProgramiv(I(0), GL_INFO_LOG_LENGTH, &n);
    else
      glGetShaderiv(I(0),
                    IS(getShaderSource) ? GL_SHADER_SOURCE_LENGTH
                                        : GL_INFO_LOG_LENGTH,
                    &n);
    if (n <= 0)
      return @"";
    std::vector<char> s(n);
    if (IS(getShaderInfoLog))
      glGetShaderInfoLog(I(0), n, nullptr, s.data());
    else if (IS(getShaderSource))
      glGetShaderSource(I(0), n, nullptr, s.data());
    else
      glGetProgramInfoLog(I(0), n, nullptr, s.data());
    return stringValue(s.data());
  }
  if (IS(getActiveAttrib) || IS(getActiveUniform)) {
    const bool attr = IS(getActiveAttrib);
    GLint n = 0;
    glGetProgramiv(I(0),
                   attr ? GL_ACTIVE_ATTRIBUTE_MAX_LENGTH
                        : GL_ACTIVE_UNIFORM_MAX_LENGTH,
                   &n);
    if (n < 1)
      return none();
    std::vector<char> s(n);
    GLint size = 0;
    GLenum type = 0;
    GLsizei written = 0;
    if (attr)
      glGetActiveAttrib(I(0), I(1), n, &written, &size, &type, s.data());
    else
      glGetActiveUniform(I(0), I(1), n, &written, &size, &type, s.data());
    return written ? @{
      @"name" : stringValue(s.data()),
      @"size" : @(size),
      @"type" : @(type)
    }
                   : none();
  }
  if (IS(getShaderPrecisionFormat)) {
    GLint range[2] = {}, p = 0;
    glGetShaderPrecisionFormat(I(0), I(1), range, &p);
    return @{
      @"rangeMin" : @(range[0]),
      @"rangeMax" : @(range[1]),
      @"precision" : @(p)
    };
  }
  if (IS(bufferData) || IS(bufferSubData)) {
    const bool sub = IS(bufferSubData);
    id data = arg(sub ? 2 : 1);
    if (!sub && [data isKindOfClass:NSNumber.class])
      glBufferData(I(0), I(1), nullptr, I(2));
    else {
      NSData *bytes = decode(data);
      if (sub)
        glBufferSubData(I(0), I(1), bytes.length, bytes.bytes);
      else
        glBufferData(I(0), bytes.length, bytes.bytes, I(2));
    }
    return none();
  }
  if (IS(texImage2D) || IS(texSubImage2D)) {
    NSData *data = arg(8) ? decode(arg(8)) : nil;
    if (IS(texImage2D))
      entry<PFNGLTEXIMAGE2DROBUSTANGLEPROC>("glTexImage2DRobustANGLE")(
          I(0), I(1), I(2), I(3), I(4), I(5), I(6), I(7), (GLsizei)data.length,
          data.bytes);
    else
      entry<PFNGLTEXSUBIMAGE2DROBUSTANGLEPROC>("glTexSubImage2DRobustANGLE")(
          I(0), I(1), I(2), I(3), I(4), I(5), I(6), I(7), (GLsizei)data.length,
          data.bytes);
    return none();
  }
  if (IS(readPixels) || IS(snapshot)) {
    const bool snap = IS(snapshot);
    int w = snap ? ctx.width : I(2), h = snap ? ctx.height : I(3);
    if (w < 0 || h < 0 || 1LL * w * h > 16777216)
      return @"INVALID_VALUE";
    const int size = snap ? w * h * 4 : I(6);
    if (size < 0 || size > 268435456)
      return @"INVALID_VALUE";
    NSMutableData *data = [NSMutableData dataWithLength:size];
    GLint fb = 0, align = 4;
    if (snap) {
      glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fb);
      glBindFramebuffer(GL_FRAMEBUFFER, 0);
      glGetIntegerv(GL_PACK_ALIGNMENT, &align);
      glPixelStorei(GL_PACK_ALIGNMENT, 1);
    }
    entry<PFNGLREADPIXELSROBUSTANGLEPROC>("glReadPixelsRobustANGLE")(
        snap ? 0 : I(0), snap ? 0 : I(1), w, h, snap ? GL_RGBA : I(4),
        snap ? GL_UNSIGNED_BYTE : I(5), size, nullptr, nullptr, nullptr,
        data.mutableBytes);
    if (snap) {
      glBindFramebuffer(GL_FRAMEBUFFER, fb);
      glPixelStorei(GL_PACK_ALIGNMENT, align);
    }
    return [data base64EncodedStringWithOptions:0];
  }
  if ([op hasPrefix:@"uniform"] || [op hasPrefix:@"vertexAttrib"]) {
    const bool mat = [op hasPrefix:@"uniformMatrix"];
    NSArray *values = arg(mat ? 2 : 1);
    if (![values isKindOfClass:NSArray.class])
      return @"INVALID_VALUE";
    std::vector<GLint> ints;
    std::vector<GLfloat> floats;
    for (NSNumber *v in values) {
      ints.push_back(v.intValue);
      floats.push_back(v.floatValue);
    }
#define VECTOR(N)                                                              \
  if (IS(uniform##N##iv)) {                                                    \
    if (ints.size() % N)                                                       \
      return @"INVALID_VALUE";                                                 \
    glUniform##N##iv(I(0), (GLsizei)ints.size() / N, ints.data());             \
    return none();                                                             \
  }                                                                            \
  if (IS(uniform##N##fv)) {                                                    \
    if (floats.size() % N)                                                     \
      return @"INVALID_VALUE";                                                 \
    glUniform##N##fv(I(0), (GLsizei)floats.size() / N, floats.data());         \
    return none();                                                             \
  }                                                                            \
  if (IS(vertexAttrib##N##fv)) {                                               \
    if (floats.size() < N)                                                     \
      return @"INVALID_VALUE";                                                 \
    glVertexAttrib##N##fv(I(0), floats.data());                                \
    return none();                                                             \
  }
    VECTOR(1)
    VECTOR(2) VECTOR(3) VECTOR(4)
#define MATRIX(N)                                                              \
  if (IS(uniformMatrix##N##fv)) {                                              \
    if (floats.size() % (N * N))                                               \
      return @"INVALID_VALUE";                                                 \
    glUniformMatrix##N##fv(I(0), (GLsizei)floats.size() / (N * N), B(1),       \
                           floats.data());                                     \
    return none();                                                             \
  }
        MATRIX(2) MATRIX(3) MATRIX(4)
  }
  if (IS(compressedTexImage2D) || IS(compressedTexSubImage2D)) {
    const bool sub = IS(compressedTexSubImage2D);
    NSData *b = decode(arg(sub ? 7 : 6));
    if (sub)
      entry<PFNGLCOMPRESSEDTEXSUBIMAGE2DROBUSTANGLEPROC>(
          "glCompressedTexSubImage2DRobustANGLE")(I(0), I(1), I(2), I(3), I(4),
                                                  I(5), I(6), (GLsizei)b.length,
                                                  (GLsizei)b.length, b.bytes);
    else
      entry<PFNGLCOMPRESSEDTEXIMAGE2DROBUSTANGLEPROC>(
          "glCompressedTexImage2DRobustANGLE")(I(0), I(1), I(2), I(3), I(4),
                                               I(5), (GLsizei)b.length,
                                               (GLsizei)b.length, b.bytes);
    return none();
  }
  if (IS(getAttachedShaders)) {
    GLuint shaders[2] = {};
    GLsizei count = 0;
    glGetAttachedShaders(I(0), 2, &count, shaders);
    NSMutableArray *ids = [NSMutableArray array];
    for (int i = 0; i < count; i++)
      [ids addObject:@(shaders[i])];
    return ids;
  }
  if (IS(getFramebufferAttachmentParameter)) {
    GLint value = 0;
    glGetFramebufferAttachmentParameteriv(I(0), I(1), I(2), &value);
    if (I(2) != GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME)
      return @(value);
    GLint type = 0;
    glGetFramebufferAttachmentParameteriv(
        I(0), I(1), GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &type);
    return @[ @(type), @(value) ];
  }
  if (IS(getVertexAttribOffset)) {
    void *offset = nullptr;
    glGetVertexAttribPointerv(I(0), I(1), &offset);
    return @(reinterpret_cast<uintptr_t>(offset));
  }
  if (IS(getVertexAttrib)) {
    if (I(1) == GL_CURRENT_VERTEX_ATTRIB) {
      GLfloat v[4] = {};
      glGetVertexAttribfv(I(0), I(1), v);
      return @[ @(v[0]), @(v[1]), @(v[2]), @(v[3]) ];
    }
    GLint v[4] = {};
    glGetVertexAttribiv(I(0), I(1), v);
    return I(1) == GL_VERTEX_ATTRIB_ARRAY_ENABLED ||
                   I(1) == GL_VERTEX_ATTRIB_ARRAY_NORMALIZED
               ? @(v[0] != 0)
               : @(v[0]);
  }
  if (IS(getUniform)) {
    GLuint program = I(0);
    GLint location = I(1), maxLength = 0, total = 0;
    GLenum kind = 0;
    glGetProgramiv(program, GL_ACTIVE_UNIFORM_MAX_LENGTH, &maxLength);
    glGetProgramiv(program, GL_ACTIVE_UNIFORMS, &total);
    std::vector<char> name(std::max(1, maxLength));
    for (int index = 0; index < total && !kind; index++) {
      GLsizei written = 0;
      GLint n = 0;
      GLenum type = 0;
      glGetActiveUniform(program, index, maxLength, &written, &n, &type,
                         name.data());
      std::string base(name.data(), written);
      if (glGetUniformLocation(program, base.c_str()) == location) {
        kind = type;
        break;
      }
      auto pos = base.find("[0]");
      if (pos != std::string::npos)
        for (int j = 1; j < n; j++) {
          std::string item = base;
          item.replace(pos, 3, "[" + std::to_string(j) + "]");
          if (glGetUniformLocation(program, item.c_str()) == location) {
            kind = type;
            break;
          }
        }
    }
    if (!kind)
      return none();
    bool numeric = kind == GL_FLOAT || kind == GL_FLOAT_VEC2 ||
                   kind == GL_FLOAT_VEC3 || kind == GL_FLOAT_VEC4 ||
                   kind == GL_FLOAT_MAT2 || kind == GL_FLOAT_MAT3 ||
                   kind == GL_FLOAT_MAT4;
    bool boolean = kind == GL_BOOL || kind == GL_BOOL_VEC2 ||
                   kind == GL_BOOL_VEC3 || kind == GL_BOOL_VEC4;
    GLint count = 0;
    GLfloat fs[16] = {};
    GLint is[16] = {};
    if (numeric)
      entry<PFNGLGETUNIFORMFVROBUSTANGLEPROC>("glGetUniformfvRobustANGLE")(
          program, location, 16, &count, fs);
    else
      entry<PFNGLGETUNIFORMIVROBUSTANGLEPROC>("glGetUniformivRobustANGLE")(
          program, location, 16, &count, is);
    NSMutableArray *values = [NSMutableArray array];
    for (int i = 0; i < count && i < 16; i++)
      [values addObject:numeric   ? @(fs[i])
                        : boolean ? @(is[i] != 0)
                                  : @(is[i])];
    return @[
      numeric   ? @"Float32Array"
      : boolean ? @"Array"
                : @"Int32Array",
      values
    ];
  }
  if (IS(getBufferParameter)) {
    GLint v = 0;
    glGetBufferParameteriv(I(0), I(1), &v);
    return @(v);
  }
  if (IS(getRenderbufferParameter)) {
    GLint v = 0;
    glGetRenderbufferParameteriv(I(0), I(1), &v);
    return @(v);
  }
  if (IS(getTexParameter)) {
    GLfloat v = 0;
    glGetTexParameterfv(I(0), I(1), &v);
    return @(v);
  }
  @throw [NSException
      exceptionWithName:@"WebGL"
                 reason:[@"Unsupported operation: " stringByAppendingString:op]
               userInfo:nil];
}
extern "C" const char *sil_webgl(const char *input) {
  static thread_local std::string result;
  @autoreleasepool {
    NSArray *reply;
    @try {
      NSData *data = [NSData dataWithBytes:input length:strlen(input)];
      NSArray *request = [NSJSONSerialization JSONObjectWithData:data
                                                         options:0
                                                           error:nil];
      if (request.count != 3)
        @throw [NSException exceptionWithName:@"WebGL"
                                       reason:@"Invalid request"
                                     userInfo:nil];
      id value = dispatch([request[0] intValue], request[1], request[2]);
      reply = @[ @YES, value ?: none() ];
    } @catch (NSException *e) {
      reply = @[ @NO, e.reason ?: @"WebGL error" ];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:reply
                                                   options:0
                                                     error:nil];
    result.assign((const char *)data.bytes, data.length);
  }
  return result.c_str();
}
