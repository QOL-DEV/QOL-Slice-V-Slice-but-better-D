package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import funkin.qol.editors.animator.AnimData;
import haxe.io.Bytes;

class PSDFile
{
  public static function read(bytes:Bytes, name:String, fps:Float):AnimDoc
    throw 'Coming soon';

  public static function writeAnimated(doc:AnimDoc, sym:AnimSymbol):Bytes
    throw 'Coming soon';

  public static function writeFrame(doc:AnimDoc, sym:AnimSymbol, frame:Int):Bytes
    throw 'Coming soon';
}
#end
