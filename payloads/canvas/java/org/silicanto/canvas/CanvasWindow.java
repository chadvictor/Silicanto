package org.silicanto.canvas;

import java.awt.Dimension;
import java.awt.Graphics;
import java.awt.image.BufferedImage;
import javax.swing.JFrame;
import javax.swing.JPanel;
import javax.swing.SwingUtilities;

/** A desktop surface for the portable RGBA backing store. */
public final class CanvasWindow {
    private static JFrame frame;
    private static volatile boolean closed;
    private static BufferedImage image;

    public static boolean present(int width, int height, byte[] rgba) {
        if (closed) return false;
        BufferedImage next = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        int[] rgb = ((java.awt.image.DataBufferInt)next.getRaster().getDataBuffer()).getData();
        for (int i=0,p=0; i<rgb.length; i++,p+=4) {
            int a=rgba[p+3]&255;
            rgb[i]=(((rgba[p]&255)*a/255)<<16)|(((rgba[p+1]&255)*a/255)<<8)|((rgba[p+2]&255)*a/255);
        }
        try {
            SwingUtilities.invokeAndWait(() -> {
                if (closed) return;
                image = next;
                if (frame == null) {
                    frame = new JFrame("Silicanto");
                    JPanel panel = new JPanel() {
                        @Override protected void paintComponent(Graphics g) {
                            super.paintComponent(g);
                            g.drawImage(image, 0, 0, getWidth(), getHeight(), null);
                        }
                    };
                    panel.setPreferredSize(new Dimension(width,height));
                    frame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
                    frame.addWindowListener(new java.awt.event.WindowAdapter() {
                        @Override public void windowClosed(java.awt.event.WindowEvent e) { closed=true; }
                    });
                    frame.setContentPane(panel); frame.pack(); frame.setLocationByPlatform(true); frame.setVisible(true);
                }
                frame.getContentPane().repaint();
            });
        } catch (Exception e) { throw new IllegalStateException("Could not present the canvas", e); }
        return !closed;
    }
    public static void close() { SwingUtilities.invokeLater(() -> { if(frame!=null)frame.dispose(); }); }
    private CanvasWindow() {}
}
