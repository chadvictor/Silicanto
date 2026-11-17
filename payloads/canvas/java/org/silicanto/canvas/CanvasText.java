package org.silicanto.canvas;

import java.awt.*;
import java.awt.font.*;
import java.awt.geom.*;
import java.awt.image.*;
import java.nio.*;

public final class CanvasText {
  private static final FontRenderContext CONTEXT =
      new FontRenderContext(null, true, true);
  public static byte[] render(String family, double size, boolean bold,
                              boolean italic, String text, double stroke,
                              boolean raster) {
    Font font =
        new Font(family, (bold ? Font.BOLD : 0) | (italic ? Font.ITALIC : 0), 1)
            .deriveFont((float)size);
    LineMetrics metrics = font.getLineMetrics("Hg", CONTEXT);
    TextLayout layout =
        text.isEmpty() ? null : new TextLayout(text, font, CONTEXT);
    Shape outline =
        layout == null ? new Path2D.Float() : layout.getOutline(null);
    if (stroke > 0)
      outline = new BasicStroke((float)stroke).createStrokedShape(outline);
    Rectangle ink = outline.getBounds();
    int w = ink.width, h = ink.height;
    if ((long)w * h > 16777216)
      throw new IllegalArgumentException("Canvas glyph raster too large");
    ByteBuffer bytes = ByteBuffer.allocate(36 + (raster ? w * h : 0))
                           .order(ByteOrder.LITTLE_ENDIAN);
    for (float x : new float[] {
             layout == null ? 0 : layout.getAdvance(), ink.x, ink.y, ink.x + w,
             ink.y + h, metrics.getAscent(), metrics.getDescent(), w, h})
      bytes.putFloat(x);
    if (raster && w > 0 && h > 0) {
      BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_BYTE_GRAY);
      Graphics2D g = img.createGraphics();
      try {
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                           RenderingHints.VALUE_ANTIALIAS_ON);
        g.setColor(Color.WHITE);
        g.translate(-ink.x, -ink.y);
        g.fill(outline);
      } finally {
        g.dispose();
      }
      bytes.put(((DataBufferByte)img.getRaster().getDataBuffer()).getData());
    }
    return bytes.array();
  }
}
