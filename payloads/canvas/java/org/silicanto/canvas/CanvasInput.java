package org.silicanto.canvas;

import java.awt.event.*;
import java.util.ArrayDeque;
import java.util.HashSet;
import java.util.Locale;
import javax.swing.JPanel;

final class CanvasInput extends MouseAdapter implements KeyListener {
  private static final ArrayDeque<String> queue = new ArrayDeque<>();
  private final JPanel panel;
  private final HashSet<Integer> down = new HashSet<>();
  private int width, height;
  CanvasInput(JPanel panel, int w, int h) {
    this.panel = panel;
    width = w;
    height = h;
    panel.setFocusable(true);
    panel.setFocusTraversalKeysEnabled(false);
    panel.addKeyListener(this);
    panel.addMouseListener(this);
    panel.addMouseMotionListener(this);
    panel.addMouseWheelListener(this);
    panel.addComponentListener(new ComponentAdapter() {
      @Override
      public void componentResized(ComponentEvent e) {
        add("{\"type\":\"resize\",\"width\":" + panel.getWidth() +
            ",\"height\":" + panel.getHeight() + "}");
      }
    });
  }
  void surface(int w, int h) {
    width = w;
    height = h;
  }
  private static synchronized void add(String event) { queue.add(event); }
  static synchronized String drain() {
    String result = "[" + String.join(",", queue) + "]";
    queue.clear();
    return result;
  }
  private static String quote(String s) {
    StringBuilder b = new StringBuilder("\"");
    for (char c : s.toCharArray()) {
      if (c == '"' || c == '\\')
        b.append('\\');
      if (c < 32)
        b.append(String.format(Locale.ROOT, "\\u%04x", (int)c));
      else
        b.append(c);
    }
    return b.append('"').toString();
  }
  private String mods(InputEvent e) {
    return ",\"ctrlKey\":" + e.isControlDown() +
        ",\"shiftKey\":" + e.isShiftDown() +
        ",\"metaKey\":" + e.isMetaDown() + ",\"altKey\":" + e.isAltDown();
  }
  private void mouse(String type, MouseEvent e) {
    int b = e.getButton(), m = e.getModifiersEx();
    int buttons = ((m & InputEvent.BUTTON1_DOWN_MASK) != 0 ? 1 : 0) |
                  ((m & InputEvent.BUTTON2_DOWN_MASK) != 0 ? 4 : 0) |
                  ((m & InputEvent.BUTTON3_DOWN_MASK) != 0 ? 2 : 0);
    String wheel = e instanceof MouseWheelEvent
                       ? ",\"deltaMode\":1,\"deltaX\":0,\"deltaY\":" +
                             ((MouseWheelEvent)e).getPreciseWheelRotation()
                       : "";
    add("{\"type\":" + quote(type) + ",\"x\":" +
        e.getX() * (double)width / Math.max(1, panel.getWidth()) + ",\"y\":" +
        e.getY() * (double)height / Math.max(1, panel.getHeight()) +
        ",\"button\":" + (b - 1) + ",\"buttons\":" + buttons + mods(e) +
        wheel + "}");
  }
  public void mousePressed(MouseEvent e) {
    panel.requestFocusInWindow();
    mouse("pointerdown", e);
  }
  public void mouseReleased(MouseEvent e) { mouse("pointerup", e); }
  public void mouseMoved(MouseEvent e) { mouse("pointermove", e); }
  public void mouseDragged(MouseEvent e) { mouseMoved(e); }
  public void mouseWheelMoved(MouseWheelEvent e) { mouse("wheel", e); }
  private void key(String type, KeyEvent e, boolean repeat) {
    int n = e.getKeyCode();
    String code = switch (n) {
      case KeyEvent.VK_LEFT -> "ArrowLeft";
      case KeyEvent.VK_RIGHT -> "ArrowRight";
      case KeyEvent.VK_UP -> "ArrowUp";
      case KeyEvent.VK_DOWN -> "ArrowDown";
      case KeyEvent.VK_SPACE -> "Space";
      default ->
        n >= 65 && n <= 90   ? "Key" + (char)n
        : n >= 48 && n <= 57 ? "Digit" + (char)n
                             : KeyEvent.getKeyText(n).replace(" ", "");
    };
    String key =
        e.getKeyChar() != KeyEvent.CHAR_UNDEFINED && e.getKeyChar() >= 32
            ? String.valueOf(e.getKeyChar())
            : code;
    add("{\"type\":" + quote(type) + ",\"key\":" + quote(key) +
        ",\"code\":" + quote(code) + ",\"keyCode\":" + n +
        ",\"repeat\":" + repeat + mods(e) + "}");
  }
  public void keyPressed(KeyEvent e) {
    key("keydown", e, !down.add(e.getKeyCode()));
  }
  public void keyReleased(KeyEvent e) {
    down.remove(e.getKeyCode());
    key("keyup", e, false);
  }
  public void keyTyped(KeyEvent e) {}
}
