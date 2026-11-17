package org.silicanto.canvas;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public final class NativeWebGL {
  private static final String RESOURCES = "/native/webgl/macos-arm64/";
  private static final boolean AVAILABLE = load();
  private static boolean load() {
    if (!System.getProperty("os.name").equals("Mac OS X") ||
        !System.getProperty("os.arch").equals("aarch64") ||
        NativeWebGL.class.getResource(RESOURCES +
                                      "libsilicanto_webgl.dylib") == null)
      return false;
    try {
      Path dir = Files.createTempDirectory("silicanto-gl-");
      dir.toFile().deleteOnExit();
      for (String name : new String[] {"libEGL.dylib", "libGLESv2.dylib",
                                       "libsilicanto_webgl.dylib"}) {
        Path file = dir.resolve(name);
        try (InputStream in =
                 NativeWebGL.class.getResourceAsStream(RESOURCES + name)) {
          Files.copy(in, file);
        }
        file.toFile().deleteOnExit();
      }
      System.load(dir.resolve("libsilicanto_webgl.dylib").toString());
      return true;
    } catch (IOException | UnsatisfiedLinkError e) {
      throw new IllegalStateException("Cannot load the bundled WebGL driver",
                                      e);
    }
  }
  public static boolean available() { return AVAILABLE; }
  private static native byte[] invoke(byte[] input);
  public static String call(String input) {
    return new String(invoke(input.getBytes(StandardCharsets.UTF_8)),
                      StandardCharsets.UTF_8);
  }
}
