/** WebGL 2.0 constants and operations from the Khronos WebIDL. */
class WebGL2Bindings {
	public static final methods = [
		"copyBufferSubData",
		"getBufferSubData",
		"blitFramebuffer",
		"framebufferTextureLayer",
		"invalidateFramebuffer",
		"invalidateSubFramebuffer",
		"readBuffer",
		"getInternalformatParameter",
		"renderbufferStorageMultisample",
		"texStorage2D",
		"texStorage3D",
		"texImage3D",
		"texSubImage3D",
		"copyTexSubImage3D",
		"compressedTexImage3D",
		"compressedTexSubImage3D",
		"getFragDataLocation",
		"uniform1ui",
		"uniform2ui",
		"uniform3ui",
		"uniform4ui",
		"uniform1uiv",
		"uniform2uiv",
		"uniform3uiv",
		"uniform4uiv",
		"uniformMatrix3x2fv",
		"uniformMatrix4x2fv",
		"uniformMatrix2x3fv",
		"uniformMatrix4x3fv",
		"uniformMatrix2x4fv",
		"uniformMatrix3x4fv",
		"vertexAttribI4i",
		"vertexAttribI4iv",
		"vertexAttribI4ui",
		"vertexAttribI4uiv",
		"vertexAttribIPointer",
		"vertexAttribDivisor",
		"drawArraysInstanced",
		"drawElementsInstanced",
		"drawRangeElements",
		"drawBuffers",
		"clearBufferfv",
		"clearBufferiv",
		"clearBufferuiv",
		"clearBufferfi",
		"createQuery",
		"deleteQuery",
		"isQuery",
		"beginQuery",
		"endQuery",
		"getQuery",
		"getQueryParameter",
		"createSampler",
		"deleteSampler",
		"isSampler",
		"bindSampler",
		"samplerParameteri",
		"samplerParameterf",
		"getSamplerParameter",
		"fenceSync",
		"isSync",
		"deleteSync",
		"clientWaitSync",
		"waitSync",
		"getSyncParameter",
		"createTransformFeedback",
		"deleteTransformFeedback",
		"isTransformFeedback",
		"bindTransformFeedback",
		"beginTransformFeedback",
		"endTransformFeedback",
		"transformFeedbackVaryings",
		"getTransformFeedbackVarying",
		"pauseTransformFeedback",
		"resumeTransformFeedback",
		"bindBufferBase",
		"bindBufferRange",
		"getIndexedParameter",
		"getUniformIndices",
		"getActiveUniforms",
		"getUniformBlockIndex",
		"getActiveUniformBlockParameter",
		"getActiveUniformBlockName",
		"uniformBlockBinding",
		"createVertexArray",
		"deleteVertexArray",
		"isVertexArray",
		"bindVertexArray",
	];

