#import <Foundation/Foundation.h>
#include <string>
id sil_http(NSString *, NSArray *);
id sil_socket(NSString *, NSArray *);
id sil_audio(NSString *, NSArray *);
id sil_layout(NSString *, NSArray *);

extern "C" const char *sil_desktop(const char *request) {
  static thread_local std::string result;
  @autoreleasepool {
    NSArray *reply;
    @try {
      NSData *data = [NSData dataWithBytes:request length:strlen(request)];
      NSArray *message = [NSJSONSerialization JSONObjectWithData:data
                                                         options:0
                                                           error:nil];
      NSString *op = message[0];
      NSArray *args = message[1];
      id value;
      if ([op hasPrefix:@"http."])
        value = sil_http([op substringFromIndex:5], args);
      else if ([op hasPrefix:@"socket."])
        value = sil_socket([op substringFromIndex:7], args);
      else if ([op hasPrefix:@"audio."])
        value = sil_audio([op substringFromIndex:6], args);
      else if ([op hasPrefix:@"layout."])
        value = sil_layout([op substringFromIndex:7], args);
      else
        [NSException raise:@"Desktop" format:@"Unknown operation %@", op];
      reply = @[ @YES, value ?: NSNull.null ];
    } @catch (NSException *failure) {
      reply = @[ @NO, failure.reason ?: @"Native call failed" ];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:reply
                                                   options:0
                                                     error:nil];
    result.assign(static_cast<const char *>(data.bytes), data.length);
  }
  return result.c_str();
}
