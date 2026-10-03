package funkin.util.plugins;

import flixel.FlxBasic;

/**
 * A plugin which adds functionality to press `F4` to immediately transition to the main menu.
 * This is useful for debugging or if you get softlocked or something.
 */
@:nullSafety
class EvacuateDebugPlugin extends FlxBasic
{
  public function new()
  {
    super();
  }

  public static function initialize():Void
  {
    FlxG.plugins.addPlugin(new EvacuateDebugPlugin());
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);

    // QOL Slice: the Animator uses F4 (Hide Panels, like Adobe Animate).
    if (FlxG.keys.justPressed.F4 && !funkin.qol.QOLSlice.editorOwnsFunctionKeys)
    {
      FlxG.switchState(() -> new funkin.ui.mainmenu.MainMenuState());
    }
  }

  override public function destroy():Void
  {
    super.destroy();
  }
}
