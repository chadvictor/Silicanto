#import <AVFoundation/AVFoundation.h>

id sil_audio(NSString *op, NSArray *a) {
  static NSMutableDictionary<NSNumber *, AVAudioPlayer *> *players =
      [NSMutableDictionary new];
  static NSUInteger next = 0;
  if ([op isEqual:@"load"]) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:a[0] options:0];
    NSError *error = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:data
                                                          error:&error];
    if (!player || ![player prepareToPlay])
      [NSException raise:@"Audio"
                  format:@"%@", error.localizedDescription
                                    ?: @"Cannot decode the media"];
    NSNumber *key = @(++next);
    players[key] = player;
    return @[ key, @(player.duration) ];
  }
  NSNumber *key = a[0];
  AVAudioPlayer *p = players[key];
  if (!p)
    [NSException raise:@"Audio" format:@"Unknown audio source"];
  if ([op isEqual:@"play"])
    return @([p play]);
  if ([op isEqual:@"pause"])
    [p pause];
  else if ([op isEqual:@"seek"])
    p.currentTime = [a[1] doubleValue];
  else if ([op isEqual:@"volume"])
    p.volume = [a[1] floatValue];
  else if ([op isEqual:@"loop"])
    p.numberOfLoops = [a[1] boolValue] ? -1 : 0;
  else if ([op isEqual:@"state"])
    return @[ @(p.currentTime), @(p.playing) ];
  else if ([op isEqual:@"dispose"]) {
    [p stop];
    [players removeObjectForKey:key];
  } else
    [NSException raise:@"Audio" format:@"Unknown operation %@", op];
  return nil;
}
