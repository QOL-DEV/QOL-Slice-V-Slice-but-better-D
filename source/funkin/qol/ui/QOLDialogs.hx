package funkin.qol.ui;

#if FEATURE_HAXEUI
import haxe.ui.containers.dialogs.Dialog;
import haxe.ui.containers.dialogs.Dialog.DialogButton;
import haxe.ui.core.Screen;

/**
 * Small helpers for HaxeUI dialogs shared by the Mod Menu and every editor.
 */
class QOLDialogs
{
  /**
   * The dialog on top, if any is open.
   */
  public static function top():Null<Dialog>
  {
    var found:Null<Dialog> = null;
    @:privateAccess
    for (c in Screen.instance.rootComponents)
      if (Std.isOfType(c, Dialog)) found = cast c;
    return found;
  }

  public static function anyOpen():Bool
    return top() != null;

  /**
   * Close the top dialog as if Cancel was pressed. Returns true if one was closed.
   */
  public static function closeTop():Bool
  {
    var d = top();
    if (d == null) return false;
    d.hideDialog(DialogButton.CANCEL);
    return true;
  }
}
#end
