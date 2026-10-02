package funkin.qol.util;

/**
 * Asset helpers for QOL Slice tools.
 */
class QOLAssets
{
  /**
   * Run `cb` once an asset library (like `week1` or `shared`) is ready.
   * Desktop builds preload every library, so this is instant there; web builds load it on demand.
   */
  public static function withLibrary(library:Null<String>, cb:Void->Void):Void
  {
    #if html5
    if (library == null || library == '' || library == 'preload' || library == 'default')
    {
      cb();
      return;
    }
    if (openfl.utils.Assets.getLibrary(library) != null)
    {
      cb();
      return;
    }
    openfl.utils.Assets.loadLibrary(library).onComplete(_ -> cb()).onError(_ -> cb());
    #else
    cb();
    #end
  }
}
