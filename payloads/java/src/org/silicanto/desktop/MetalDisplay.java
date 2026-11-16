package org.silicanto.desktop;

import java.awt.*;
import java.awt.event.*;
import java.awt.image.*;
import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.concurrent.ConcurrentLinkedQueue;
import javax.swing.*;

/** JVM desktop host. The JNI boundary carries mesh buffers and camera uniforms, never scene code. */
public final class MetalDisplay implements AutoCloseable {
    private static final String LIB = "/native/macos-arm64/libsilicanto_metal.dylib";
    static {
        if (!System.getProperty("os.name").equals("Mac OS X") ||
            !System.getProperty("os.arch").equals("aarch64"))
            throw new UnsupportedOperationException("This graphics payload requires an ARM64 JVM on macOS with Metal");
        try (var source = resource(LIB)) {
            Path path = Files.createTempFile("silicanto-metal-", ".dylib");
            path.toFile().deleteOnExit();
            Files.copy(source, path, StandardCopyOption.REPLACE_EXISTING);
            System.load(path.toString());
        } catch (IOException e) { throw new UncheckedIOException(e); }
    }

    private static InputStream resource(String name) throws IOException {
        var input = MetalDisplay.class.getResourceAsStream(name);
        if (input == null) throw new FileNotFoundException(name);
        return input;
    }
    private static byte[] shader(String name) throws IOException {
        try (var input = resource("/shaders/" + name)) { return input.readAllBytes(); }
    }

    private final int width, height;
    private final ByteBuffer pixels;
    private final IntBuffer argb;
    private final ConcurrentLinkedQueue<Integer> keys = new ConcurrentLinkedQueue<>();
    private volatile boolean open = true;
    private long renderer;
    private JFrame window;
    private JPanel canvas;
    private BufferedImage image;

    public MetalDisplay(int w, int h, boolean visible) {
        width = w; height = h;
        pixels = ByteBuffer.allocateDirect(Math.multiplyExact(Math.multiplyExact(w, h), 4)).order(ByteOrder.LITTLE_ENDIAN);
        argb = pixels.asIntBuffer();
        try { renderer = create(shader("box.metal"), shader("scene.metal")); }
        catch (IOException e) { throw new UncheckedIOException(e); }
        if (visible) try {
            EventQueue.invokeAndWait(() -> {
                image = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
                canvas = new JPanel() {
                    protected void paintComponent(Graphics g) { super.paintComponent(g); g.drawImage(image, 0, 0, null); }
                };
                canvas.setPreferredSize(new Dimension(w, h));
                window = new JFrame("Silicanto · Java / Metal");
                window.setDefaultCloseOperation(WindowConstants.DO_NOTHING_ON_CLOSE);
                window.addWindowListener(new WindowAdapter() {
                    public void windowClosing(WindowEvent e) { open = false; }
                });
                var keyboard = new KeyAdapter() {
                    boolean down;
                    public void keyPressed(KeyEvent e) {
                        if (e.getKeyCode() == KeyEvent.VK_SPACE) { keys.add(down ? 1 : 0); down = true; }
                    }
                    public void keyReleased(KeyEvent e) { if (e.getKeyCode() == KeyEvent.VK_SPACE) down = false; }
                };
                canvas.setFocusable(true);
                canvas.addKeyListener(keyboard);
                canvas.addFocusListener(new FocusAdapter() { public void focusLost(FocusEvent e) { keyboard.down = false; } });
                window.setContentPane(canvas); window.setResizable(false); window.pack();
                window.setLocationRelativeTo(null); window.setVisible(true); canvas.requestFocusInWindow();
            });
        } catch (Exception e) { close(); throw new IllegalStateException("Cannot open the Swing window", e); }
    }
    public void title(String text) {
        if (window != null) EventQueue.invokeLater(() -> window.setTitle(text + " · Java / Metal"));
    }
    public void upload(byte[] vertices, byte[] lighting, byte[] probe, int count) {
        setScene(renderer, vertices, lighting, probe, count);
    }
    public void frame(boolean aa, byte[] camera, byte[] box, byte[] color, double r, double g, double b) {
        render(renderer, width, height, aa ? 2 : 1, camera, box, color, r, g, b, pixels);
        if (window != null) try { EventQueue.invokeAndWait(() -> {
            int[] data = ((DataBufferInt)image.getRaster().getDataBuffer()).getData();
            argb.get(0, data);
            canvas.repaint();
        }); } catch (Exception e) { throw new IllegalStateException("Cannot display the Metal frame", e); }
    }
    public int nextKey() { Integer k = keys.poll(); return k == null ? -1 : k; }
    public boolean isOpen() { return open; }
    public void capture(String path) {
        try (var out = new BufferedOutputStream(Files.newOutputStream(Path.of(path)))) {
            out.write(("P6\n" + width + " " + height + "\n255\n").getBytes(StandardCharsets.US_ASCII));
            byte[] row = new byte[width * 3];
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    int rgb = argb.get(y * width + x), off = x * 3;
                    row[off] = (byte)(rgb >> 16); row[off+1] = (byte)(rgb >> 8); row[off+2] = (byte)rgb;
                }
                out.write(row);
            }
        } catch (IOException e) { throw new UncheckedIOException(e); }
    }
    public void close() {
        if (renderer != 0) { destroy(renderer); renderer = 0; }
        if (window != null) EventQueue.invokeLater(window::dispose);
        open = false;
    }
    private static native long create(byte[] boxShader, byte[] sceneShader);
    private static native void destroy(long handle);
    private static native void setScene(long handle, byte[] vertices, byte[] lights, byte[] probe, int count);
    private static native void render(long handle, int w, int h, int scale, byte[] camera, byte[] box, byte[] color,
                                      double r, double g, double b, ByteBuffer pixels);
}
