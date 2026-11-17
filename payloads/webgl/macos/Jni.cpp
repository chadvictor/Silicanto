#include <cstring>
#include <jni.h>
#include <string>
extern "C" const char *sil_webgl(const char *);
extern "C" JNIEXPORT jbyteArray JNICALL
Java_org_silicanto_canvas_NativeWebGL_invoke(JNIEnv *env, jclass,
                                             jbyteArray request) {
  const auto n = env->GetArrayLength(request);
  std::string s(n, '\0');
  env->GetByteArrayRegion(request, 0, n, reinterpret_cast<jbyte *>(s.data()));
  const char *out = sil_webgl(s.c_str());
  const auto length = static_cast<jsize>(strlen(out));
  auto result = env->NewByteArray(length);
  if (result)
    env->SetByteArrayRegion(result, 0, length,
                            reinterpret_cast<const jbyte *>(out));
  return result;
}
