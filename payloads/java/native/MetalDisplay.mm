#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "org_silicanto_desktop_MetalDisplay.h"
#include <memory>

struct Surface {
    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    id<MTLRenderPipelineState> scene, box, boxWide, resolve;
    id<MTLBuffer> vertices, lights, probe;
    id<MTLTexture> intermediate, output;
    NSUInteger count = 0;
};

static void fail(JNIEnv *env, NSString *message) {
    if (!env->ExceptionCheck())
        env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message.UTF8String);
}
static id<MTLLibrary> library(JNIEnv *env, Surface &s, jbyteArray source) {
    auto bytes = [NSMutableData dataWithLength:env->GetArrayLength(source)];
    env->GetByteArrayRegion(source, 0, (jsize)bytes.length, (jbyte *)bytes.mutableBytes);
    NSString *text = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
    NSError *error = nil;
    auto lib = [s.device newLibraryWithSource:text options:nil error:&error];
    if (!lib) fail(env, error.localizedDescription ?: @"Cannot compile Metal library");
    return lib;
}
static id<MTLRenderPipelineState> pipeline(JNIEnv *env, Surface &s, id<MTLLibrary> lib,
                                            NSString *vert, NSString *frag, MTLPixelFormat format) {
    auto desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = [lib newFunctionWithName:vert];
    desc.fragmentFunction = [lib newFunctionWithName:frag];
    desc.colorAttachments[0].pixelFormat = format;
    NSError *error = nil;
    auto p = [s.device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!p) fail(env, error.localizedDescription ?: @"Cannot create Metal pipeline");
    return p;
}
#define JNI_DISPLAY(name) Java_org_silicanto_desktop_MetalDisplay_##name
JNIEXPORT jlong JNICALL JNI_DISPLAY(create)(JNIEnv *env, jclass, jbyteArray box, jbyteArray world) {
    @autoreleasepool {
        auto s = std::make_unique<Surface>();
        s->device = MTLCreateSystemDefaultDevice();
        s->queue = [s->device newCommandQueue];
        if (!s->queue) { fail(env, @"No Metal command queue on this Mac"); return 0; }
        auto b = library(env, *s, box);
        if (!b) return 0;
        auto w = library(env, *s, world);
        if (!w) return 0;
        s->scene = pipeline(env,*s,w,@"sceneVertex",@"sceneColor",MTLPixelFormatRGBA32Float);
        s->box = pipeline(env,*s,b,@"boxVertex",@"boxColor",MTLPixelFormatBGRA8Unorm);
        s->boxWide = pipeline(env,*s,b,@"boxVertex",@"boxColor",MTLPixelFormatRGBA32Float);
        s->resolve = pipeline(env,*s,b,@"screenVertex",@"resolveColor",MTLPixelFormatBGRA8Unorm);
        return env->ExceptionCheck() ? 0 : reinterpret_cast<jlong>(s.release());
    }
}
JNIEXPORT void JNICALL JNI_DISPLAY(destroy)(JNIEnv *, jclass, jlong handle) {
    @autoreleasepool { delete reinterpret_cast<Surface *>(handle); }
}
static id<MTLBuffer> upload(JNIEnv *env, Surface &s, jbyteArray bytes) {
    jsize len = env->GetArrayLength(bytes);
    auto buffer = [s.device newBufferWithLength:MAX(16, len) options:MTLResourceStorageModeShared];
    if (buffer) env->GetByteArrayRegion(bytes, 0, len, (jbyte *)buffer.contents);
    else fail(env, @"Cannot allocate Metal geometry buffer");
    return buffer;
}
JNIEXPORT void JNICALL JNI_DISPLAY(setScene)(JNIEnv *env, jclass, jlong handle, jbyteArray vertices,
                                               jbyteArray lights, jbyteArray probe, jint count) {
    @autoreleasepool {
        auto &s = *reinterpret_cast<Surface *>(handle);
        if (!vertices || !lights || !probe || count < 0 || count * 64LL != env->GetArrayLength(vertices)
            || env->GetArrayLength(lights) != 208 || env->GetArrayLength(probe) < 16) {
            fail(env, @"Invalid Metal mesh or lighting buffers"); return;
        }
        s.vertices = upload(env,s,vertices); if (!s.vertices) return;
        s.lights = upload(env,s,lights); if (!s.lights) return;
        s.probe = upload(env,s,probe); s.count = count;
    }
}
static id<MTLTexture> texture(Surface &s, NSUInteger w, NSUInteger h, MTLPixelFormat fmt, bool shared) {
    auto d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:fmt width:w height:h mipmapped:NO];
    d.usage = shared ? MTLTextureUsageRenderTarget : MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    d.storageMode = shared ? MTLStorageModeShared : MTLStorageModePrivate;
    return [s.device newTextureWithDescriptor:d];
}
static id<MTLRenderCommandEncoder> pass(id<MTLCommandBuffer> cmd, id<MTLTexture> target, MTLClearColor clear) {
    auto d = [MTLRenderPassDescriptor renderPassDescriptor];
    auto color = d.colorAttachments[0];
    color.texture = target; color.clearColor = clear;
    color.loadAction = MTLLoadActionClear; color.storeAction = MTLStoreActionStore;
    return [cmd renderCommandEncoderWithDescriptor:d];
}
JNIEXPORT void JNICALL JNI_DISPLAY(render)(JNIEnv *env, jclass, jlong handle, jint w, jint h, jint scale,
    jbyteArray camera, jbyteArray box, jbyteArray color, jdouble r, jdouble g, jdouble b, jobject pixels) {
    @autoreleasepool {
        auto &s = *reinterpret_cast<Surface *>(handle);
        auto fmt = camera ? MTLPixelFormatRGBA32Float : MTLPixelFormatBGRA8Unorm;
        void *dest = env->GetDirectBufferAddress(pixels);
        if (!dest || w <= 0 || h <= 0 || (scale != 1 && scale != 2) || 4LL*w*h != env->GetDirectBufferCapacity(pixels)
            || (camera && (env->GetArrayLength(camera) != 80 || !s.probe))
            || (box && (env->GetArrayLength(box) != 112 || !color || env->GetArrayLength(color) != 16))) {
            fail(env, @"Invalid Metal frame"); return;
        }
        NSUInteger sw = (NSUInteger)w*scale, sh = (NSUInteger)h*scale;
        if (!s.intermediate || s.intermediate.width != sw || s.intermediate.height != sh || s.intermediate.pixelFormat != fmt)
            s.intermediate = texture(s,sw,sh,fmt,false);
        if (!s.output || s.output.width != (NSUInteger)w || s.output.height != (NSUInteger)h)
            s.output = texture(s,w,h,MTLPixelFormatBGRA8Unorm,true);
        if (!s.intermediate || !s.output) { fail(env, @"Cannot allocate Metal render targets"); return; }
        auto cmd = [s.queue commandBuffer];
        auto mesh = pass(cmd,s.intermediate,MTLClearColorMake(r,g,b,1));
        if (camera) {
            float frame[20]; env->GetByteArrayRegion(camera,0,sizeof(frame),(jbyte *)frame);
            [mesh setRenderPipelineState:s.scene];
            [mesh setVertexBuffer:s.vertices offset:0 atIndex:0];
            [mesh setVertexBytes:frame length:sizeof(frame) atIndex:1];
            [mesh setFragmentBuffer:s.lights offset:0 atIndex:0];
            [mesh setFragmentBytes:frame length:sizeof(frame) atIndex:1];
            [mesh setFragmentBuffer:s.probe offset:0 atIndex:2];
            [mesh drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:s.count];
        }
        if (box) {
            float u[28], rgba[4];
            env->GetByteArrayRegion(box,0,sizeof(u),(jbyte *)u);
            env->GetByteArrayRegion(color,0,sizeof(rgba),(jbyte *)rgba);
            [mesh setRenderPipelineState:camera ? s.boxWide : s.box];
            [mesh setVertexBytes:u length:sizeof(u) atIndex:0];
            [mesh setFragmentBytes:rgba length:sizeof(rgba) atIndex:0];
            [mesh drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36];
        }
        [mesh endEncoding];
        auto screen = pass(cmd,s.output,MTLClearColorMake(0,0,0,1));
        [screen setRenderPipelineState:s.resolve]; [screen setFragmentTexture:s.intermediate atIndex:0];
        [screen setFragmentBytes:&scale length:sizeof(scale) atIndex:0];
        [screen drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [screen endEncoding];
        [cmd commit]; [cmd waitUntilCompleted];
        if (cmd.status != MTLCommandBufferStatusCompleted) { fail(env,cmd.error.localizedDescription ?: @"Metal frame failed"); return; }
        [s.output getBytes:dest bytesPerRow:(NSUInteger)w*4 fromRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0];
    }
}
