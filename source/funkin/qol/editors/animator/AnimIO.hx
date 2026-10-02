package funkin.qol.editors.animator;

import funkin.qol.editors.animator.AnimData;
import haxe.io.Bytes;
import openfl.display.BitmapData;
import openfl.display.PNGEncoderOptions;
import openfl.geom.Rectangle;
import openfl.utils.ByteArray;

/**
 * Saving and loading Animator documents in the active mod (`data/qol/animations/<id>.json` plus one PNG per bitmap in
 * `data/qol/animations/<id>/`), and PNG encoding/decoding that works the same on every platform.
 */
class AnimIO
{
  public static inline final FOLDER:String = 'data/qol/animations';

  public static function fileId(name:String):String
  {
    var id = ModWorkspace.sanitizeFolderName(name).toLowerCase();
    return id == '' ? 'animation' : id;
  }

  public static function jsonPath(id:String):String
    return '$FOLDER/$id.json';

  public static function bitmapPath(id:String, bitmapId:String):String
    return '$FOLDER/$id/$bitmapId.png';

  /**
   * Saved animations in the active mod.
   */
  public static function list():Array<String>
  {
    var out:Array<String> = [];
    for (f in ModWorkspace.list(FOLDER))
      if (StringTools.endsWith(f, '.json')) out.push(f.substr(0, f.length - 5));
    out.sort((a, b) -> a < b ? -1 : 1);
    return out;
  }

  public static function save(doc:AnimDoc):String
  {
    var id = fileId(doc.project.name);
    doc.pruneBitmaps();
    for (info in doc.project.bitmaps)
    {
      var bmp = doc.getBitmap(info.id);
      if (bmp == null) continue;
      var path = bitmapPath(id, info.id);
      if (ModWorkspace.exists(path)) continue; // Bitmaps never change once saved (painting makes a new one).
      ModWorkspace.saveBytes(path, encodePNG(bmp));
    }
    return ModWorkspace.saveText(jsonPath(id), haxe.Json.stringify(doc.project, null, '  '));
  }

  public static function load(id:String):Null<AnimDoc>
  {
    var json:Dynamic = ModWorkspace.getJson(jsonPath(id));
    if (json == null) return null;
    var project:AnimProject = json;
    var doc = new AnimDoc(project);
    for (info in project.bitmaps)
    {
      var bytes = ModWorkspace.getBytes(bitmapPath(id, info.id));
      var bmp = bytes != null ? decodePNG(bytes) : null;
      if (bmp == null) bmp = new BitmapData(Std.int(Math.max(1, info.width)), Std.int(Math.max(1, info.height)), true, 0);
      doc.bitmaps.set(info.id, bmp);
    }
    return doc;
  }

  //
  // PNG
  //

  public static function encodePNG(bmp:BitmapData, ?rect:Rectangle):Bytes
  {
    var ba:ByteArray = bmp.encode(rect ?? bmp.rect, new PNGEncoderOptions());
    return ba;
  }

  /**
   * Decode a PNG right away (no waiting for the browser), as a transparent BitmapData.
   */
  public static function decodePNG(bytes:Bytes):Null<BitmapData>
  {
    try
    {
      var reader = new format.png.Reader(new haxe.io.BytesInput(bytes));
      var data = reader.read();
      var header = format.png.Tools.getHeader(data);
      var bgra = format.png.Tools.extract32(data);
      return fromBGRA(bgra, header.width, header.height);
    }
    catch (e)
    {
      trace('[QOL] PNG decode failed: $e');
      return null;
    }
  }

  public static function fromBGRA(bgra:Bytes, w:Int, h:Int):BitmapData
  {
    var argb = new ByteArray(w * h * 4);
    for (i in 0...w * h)
    {
      var p = i * 4;
      argb[p] = bgra.get(p + 3);
      argb[p + 1] = bgra.get(p + 2);
      argb[p + 2] = bgra.get(p + 1);
      argb[p + 3] = bgra.get(p);
    }
    argb.position = 0;
    var bmp = new BitmapData(w, h, true, 0);
    bmp.setPixels(new Rectangle(0, 0, w, h), argb);
    return bmp;
  }

  /**
   * Raw ARGB bytes (unmultiplied) of a bitmap.
   */
  public static function argbBytes(bmp:BitmapData, ?rect:Rectangle):Bytes
  {
    var ba = bmp.getPixels(rect ?? bmp.rect);
    var out = Bytes.alloc(ba.length);
    ba.position = 0;
    for (i in 0...ba.length)
      out.set(i, ba[i]);
    return out;
  }

  public static function fromARGB(argb:Bytes, w:Int, h:Int):BitmapData
  {
    var ba = ByteArray.fromBytes(argb);
    ba.position = 0;
    var bmp = new BitmapData(w, h, true, 0);
    bmp.setPixels(new Rectangle(0, 0, w, h), ba);
    return bmp;
  }
}
