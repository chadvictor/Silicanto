#import <Foundation/Foundation.h>

@interface SilRequest : NSObject
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSDictionary *result;
@end
@implementation SilRequest
@end

id sil_http(NSString *op, NSArray *a) {
  static NSMutableDictionary<NSNumber *, SilRequest *> *requests =
      [NSMutableDictionary new];
  static NSUInteger next = 0;
  if ([op isEqual:@"start"]) {
    NSURL *url = [NSURL URLWithString:a[1]];
    if (!url.host ||
        ![@[ @"http", @"https" ] containsObject:url.scheme.lowercaseString])
      [NSException raise:@"NetworkError" format:@"Expected an HTTP(S) URL"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = a[0];
    for (NSString *key in a[2])
      [request setValue:a[2][key] forHTTPHeaderField:key];
    if (a[3] != NSNull.null)
      request.HTTPBody = [[NSData alloc] initWithBase64EncodedString:a[3]
                                                             options:0];
    if ([a[4] doubleValue] > 0)
      request.timeoutInterval = [a[4] doubleValue] / 1000.;
    NSNumber *key = @(++next);
    SilRequest *record = [SilRequest new];
    requests[key] = record;
    record.task = [NSURLSession.sharedSession
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response,
                              NSError *error) {
            NSDictionary *out;
            if (error)
              out = @{
                @"error" : error.localizedDescription,
                @"timeout" : @(error.code == NSURLErrorTimedOut)
              };
            else {
              NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
              NSMutableDictionary *headers = [NSMutableDictionary dictionary];
              for (NSString *name in http.allHeaderFields)
                headers[name.lowercaseString] =
                    [http.allHeaderFields[name] description];
              out = @{
                @"status" : @(http.statusCode),
                @"url" : http.URL.absoluteString,
                @"headers" : headers,
                @"body" : [data base64EncodedStringWithOptions:0] ?: @""
              };
            }
            @synchronized(record) {
              record.result = out;
              record.task = nil;
            }
          }];
    [record.task resume];
    return key;
  }
  NSNumber *key = a[0];
  SilRequest *record = requests[key];
  if (!record)
    return nil;
  if ([op isEqual:@"abort"]) {
    @synchronized(record) {
      [record.task cancel];
    }
    [requests removeObjectForKey:key];
    return nil;
  }
  if (![op isEqual:@"poll"])
    [NSException raise:@"NetworkError" format:@"Unknown operation %@", op];
  @synchronized(record) {
    if (!record.result)
      return nil;
    [requests removeObjectForKey:key];
    return record.result;
  }
}
