package funkin.qol.util;

import haxe.io.Bytes;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.geom.Matrix;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;

/**
 * Generates a temporary mod icon (`_polymod_icon.png`): a colorful gradient tile with the mod's initials.
 * Replace it with a real icon from the Modpack Manager whenever you like.
 */
class QOLIconGen
{
  static final PALETTES:Array<Array<Int>> = [
    [0xFF31A2FD, 0xFF7B2FF7],
    [0xFFFF4F9A, 0xFFFF9A3C],
    [0xFF12C2A0, 0xFF1D6FE0],
    [0xFFF9D423, 0xFFFF4E50],
    [0xFF8E2DE2, 0xFF4A00E0],
    [0xFF00B09B, 0xFF96C93D],
    [0xFFFC466B, 0xFF3F5EFB]
  ];

  public static function initials(title:String):String
  {
    var words = ~/[^A-Za-z0-9 ]/g.replace(title, ' ').split(' ').filter(w -> w.length > 0);
    if (words.length == 0) return '?';
    if (words.length == 1) return words[0].substr(0, 2).toUpperCase();
    return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase();
  }

  public static function render(title:String, size:Int = 256):Null<BitmapData>
  {
    try
    {
      var hash = 0;
      for (i in 0...title.length)
        hash = (hash * 31 + StringTools.fastCodeAt(title, i)) & 0x7FFFFFFF;
      var palette = PALETTES[hash % PALETTES.length];

      var bmp = new BitmapData(size, size, true, 0x00000000);

      // Diagonal gradient, rounded corners.
      var shape = new Shape();
      var m = new Matrix();
      m.createGradientBox(size, size, Math.PI / 4);
      shape.graphics.beginGradientFill(LINEAR, [palette[0] & 0xFFFFFF, palette[1] & 0xFFFFFF], [1, 1], [0, 255], m);
      shape.graphics.drawRoundRect(0, 0, size, size, size * 0.25, size * 0.25);
      shape.graphics.endFill();
      // Soft highlight.
      shape.graphics.beginFill(0xFFFFFF, 0.12);
      shape.graphics.drawEllipse(-size * 0.2, -size * 0.45, size * 1.4, size * 0.9);
      shape.graphics.endFill();
      bmp.draw(shape, null, null, null, null, true);

      var tf = new TextField();
      var fontName:String = '_sans';
      try
      {
        var font = openfl.utils.Assets.getFont(Paths.font('vcr.ttf'));
        if (font != null) fontName = font.fontName;
      }
      catch (e) {}
      var fmt = new TextFormat(fontName, Std.int(size * 0.42), 0xFFFFFF, true);
      fmt.align = TextFormatAlign.CENTER;
      tf.defaultTextFormat = fmt;
      tf.embedFonts = fontName != '_sans';
      tf.width = size;
      tf.height = size;
      tf.text = initials(title);
      var tm = new Matrix();
      tm.translate(0, (size - tf.textHeight) / 2 - 4);
      // Drop shadow.
      var shadowMatrix = tm.clone();
      shadowMatrix.translate(size * 0.02, size * 0.025);
      bmp.draw(tf, shadowMatrix, new openfl.geom.ColorTransform(0, 0, 0, 0.35), null, null, true);
      bmp.draw(tf, tm, null, null, null, true);
      return bmp;
    }
    catch (e)
    {
      trace('[QOL] Icon generation failed: $e');
      return null;
    }
  }

  /**
   * Render and PNG-encode a temporary icon.
   */
  public static function generate(title:String, size:Int = 256):Null<Bytes>
  {
    var bmp = render(title, size);
    if (bmp == null) return null;
    return encodePNG(bmp);
  }

  public static function encodePNG(bmp:BitmapData):Null<Bytes>
  {
    try
    {
      if (bmp.image == null) return null;
      return bmp.image.encode(lime.graphics.ImageFileFormat.PNG);
    }
    catch (e)
    {
      trace('[QOL] PNG encode failed: $e');
      return null;
    }
  }
}
