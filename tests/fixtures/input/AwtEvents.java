package org.silicanto.canvas;
import java.awt.KeyboardFocusManager;
import java.awt.event.*;
import javax.swing.*;

public final class AwtEvents {
  public static void main(String[] args) throws Exception {
    SwingUtilities.invokeAndWait(() -> {
      JPanel panel = new JPanel();
      panel.setSize(96, 64);
      new CanvasInput(panel, 96, 64);
      long when = System.currentTimeMillis();
      for (int type :
           new int[] {MouseEvent.MOUSE_PRESSED, MouseEvent.MOUSE_RELEASED})
        panel.dispatchEvent(new MouseEvent(panel, type, when, 0, 12, 14, 1,
                                           false, MouseEvent.BUTTON1));
      KeyboardFocusManager.getCurrentKeyboardFocusManager().redispatchEvent(
          panel, new KeyEvent(panel, KeyEvent.KEY_PRESSED, when,
                              KeyEvent.SHIFT_DOWN_MASK, KeyEvent.VK_A, 'A'));
      System.out.println(CanvasInput.drain());
    });
  }
}
