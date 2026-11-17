package org.silicanto.canvas;

import java.nio.charset.StandardCharsets;

public final class DesktopServices {
  private DesktopServices() {}
  private static native byte[] invoke(byte[] input);
  public static String call(String input) {
    if (!NativeWebGL.available())
      throw new UnsupportedOperationException(
          "Native desktop services require macOS ARM64");
    return new String(invoke(input.getBytes(StandardCharsets.UTF_8)),
                      StandardCharsets.UTF_8);
  }
}
