package funkin.qol.guide;

#if FEATURE_HAXEUI
import flixel.FlxState;
import haxe.ui.containers.dialogs.Dialog;

/**
 * The built-in QOL Slice guide.
 */
class GuideState extends funkin.qol.ui.QOLEditorState
{
  var startPage:String;

  public function new(?page:String)
  {
    super();
    editorName = 'Guide';
    startPage = page ?? 'welcome';
  }

  /**
   * Open the guide as a dialog over the current editor.
   */
  public static function openOver(state:FlxState, page:String):Void
  {
    var dialog = new GuideDialog(page);
    dialog.showDialog(true);
  }

  override function buildEditor():Void
  {
    var view = new GuideView(startPage, FlxG.width - 40, FlxG.height - 90);
    view.left = 20;
    view.top = 44;
    root.addComponent(view);
  }
}

class GuideDialog extends Dialog
{
  public function new(page:String)
  {
    super();
    title = 'QOL Slice Guide';
    buttons = DialogButton.CLOSE;
    destroyOnClose = true;
    addComponent(new GuideView(page, 980, 560));
  }
}
#end
