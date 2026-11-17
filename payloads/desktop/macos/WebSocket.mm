#import <Foundation/Foundation.h>

// NSURLSession serializes delegate callbacks. The application's frame thread
// drains events.
@interface SilSocket : NSObject <NSURLSessionWebSocketDelegate>
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionWebSocketTask *task;
@property(nonatomic, strong) NSMutableArray *events;
@property(nonatomic) BOOL finished;
- (void)receive;
@end
@implementation SilSocket
- (void)failed:(NSError *)error {
  @synchronized(self) {
    if (_finished)
      return;
    _finished = YES;
    [_events addObject:@{
      @"type" : @"error",
      @"message" : error.localizedDescription
    }];
    [_events addObject:@{
      @"type" : @"close",
      @"code" : @1006,
      @"reason" : @"",
      @"wasClean" : @NO
    }];
  }
  [_session finishTasksAndInvalidate];
}
- (void)receive {
  [_task receiveMessageWithCompletionHandler:^(
             NSURLSessionWebSocketMessage *msg, NSError *error) {
    if (error)
      return; // The task delegate reports the terminal close or transport
              // error.
    @synchronized(self) {
      if (self.finished)
        return;
      [self.events addObject:msg.type == NSURLSessionWebSocketMessageTypeString
                                 ? @{@"type" : @"message", @"text" : msg.string}
                                 : @{
                                     @"type" : @"message",
                                     @"binary" : [msg.data
                                         base64EncodedStringWithOptions:0]
                                   }];
    }
    [self receive];
  }];
}
- (void)URLSession:(NSURLSession *)session
          webSocketTask:(NSURLSessionWebSocketTask *)task
    didOpenWithProtocol:(NSString *)protocol {
  @synchronized(self) {
    if (_finished)
      return;
    [_events addObject:@{@"type" : @"open", @"protocol" : protocol ?: @""}];
  }
  [self receive];
}
- (void)URLSession:(NSURLSession *)session
       webSocketTask:(NSURLSessionWebSocketTask *)task
    didCloseWithCode:(NSURLSessionWebSocketCloseCode)code
              reason:(NSData *)reason {
  @synchronized(self) {
    if (_finished)
      return;
    _finished = YES;
    [_events addObject:@{
      @"type" : @"close",
      @"code" : @(code),
      @"wasClean" : @YES,
      @"reason" : [[NSString alloc] initWithData:reason ?: NSData.data
                                        encoding:NSUTF8StringEncoding]
          ?: @""
    }];
  }
  [session finishTasksAndInvalidate];
}
- (void)URLSession:(NSURLSession *)session
                    task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
  if (error)
    [self failed:error];
}
@end
id sil_socket(NSString *op, NSArray *args) {
  static NSMutableDictionary<NSNumber *, SilSocket *> *sockets =
      [NSMutableDictionary new];
  static NSUInteger next = 0;
  if ([op isEqual:@"open"]) {
    NSURL *url = [NSURL URLWithString:args[0]];
    if (!url.host || url.fragment ||
        ![@[ @"ws", @"wss" ] containsObject:url.scheme.lowercaseString])
      [NSException raise:@"SyntaxError"
                  format:@"Expected a ws or wss URL without a fragment"];
    SilSocket *s = [SilSocket new];
    s.events = [NSMutableArray new];
    s.session =
        [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration
                                                   .defaultSessionConfiguration
                                      delegate:s
                                 delegateQueue:nil];
    s.task = [s.session webSocketTaskWithURL:url protocols:args[1]];
    NSNumber *key = @(++next);
    sockets[key] = s;
    [s.task resume];
    return key;
  }
  NSNumber *key = args[0];
  SilSocket *s = sockets[key];
  if (!s)
    return nil;
  if ([op isEqual:@"poll"]) {
    @synchronized(s) {
      NSArray *events = [s.events copy];
      [s.events removeAllObjects];
      if (s.finished)
        [sockets removeObjectForKey:key];
      return events;
    }
  }
  if ([op isEqual:@"close"]) {
    [s.task
        cancelWithCloseCode:(NSURLSessionWebSocketCloseCode)
                                [args[1] integerValue]
                     reason:[args[2] dataUsingEncoding:NSUTF8StringEncoding]];
    return nil;
  }
  if ([op isEqual:@"send"]) {
    NSURLSessionWebSocketMessage *message =
        [args[1] boolValue]
            ? [[NSURLSessionWebSocketMessage alloc]
                  initWithData:[[NSData alloc]
                                   initWithBase64EncodedString:args[2]
                                                       options:0]]
            : [[NSURLSessionWebSocketMessage alloc] initWithString:args[2]];
    [s.task sendMessage:message
        completionHandler:^(NSError *error) {
          if (error)
            [s failed:error];
        }];
    return nil;
  }
  [NSException raise:@"WebSocket" format:@"Unknown operation %@", op];
  return nil;
}
