package funkin.qol.menu;

#if FEATURE_HAXEUI
import flixel.FlxState;

/**
 * Creates editor states by tool ID.
 */
class QOLToolFactory
{
  public static function create(id:String):Null<FlxState>
  {
    return switch (id)
    {
      case 'test': new funkin.qol.editors.QOLTestState();
      case 'modpack': new funkin.qol.editors.ModpackManagerState();
      case 'settings': new funkin.qol.editors.EngineSettingsState();
      case 'character': new funkin.qol.editors.CharacterEditorState();
      case 'death': new funkin.qol.editors.DeathEditorState();
      case 'stage': new funkin.qol.editors.BackgroundEditorState();
      case 'chart': new funkin.qol.editors.QOLChartEditorState();
      case 'modchart': new funkin.qol.editors.ModchartEditorState();
      default: null;
    }
  }
}
#end
