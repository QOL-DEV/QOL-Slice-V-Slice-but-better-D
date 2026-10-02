package funkin.qol.runtime;

/**
 * Starts up QOL Slice's in-game systems (custom HUDs, modcharts, death screens, menus, shaders...).
 */
class QOLRuntime
{
  static var initialized:Bool = false;

  public static function init():Void
  {
    if (initialized) return;
    initialized = true;
  }
}