	public static function install(p:JsObject, c:JsObject) {
		WebGLEnums.set(p, c, "READ_BUFFER", 0x0C02);
		WebGLEnums.set(p, c, "UNPACK_ROW_LENGTH", 0x0CF2);
		WebGLEnums.set(p, c, "UNPACK_SKIP_ROWS", 0x0CF3);
		WebGLEnums.set(p, c, "UNPACK_SKIP_PIXELS", 0x0CF4);
		WebGLEnums.set(p, c, "PACK_ROW_LENGTH", 0x0D02);
		WebGLEnums.set(p, c, "PACK_SKIP_ROWS", 0x0D03);
		WebGLEnums.set(p, c, "PACK_SKIP_PIXELS", 0x0D04);
		WebGLEnums.set(p, c, "COLOR", 0x1800);
		WebGLEnums.set(p, c, "DEPTH", 0x1801);
		WebGLEnums.set(p, c, "STENCIL", 0x1802);
		WebGLEnums.set(p, c, "RED", 0x1903);
		WebGLEnums.set(p, c, "RGB8", 0x8051);
		WebGLEnums.set(p, c, "RGBA8", 0x8058);
		WebGLEnums.set(p, c, "RGB10_A2", 0x8059);
		WebGLEnums.set(p, c, "TEXTURE_BINDING_3D", 0x806A);
		WebGLEnums.set(p, c, "UNPACK_SKIP_IMAGES", 0x806D);
		WebGLEnums.set(p, c, "UNPACK_IMAGE_HEIGHT", 0x806E);
		WebGLEnums.set(p, c, "TEXTURE_3D", 0x806F);
		WebGLEnums.set(p, c, "TEXTURE_WRAP_R", 0x8072);
		WebGLEnums.set(p, c, "MAX_3D_TEXTURE_SIZE", 0x8073);
		WebGLEnums.set(p, c, "UNSIGNED_INT_2_10_10_10_REV", 0x8368);
		WebGLEnums.set(p, c, "MAX_ELEMENTS_VERTICES", 0x80E8);
		WebGLEnums.set(p, c, "MAX_ELEMENTS_INDICES", 0x80E9);
		WebGLEnums.set(p, c, "TEXTURE_MIN_LOD", 0x813A);
		WebGLEnums.set(p, c, "TEXTURE_MAX_LOD", 0x813B);
		WebGLEnums.set(p, c, "TEXTURE_BASE_LEVEL", 0x813C);
		WebGLEnums.set(p, c, "TEXTURE_MAX_LEVEL", 0x813D);
		WebGLEnums.set(p, c, "MIN", 0x8007);
		WebGLEnums.set(p, c, "MAX", 0x8008);
		WebGLEnums.set(p, c, "DEPTH_COMPONENT24", 0x81A6);
		WebGLEnums.set(p, c, "MAX_TEXTURE_LOD_BIAS", 0x84FD);
		WebGLEnums.set(p, c, "TEXTURE_COMPARE_MODE", 0x884C);
		WebGLEnums.set(p, c, "TEXTURE_COMPARE_FUNC", 0x884D);
		WebGLEnums.set(p, c, "CURRENT_QUERY", 0x8865);
		WebGLEnums.set(p, c, "QUERY_RESULT", 0x8866);
		WebGLEnums.set(p, c, "QUERY_RESULT_AVAILABLE", 0x8867);
		WebGLEnums.set(p, c, "STREAM_READ", 0x88E1);
		WebGLEnums.set(p, c, "STREAM_COPY", 0x88E2);
		WebGLEnums.set(p, c, "STATIC_READ", 0x88E5);
		WebGLEnums.set(p, c, "STATIC_COPY", 0x88E6);
		WebGLEnums.set(p, c, "DYNAMIC_READ", 0x88E9);
		WebGLEnums.set(p, c, "DYNAMIC_COPY", 0x88EA);
		WebGLEnums.set(p, c, "MAX_DRAW_BUFFERS", 0x8824);
		WebGLEnums.set(p, c, "DRAW_BUFFER0", 0x8825);
		WebGLEnums.set(p, c, "DRAW_BUFFER1", 0x8826);
		WebGLEnums.set(p, c, "DRAW_BUFFER2", 0x8827);
		WebGLEnums.set(p, c, "DRAW_BUFFER3", 0x8828);
		WebGLEnums.set(p, c, "DRAW_BUFFER4", 0x8829);
		WebGLEnums.set(p, c, "DRAW_BUFFER5", 0x882A);
		WebGLEnums.set(p, c, "DRAW_BUFFER6", 0x882B);
		WebGLEnums.set(p, c, "DRAW_BUFFER7", 0x882C);
		WebGLEnums.set(p, c, "DRAW_BUFFER8", 0x882D);
		WebGLEnums.set(p, c, "DRAW_BUFFER9", 0x882E);
		WebGLEnums.set(p, c, "DRAW_BUFFER10", 0x882F);
		WebGLEnums.set(p, c, "DRAW_BUFFER11", 0x8830);
		WebGLEnums.set(p, c, "DRAW_BUFFER12", 0x8831);
		WebGLEnums.set(p, c, "DRAW_BUFFER13", 0x8832);
		WebGLEnums.set(p, c, "DRAW_BUFFER14", 0x8833);
		WebGLEnums.set(p, c, "DRAW_BUFFER15", 0x8834);
		WebGLEnums.set(p, c, "MAX_FRAGMENT_UNIFORM_COMPONENTS", 0x8B49);
		WebGLEnums.set(p, c, "MAX_VERTEX_UNIFORM_COMPONENTS", 0x8B4A);
		WebGLEnums.set(p, c, "SAMPLER_3D", 0x8B5F);
		WebGLEnums.set(p, c, "SAMPLER_2D_SHADOW", 0x8B62);
		WebGLEnums.set(p, c, "FRAGMENT_SHADER_DERIVATIVE_HINT", 0x8B8B);
		WebGLEnums.set(p, c, "PIXEL_PACK_BUFFER", 0x88EB);
		WebGLEnums.set(p, c, "PIXEL_UNPACK_BUFFER", 0x88EC);
		WebGLEnums.set(p, c, "PIXEL_PACK_BUFFER_BINDING", 0x88ED);
		WebGLEnums.set(p, c, "PIXEL_UNPACK_BUFFER_BINDING", 0x88EF);
		WebGLEnums.set(p, c, "FLOAT_MAT2x3", 0x8B65);
		WebGLEnums.set(p, c, "FLOAT_MAT2x4", 0x8B66);
		WebGLEnums.set(p, c, "FLOAT_MAT3x2", 0x8B67);
		WebGLEnums.set(p, c, "FLOAT_MAT3x4", 0x8B68);
		WebGLEnums.set(p, c, "FLOAT_MAT4x2", 0x8B69);
		WebGLEnums.set(p, c, "FLOAT_MAT4x3", 0x8B6A);
		WebGLEnums.set(p, c, "SRGB", 0x8C40);
		WebGLEnums.set(p, c, "SRGB8", 0x8C41);
		WebGLEnums.set(p, c, "SRGB8_ALPHA8", 0x8C43);
		WebGLEnums.set(p, c, "COMPARE_REF_TO_TEXTURE", 0x884E);
		WebGLEnums.set(p, c, "RGBA32F", 0x8814);
		WebGLEnums.set(p, c, "RGB32F", 0x8815);
		WebGLEnums.set(p, c, "RGBA16F", 0x881A);
		WebGLEnums.set(p, c, "RGB16F", 0x881B);
		WebGLEnums.set(p, c, "VERTEX_ATTRIB_ARRAY_INTEGER", 0x88FD);
		WebGLEnums.set(p, c, "MAX_ARRAY_TEXTURE_LAYERS", 0x88FF);
		WebGLEnums.set(p, c, "MIN_PROGRAM_TEXEL_OFFSET", 0x8904);
		WebGLEnums.set(p, c, "MAX_PROGRAM_TEXEL_OFFSET", 0x8905);
		WebGLEnums.set(p, c, "MAX_VARYING_COMPONENTS", 0x8B4B);
		WebGLEnums.set(p, c, "TEXTURE_2D_ARRAY", 0x8C1A);
		WebGLEnums.set(p, c, "TEXTURE_BINDING_2D_ARRAY", 0x8C1D);
		WebGLEnums.set(p, c, "R11F_G11F_B10F", 0x8C3A);
		WebGLEnums.set(p, c, "UNSIGNED_INT_10F_11F_11F_REV", 0x8C3B);
		WebGLEnums.set(p, c, "RGB9_E5", 0x8C3D);
		WebGLEnums.set(p, c, "UNSIGNED_INT_5_9_9_9_REV", 0x8C3E);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_BUFFER_MODE", 0x8C7F);
		WebGLEnums.set(p, c, "MAX_TRANSFORM_FEEDBACK_SEPARATE_COMPONENTS", 0x8C80);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_VARYINGS", 0x8C83);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_BUFFER_START", 0x8C84);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_BUFFER_SIZE", 0x8C85);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN", 0x8C88);
		WebGLEnums.set(p, c, "RASTERIZER_DISCARD", 0x8C89);
		WebGLEnums.set(p, c, "MAX_TRANSFORM_FEEDBACK_INTERLEAVED_COMPONENTS", 0x8C8A);
		WebGLEnums.set(p, c, "MAX_TRANSFORM_FEEDBACK_SEPARATE_ATTRIBS", 0x8C8B);
		WebGLEnums.set(p, c, "INTERLEAVED_ATTRIBS", 0x8C8C);
		WebGLEnums.set(p, c, "SEPARATE_ATTRIBS", 0x8C8D);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_BUFFER", 0x8C8E);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_BUFFER_BINDING", 0x8C8F);
		WebGLEnums.set(p, c, "RGBA32UI", 0x8D70);
		WebGLEnums.set(p, c, "RGB32UI", 0x8D71);
		WebGLEnums.set(p, c, "RGBA16UI", 0x8D76);
		WebGLEnums.set(p, c, "RGB16UI", 0x8D77);
		WebGLEnums.set(p, c, "RGBA8UI", 0x8D7C);
		WebGLEnums.set(p, c, "RGB8UI", 0x8D7D);
		WebGLEnums.set(p, c, "RGBA32I", 0x8D82);
		WebGLEnums.set(p, c, "RGB32I", 0x8D83);
		WebGLEnums.set(p, c, "RGBA16I", 0x8D88);
		WebGLEnums.set(p, c, "RGB16I", 0x8D89);
		WebGLEnums.set(p, c, "RGBA8I", 0x8D8E);
		WebGLEnums.set(p, c, "RGB8I", 0x8D8F);
		WebGLEnums.set(p, c, "RED_INTEGER", 0x8D94);
		WebGLEnums.set(p, c, "RGB_INTEGER", 0x8D98);
		WebGLEnums.set(p, c, "RGBA_INTEGER", 0x8D99);
		WebGLEnums.set(p, c, "SAMPLER_2D_ARRAY", 0x8DC1);
		WebGLEnums.set(p, c, "SAMPLER_2D_ARRAY_SHADOW", 0x8DC4);
		WebGLEnums.set(p, c, "SAMPLER_CUBE_SHADOW", 0x8DC5);
		WebGLEnums.set(p, c, "UNSIGNED_INT_VEC2", 0x8DC6);
		WebGLEnums.set(p, c, "UNSIGNED_INT_VEC3", 0x8DC7);
		WebGLEnums.set(p, c, "UNSIGNED_INT_VEC4", 0x8DC8);
		WebGLEnums.set(p, c, "INT_SAMPLER_2D", 0x8DCA);
		WebGLEnums.set(p, c, "INT_SAMPLER_3D", 0x8DCB);
		WebGLEnums.set(p, c, "INT_SAMPLER_CUBE", 0x8DCC);
		WebGLEnums.set(p, c, "INT_SAMPLER_2D_ARRAY", 0x8DCF);
		WebGLEnums.set(p, c, "UNSIGNED_INT_SAMPLER_2D", 0x8DD2);
		WebGLEnums.set(p, c, "UNSIGNED_INT_SAMPLER_3D", 0x8DD3);
		WebGLEnums.set(p, c, "UNSIGNED_INT_SAMPLER_CUBE", 0x8DD4);
		WebGLEnums.set(p, c, "UNSIGNED_INT_SAMPLER_2D_ARRAY", 0x8DD7);
		WebGLEnums.set(p, c, "DEPTH_COMPONENT32F", 0x8CAC);
		WebGLEnums.set(p, c, "DEPTH32F_STENCIL8", 0x8CAD);
		WebGLEnums.set(p, c, "FLOAT_32_UNSIGNED_INT_24_8_REV", 0x8DAD);
		WebGLEnums.set(p, c, "FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING", 0x8210);
		WebGLEnums.set(p, c, "FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE", 0x8211);
		WebGLEnums.set(p, c, "FRAMEBUFFER_ATTACHMENT_RED_SIZE", 0x8212);
		WebGLEnums.set(p, c, "FRAMEBUFFER_ATTACHMENT_GREEN_SIZE", 0x8213);
		WebGLEnums.set(p, c, "FRAMEBUFFER_ATTACHMENT_BLUE_SIZE", 0x8214);
		WebGLEnums.set(p, c, "FRAMEBUFFER_ATTACHMENT_ALPHA_SIZE", 0x8215);
		WebGLEnums.set(p, c, "FRAMEBUFFER_ATTACHMENT_DEPTH_SIZE", 0x8216);
		WebGLEnums.set(p, c, "FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE", 0x8217);
		WebGLEnums.set(p, c, "FRAMEBUFFER_DEFAULT", 0x8218);
		WebGLEnums.set(p, c, "DEPTH_STENCIL_ATTACHMENT", 0x821A);
		WebGLEnums.set(p, c, "DEPTH_STENCIL", 0x84F9);
		WebGLEnums.set(p, c, "UNSIGNED_INT_24_8", 0x84FA);
		WebGLEnums.set(p, c, "DEPTH24_STENCIL8", 0x88F0);
		WebGLEnums.set(p, c, "UNSIGNED_NORMALIZED", 0x8C17);
		WebGLEnums.set(p, c, "DRAW_FRAMEBUFFER_BINDING", 0x8CA6);
		WebGLEnums.set(p, c, "READ_FRAMEBUFFER", 0x8CA8);
		WebGLEnums.set(p, c, "DRAW_FRAMEBUFFER", 0x8CA9);
		WebGLEnums.set(p, c, "READ_FRAMEBUFFER_BINDING", 0x8CAA);
		WebGLEnums.set(p, c, "RENDERBUFFER_SAMPLES", 0x8CAB);
		WebGLEnums.set(p, c, "FRAMEBUFFER_ATTACHMENT_TEXTURE_LAYER", 0x8CD4);
		WebGLEnums.set(p, c, "MAX_COLOR_ATTACHMENTS", 0x8CDF);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT1", 0x8CE1);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT2", 0x8CE2);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT3", 0x8CE3);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT4", 0x8CE4);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT5", 0x8CE5);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT6", 0x8CE6);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT7", 0x8CE7);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT8", 0x8CE8);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT9", 0x8CE9);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT10", 0x8CEA);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT11", 0x8CEB);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT12", 0x8CEC);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT13", 0x8CED);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT14", 0x8CEE);
		WebGLEnums.set(p, c, "COLOR_ATTACHMENT15", 0x8CEF);
		WebGLEnums.set(p, c, "FRAMEBUFFER_INCOMPLETE_MULTISAMPLE", 0x8D56);
		WebGLEnums.set(p, c, "MAX_SAMPLES", 0x8D57);
		WebGLEnums.set(p, c, "HALF_FLOAT", 0x140B);
		WebGLEnums.set(p, c, "RG", 0x8227);
		WebGLEnums.set(p, c, "RG_INTEGER", 0x8228);
		WebGLEnums.set(p, c, "R8", 0x8229);
		WebGLEnums.set(p, c, "RG8", 0x822B);
		WebGLEnums.set(p, c, "R16F", 0x822D);
		WebGLEnums.set(p, c, "R32F", 0x822E);
		WebGLEnums.set(p, c, "RG16F", 0x822F);
		WebGLEnums.set(p, c, "RG32F", 0x8230);
		WebGLEnums.set(p, c, "R8I", 0x8231);
		WebGLEnums.set(p, c, "R8UI", 0x8232);
		WebGLEnums.set(p, c, "R16I", 0x8233);
		WebGLEnums.set(p, c, "R16UI", 0x8234);
		WebGLEnums.set(p, c, "R32I", 0x8235);
		WebGLEnums.set(p, c, "R32UI", 0x8236);
		WebGLEnums.set(p, c, "RG8I", 0x8237);
		WebGLEnums.set(p, c, "RG8UI", 0x8238);
		WebGLEnums.set(p, c, "RG16I", 0x8239);
		WebGLEnums.set(p, c, "RG16UI", 0x823A);
		WebGLEnums.set(p, c, "RG32I", 0x823B);
		WebGLEnums.set(p, c, "RG32UI", 0x823C);
		WebGLEnums.set(p, c, "VERTEX_ARRAY_BINDING", 0x85B5);
		WebGLEnums.set(p, c, "R8_SNORM", 0x8F94);
		WebGLEnums.set(p, c, "RG8_SNORM", 0x8F95);
		WebGLEnums.set(p, c, "RGB8_SNORM", 0x8F96);
		WebGLEnums.set(p, c, "RGBA8_SNORM", 0x8F97);
		WebGLEnums.set(p, c, "SIGNED_NORMALIZED", 0x8F9C);
		WebGLEnums.set(p, c, "COPY_READ_BUFFER", 0x8F36);
		WebGLEnums.set(p, c, "COPY_WRITE_BUFFER", 0x8F37);
		WebGLEnums.set(p, c, "COPY_READ_BUFFER_BINDING", 0x8F36);
		WebGLEnums.set(p, c, "COPY_WRITE_BUFFER_BINDING", 0x8F37);
		WebGLEnums.set(p, c, "UNIFORM_BUFFER", 0x8A11);
		WebGLEnums.set(p, c, "UNIFORM_BUFFER_BINDING", 0x8A28);
		WebGLEnums.set(p, c, "UNIFORM_BUFFER_START", 0x8A29);
		WebGLEnums.set(p, c, "UNIFORM_BUFFER_SIZE", 0x8A2A);
		WebGLEnums.set(p, c, "MAX_VERTEX_UNIFORM_BLOCKS", 0x8A2B);
		WebGLEnums.set(p, c, "MAX_FRAGMENT_UNIFORM_BLOCKS", 0x8A2D);
		WebGLEnums.set(p, c, "MAX_COMBINED_UNIFORM_BLOCKS", 0x8A2E);
		WebGLEnums.set(p, c, "MAX_UNIFORM_BUFFER_BINDINGS", 0x8A2F);
		WebGLEnums.set(p, c, "MAX_UNIFORM_BLOCK_SIZE", 0x8A30);
		WebGLEnums.set(p, c, "MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS", 0x8A31);
		WebGLEnums.set(p, c, "MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS", 0x8A33);
		WebGLEnums.set(p, c, "UNIFORM_BUFFER_OFFSET_ALIGNMENT", 0x8A34);
		WebGLEnums.set(p, c, "ACTIVE_UNIFORM_BLOCKS", 0x8A36);
		WebGLEnums.set(p, c, "UNIFORM_TYPE", 0x8A37);
		WebGLEnums.set(p, c, "UNIFORM_SIZE", 0x8A38);
		WebGLEnums.set(p, c, "UNIFORM_BLOCK_INDEX", 0x8A3A);
		WebGLEnums.set(p, c, "UNIFORM_OFFSET", 0x8A3B);
		WebGLEnums.set(p, c, "UNIFORM_ARRAY_STRIDE", 0x8A3C);
		WebGLEnums.set(p, c, "UNIFORM_MATRIX_STRIDE", 0x8A3D);
		WebGLEnums.set(p, c, "UNIFORM_IS_ROW_MAJOR", 0x8A3E);
		WebGLEnums.set(p, c, "UNIFORM_BLOCK_BINDING", 0x8A3F);
		WebGLEnums.set(p, c, "UNIFORM_BLOCK_DATA_SIZE", 0x8A40);
		WebGLEnums.set(p, c, "UNIFORM_BLOCK_ACTIVE_UNIFORMS", 0x8A42);
		WebGLEnums.set(p, c, "UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES", 0x8A43);
		WebGLEnums.set(p, c, "UNIFORM_BLOCK_REFERENCED_BY_VERTEX_SHADER", 0x8A44);
		WebGLEnums.set(p, c, "UNIFORM_BLOCK_REFERENCED_BY_FRAGMENT_SHADER", 0x8A46);
		WebGLEnums.set(p, c, "INVALID_INDEX", 4294967295.);
		WebGLEnums.set(p, c, "MAX_VERTEX_OUTPUT_COMPONENTS", 0x9122);
		WebGLEnums.set(p, c, "MAX_FRAGMENT_INPUT_COMPONENTS", 0x9125);
		WebGLEnums.set(p, c, "MAX_SERVER_WAIT_TIMEOUT", 0x9111);
		WebGLEnums.set(p, c, "OBJECT_TYPE", 0x9112);
		WebGLEnums.set(p, c, "SYNC_CONDITION", 0x9113);
		WebGLEnums.set(p, c, "SYNC_STATUS", 0x9114);
		WebGLEnums.set(p, c, "SYNC_FLAGS", 0x9115);
		WebGLEnums.set(p, c, "SYNC_FENCE", 0x9116);
		WebGLEnums.set(p, c, "SYNC_GPU_COMMANDS_COMPLETE", 0x9117);
		WebGLEnums.set(p, c, "UNSIGNALED", 0x9118);
		WebGLEnums.set(p, c, "SIGNALED", 0x9119);
		WebGLEnums.set(p, c, "ALREADY_SIGNALED", 0x911A);
		WebGLEnums.set(p, c, "TIMEOUT_EXPIRED", 0x911B);
		WebGLEnums.set(p, c, "CONDITION_SATISFIED", 0x911C);
		WebGLEnums.set(p, c, "WAIT_FAILED", 0x911D);
		WebGLEnums.set(p, c, "SYNC_FLUSH_COMMANDS_BIT", 0x00000001);
		WebGLEnums.set(p, c, "VERTEX_ATTRIB_ARRAY_DIVISOR", 0x88FE);
		WebGLEnums.set(p, c, "ANY_SAMPLES_PASSED", 0x8C2F);
		WebGLEnums.set(p, c, "ANY_SAMPLES_PASSED_CONSERVATIVE", 0x8D6A);
		WebGLEnums.set(p, c, "SAMPLER_BINDING", 0x8919);
		WebGLEnums.set(p, c, "RGB10_A2UI", 0x906F);
		WebGLEnums.set(p, c, "INT_2_10_10_10_REV", 0x8D9F);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK", 0x8E22);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_PAUSED", 0x8E23);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_ACTIVE", 0x8E24);
		WebGLEnums.set(p, c, "TRANSFORM_FEEDBACK_BINDING", 0x8E25);
		WebGLEnums.set(p, c, "TEXTURE_IMMUTABLE_FORMAT", 0x912F);
		WebGLEnums.set(p, c, "MAX_ELEMENT_INDEX", 0x8D6B);
		WebGLEnums.set(p, c, "TEXTURE_IMMUTABLE_LEVELS", 0x82DF);
		WebGLEnums.set(p, c, "TIMEOUT_IGNORED", -1);
		WebGLEnums.set(p, c, "MAX_CLIENT_WAIT_TIMEOUT_WEBGL", 0x9247);
	}
}
