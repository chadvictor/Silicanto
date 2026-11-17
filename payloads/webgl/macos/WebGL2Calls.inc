// GLES 3 commands are reachable only from actual ES 3 contexts.
#define GL_OBJECT(Name, Plural)                                                \
  if (IS(create##Name)) {                                                      \
    GLuint n = 0;                                                              \
    glGen##Plural(1, &n);                                                      \
    return @(n);                                                               \
  }                                                                            \
  if (IS(delete##Name)) {                                                      \
    GLuint n = I(0);                                                           \
    glDelete##Plural(1, &n);                                                   \
    return none();                                                             \
  }                                                                            \
  VALUE_CALL(is##Name, glIs##Name(I(0)) != GL_FALSE)
GL_OBJECT(VertexArray, VertexArrays)
GL_OBJECT(Sampler, Samplers)
GL_OBJECT(TransformFeedback, TransformFeedbacks)
GL_OBJECT(Query, Queries)
#undef GL_OBJECT
VOID_CALL(bindVertexArray, glBindVertexArray(I(0)))
VOID_CALL(bindSampler, glBindSampler(I(0), I(1)))
VOID_CALL(bindTransformFeedback, glBindTransformFeedback(I(0), I(1)))
VOID_CALL(beginTransformFeedback, glBeginTransformFeedback(I(0)))
VOID_CALL(endTransformFeedback, glEndTransformFeedback())
VOID_CALL(pauseTransformFeedback, glPauseTransformFeedback())
VOID_CALL(resumeTransformFeedback, glResumeTransformFeedback())
VOID_CALL(beginQuery, glBeginQuery(I(0), I(1)))
VOID_CALL(endQuery, glEndQuery(I(0)))
VOID_CALL(samplerParameteri, glSamplerParameteri(I(0), I(1), I(2)))
VOID_CALL(samplerParameterf, glSamplerParameterf(I(0), I(1), F(2)))
VOID_CALL(bindBufferBase, glBindBufferBase(I(0), I(1), I(2)))
VOID_CALL(bindBufferRange, glBindBufferRange(I(0), I(1), I(2), I(3), I(4)))
VOID_CALL(copyBufferSubData, glCopyBufferSubData(I(0), I(1), I(2), I(3), I(4)))
VOID_CALL(blitFramebuffer, glBlitFramebuffer(I(0), I(1), I(2), I(3), I(4), I(5),
                                             I(6), I(7), I(8), I(9)))
VOID_CALL(framebufferTextureLayer,
          glFramebufferTextureLayer(I(0), I(1), I(2), I(3), I(4)))
VOID_CALL(readBuffer, glReadBuffer(I(0)))
VOID_CALL(renderbufferStorageMultisample,
          glRenderbufferStorageMultisample(I(0), I(1), I(2), I(3), I(4)))
VOID_CALL(texStorage2D, glTexStorage2D(I(0), I(1), I(2), I(3), I(4)))
VOID_CALL(texStorage3D, glTexStorage3D(I(0), I(1), I(2), I(3), I(4), I(5)))
VOID_CALL(copyTexSubImage3D, glCopyTexSubImage3D(I(0), I(1), I(2), I(3), I(4),
                                                 I(5), I(6), I(7), I(8)))
VALUE_CALL(getFragDataLocation, glGetFragDataLocation(I(0), S(1)))
VALUE_CALL(getUniformBlockIndex, (unsigned)glGetUniformBlockIndex(I(0), S(1)))
VOID_CALL(uniformBlockBinding, glUniformBlockBinding(I(0), I(1), I(2)))
VOID_CALL(vertexAttribDivisor, glVertexAttribDivisor(I(0), I(1)))
VOID_CALL(vertexAttribI4i, glVertexAttribI4i(I(0), I(1), I(2), I(3), I(4)))
VOID_CALL(vertexAttribI4ui, glVertexAttribI4ui(I(0), I(1), I(2), I(3), I(4)))
VOID_CALL(drawArraysInstanced, glDrawArraysInstanced(I(0), I(1), I(2), I(3)))
VOID_CALL(clearBufferfi, glClearBufferfi(I(0), I(1), F(2), I(3)))
VOID_CALL(uniform1ui, glUniform1ui(I(0), I(1)))
VOID_CALL(uniform2ui, glUniform2ui(I(0), I(1), I(2)))
VOID_CALL(uniform3ui, glUniform3ui(I(0), I(1), I(2), I(3)))
VOID_CALL(uniform4ui, glUniform4ui(I(0), I(1), I(2), I(3), I(4)))
if (IS(drawElementsInstanced) || IS(drawRangeElements) ||
    IS(vertexAttribIPointer)) {
  const bool vertex = IS(vertexAttribIPointer);
  GLint bound = 0;
  glGetIntegerv(vertex ? GL_ARRAY_BUFFER_BINDING
                       : GL_ELEMENT_ARRAY_BUFFER_BINDING,
                &bound);
  const int offset = I(vertex ? 4 : IS(drawRangeElements) ? 5 : 3);
  if (!bound || offset < 0)
    return @"INVALID_OPERATION";
  auto p = reinterpret_cast<const void *>(static_cast<uintptr_t>(offset));
  if (vertex)
    glVertexAttribIPointer(I(0), I(1), I(2), I(3), p);
  else if (IS(drawRangeElements))
    glDrawRangeElements(I(0), I(1), I(2), I(3), I(4), p);
  else
    glDrawElementsInstanced(I(0), I(1), I(2), p, I(4));
  return none();
}
if (IS(drawBuffers) || IS(invalidateFramebuffer) ||
    IS(invalidateSubFramebuffer)) {
  NSArray *arr = arg(IS(drawBuffers) ? 0 : 1);
  std::vector<GLenum> values;
  for (NSNumber *n in arr)
    values.push_back(n.unsignedIntValue);
  if (IS(drawBuffers))
    glDrawBuffers(values.size(), values.data());
  else if (IS(invalidateFramebuffer))
    glInvalidateFramebuffer(I(0), values.size(), values.data());
  else
    glInvalidateSubFramebuffer(I(0), values.size(), values.data(), I(2), I(3),
                               I(4), I(5));
  return none();
}
if (IS(getBufferSubData)) {
  const GLint off = I(1), bytes = I(2);
  GLint64 size = 0;
  glGetBufferParameteri64v(I(0), GL_BUFFER_SIZE, &size);
  if (off < 0 || bytes < 0 || bytes > 268435456 || int64_t(off) + bytes > size)
    return @"INVALID_VALUE";
  if (!bytes)
    return @"";
  const void *p = glMapBufferRange(I(0), off, bytes, GL_MAP_READ_BIT);
  if (!p)
    return @"INVALID_OPERATION";
  NSData *data = [NSData dataWithBytes:p length:bytes];
  glUnmapBuffer(I(0));
  return [data base64EncodedStringWithOptions:0];
}
if (IS(getInternalformatParameter)) {
  GLint count = 0;
  glGetInternalformativ(I(0), I(1), GL_NUM_SAMPLE_COUNTS, 1, &count);
  std::vector<GLint> values(std::clamp(count, 0, 256));
  glGetInternalformativ(I(0), I(1), I(2), values.size(), values.data());
  NSMutableArray *out = [NSMutableArray new];
  for (auto v : values)
    [out addObject:@(v)];
  return out;
}
if (IS(getQuery)) {
  GLint value = 0;
  glGetQueryiv(I(0), I(1), &value);
  return @(value);
}
if (IS(getQueryParameter)) {
  GLuint v = 0;
  glGetQueryObjectuiv(I(0), I(1), &v);
  return I(1) == GL_QUERY_RESULT_AVAILABLE ? @(v != 0) : @(v);
}
if (IS(getSamplerParameter)) {
  GLfloat v = 0;
  entry<PFNGLGETSAMPLERPARAMETERFVROBUSTANGLEPROC>(
      "glGetSamplerParameterfvRobustANGLE")(I(0), I(1), 1, nullptr, &v);
  return @(v);
}
if (IS(fenceSync)) {
  auto sync = glFenceSync(I(0), I(1));
  if (!sync)
    return @(0);
  GLuint id = ctx.nextSync++;
  ctx.syncs[id] = sync;
  return @(id);
}
if (IS(isSync) || IS(deleteSync) || IS(waitSync) || IS(clientWaitSync) ||
    IS(getSyncParameter)) {
  auto it = ctx.syncs.find(I(0));
  if (IS(isSync))
    return @(it != ctx.syncs.end() && glIsSync(it->second));
  if (it == ctx.syncs.end())
    return IS(deleteSync) ? none() : @"INVALID_VALUE";
  auto sync = it->second;
  if (IS(deleteSync)) {
    glDeleteSync(sync);
    ctx.syncs.erase(it);
    return none();
  }
  if (IS(getSyncParameter)) {
    GLint v = 0;
    glGetSynciv(sync, I(1), 1, nullptr, &v);
    return @(v);
  }
  if (IS(waitSync)) {
    if ([arg(2) doubleValue] != -1)
      return @"INVALID_VALUE";
    glWaitSync(sync, I(1), GL_TIMEOUT_IGNORED);
    return none();
  }
  if ([arg(2) doubleValue] != 0)
    return @"INVALID_OPERATION";
  return @(glClientWaitSync(sync, I(1), 0));
}
if (IS(getIndexedParameter)) {
  GLint64 v = 0;
  entry<PFNGLGETINTEGER64I_VROBUSTANGLEPROC>("glGetInteger64i_vRobustANGLE")(
      I(0), I(1), 1, nullptr, &v);
  return @(v);
}
if (IS(transformFeedbackVaryings) || IS(getUniformIndices)) {
  std::vector<const GLchar *> names;
  for (NSString *v in arg(1))
    names.push_back(v.UTF8String);
  if (IS(transformFeedbackVaryings)) {
    glTransformFeedbackVaryings(I(0), names.size(), names.data(), I(2));
    return none();
  }
  std::vector<GLuint> ids(names.size());
  glGetUniformIndices(I(0), names.size(), names.data(), ids.data());
  NSMutableArray *out = [NSMutableArray new];
  for (auto id : ids)
    [out addObject:@(id)];
  return out;
}
if (IS(getActiveUniforms)) {
  std::vector<GLuint> indices;
  for (NSNumber *v in arg(1))
    indices.push_back(v.unsignedIntValue);
  std::vector<GLint> values(indices.size());
  glGetActiveUniformsiv(I(0), indices.size(), indices.data(), I(2),
                        values.data());
  NSMutableArray *out = [NSMutableArray new];
  for (auto v : values)
    [out addObject:I(2) == GL_UNIFORM_IS_ROW_MAJOR ? @(v != 0) : @(v)];
  return out;
}
if (IS(getTransformFeedbackVarying) || IS(getActiveUniformBlockName)) {
  bool block = IS(getActiveUniformBlockName);
  GLint n = 0, size = 0;
  GLenum type = 0;
  GLsizei written = 0;
  glGetProgramiv(I(0),
                 block ? GL_ACTIVE_UNIFORM_BLOCK_MAX_NAME_LENGTH
                       : GL_TRANSFORM_FEEDBACK_VARYING_MAX_LENGTH,
                 &n);
  if (n <= 0)
    return none();
  std::vector<char> buf(n);
  if (block)
    glGetActiveUniformBlockName(I(0), I(1), n, &written, buf.data());
  else
    glGetTransformFeedbackVarying(I(0), I(1), n, &written, &size, &type,
                                  buf.data());
  if (!written)
    return none();
  NSString *name = stringValue(buf.data());
  return block ? name : @{@"name" : name, @"size" : @(size), @"type" : @(type)};
}
if (IS(getActiveUniformBlockParameter)) {
  const GLenum key = I(2);
  GLint count = 1;
  if (key == GL_UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES)
    glGetActiveUniformBlockiv(I(0), I(1), GL_UNIFORM_BLOCK_ACTIVE_UNIFORMS,
                              &count);
  std::vector<GLint> values(std::max(1, count));
  glGetActiveUniformBlockiv(I(0), I(1), key, values.data());
  if (key == GL_UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES) {
    NSMutableArray *out = [NSMutableArray new];
    for (int i = 0; i < count; i++)
      [out addObject:@(values[i])];
    return out;
  }
  if (key == GL_UNIFORM_BLOCK_REFERENCED_BY_VERTEX_SHADER ||
      key == GL_UNIFORM_BLOCK_REFERENCED_BY_FRAGMENT_SHADER)
    return @(values[0] != 0);
  return @(values[0]);
}
if (IS(clearBufferfv) || IS(clearBufferiv) || IS(clearBufferuiv) ||
    IS(vertexAttribI4iv) || IS(vertexAttribI4uiv) ||
    [op hasPrefix:@"uniformMatrix"] || [op hasSuffix:@"uiv"]) {
  const bool clear = [op hasPrefix:@"clear"],
             matrix = [op hasPrefix:@"uniformMatrix"],
             vertex = [op hasPrefix:@"vertex"];
  NSArray *values = arg(clear || matrix ? 2 : 1);
  if (![values isKindOfClass:NSArray.class])
    return @"INVALID_VALUE";
  std::vector<GLint> iv;
  std::vector<GLuint> uv;
  std::vector<GLfloat> fv;
  for (NSNumber *n in values) {
    iv.push_back(n.intValue);
    uv.push_back(n.unsignedIntValue);
    fv.push_back(n.floatValue);
  }
  if (clear) {
    if (values.count < (I(0) == GL_COLOR ? 4 : 1))
      return @"INVALID_VALUE";
    if (IS(clearBufferfv))
      glClearBufferfv(I(0), I(1), fv.data());
    else if (IS(clearBufferiv))
      glClearBufferiv(I(0), I(1), iv.data());
    else
      glClearBufferuiv(I(0), I(1), uv.data());
    return none();
  }
  if (vertex) {
    if (values.count < 4)
      return @"INVALID_VALUE";
    if (IS(vertexAttribI4iv))
      glVertexAttribI4iv(I(0), iv.data());
    else
      glVertexAttribI4uiv(I(0), uv.data());
    return none();
  }
#define UV(N)                                                                  \
  if (IS(uniform##N##uiv)) {                                                   \
    if (uv.size() % N)                                                         \
      return @"INVALID_VALUE";                                                 \
    glUniform##N##uiv(I(0), uv.size() / N, uv.data());                         \
    return none();                                                             \
  }
  UV(1)
  UV(2) UV(3) UV(4)
#undef UV
#define MAT(NAME, CELLS)                                                       \
  if (IS(uniformMatrix##NAME##fv)) {                                           \
    if (fv.size() % CELLS)                                                     \
      return @"INVALID_VALUE";                                                 \
    glUniformMatrix##NAME##fv(I(0), fv.size() / CELLS, B(1), fv.data());       \
    return none();                                                             \
  }
      MAT(2x3, 6) MAT(2x4, 8) MAT(3x2, 6) MAT(3x4, 12) MAT(4x2, 8) MAT(4x3, 12)
          MAT(2, 4) MAT(3, 9) MAT(4, 16)
#undef MAT
}
if (IS(texImage3D) || IS(texSubImage3D) || IS(compressedTexImage3D) ||
    IS(compressedTexSubImage3D)) {
  const bool sub = [op containsString:@"Sub"],
             compressed = [op hasPrefix:@"compressed"];
  const int index = compressed ? (sub ? 9 : 7) : (sub ? 10 : 9);
  const bool offset = [arg(index) isKindOfClass:NSNumber.class];
  GLint bound = 0;
  glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &bound);
  if ((bound != 0) != offset)
    return @"INVALID_OPERATION";
  NSData *bytes = offset ? nil : decode(arg(index));
  if (offset && I(index) < 0)
    return @"INVALID_VALUE";
  const void *ptr =
      offset ? reinterpret_cast<const void *>(static_cast<uintptr_t>(I(index)))
             : bytes.bytes;
  if (compressed) {
    if (offset)
      return @"INVALID_OPERATION";
    if (sub)
      glCompressedTexSubImage3D(I(0), I(1), I(2), I(3), I(4), I(5), I(6), I(7),
                                I(8), bytes.length, ptr);
    else
      glCompressedTexImage3D(I(0), I(1), I(2), I(3), I(4), I(5), I(6),
                             bytes.length, ptr);
  } else if (sub)
    entry<PFNGLTEXSUBIMAGE3DROBUSTANGLEPROC>("glTexSubImage3DRobustANGLE")(
        I(0), I(1), I(2), I(3), I(4), I(5), I(6), I(7), I(8), I(9),
        bytes.length, ptr);
  else
    entry<PFNGLTEXIMAGE3DROBUSTANGLEPROC>("glTexImage3DRobustANGLE")(
        I(0), I(1), I(2), I(3), I(4), I(5), I(6), I(7), I(8), bytes.length,
        ptr);
  return none();
}
