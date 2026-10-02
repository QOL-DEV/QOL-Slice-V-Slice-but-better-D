package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import funkin.qol.util.QOLFilePicker.QOLPickedFile;
import haxe.io.Bytes;

class XFLFile
{
  public static function read(files:Array<QOLPickedFile>):AnimDoc
    throw 'Coming soon';

  public static function write(doc:AnimDoc):Bytes
    throw 'Coming soon';
}
#end
