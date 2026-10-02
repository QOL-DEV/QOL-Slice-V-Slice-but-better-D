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
   * Close any open dropdown list / color picker popup. Returns true if one was open.
   */
  public static function closePopups():Bool
  {
    var closed = false;
    @:privateAccess
    for (root in Screen.instance.rootComponents.copy())
    {
      var drops:Array<haxe.ui.components.DropDown> = root.findComponents(null, haxe.ui.components.DropDown, -1);
      if (Std.isOfType(root, haxe.ui.components.DropDown)) drops.push(cast root);
      for (d in drops)
      {
        if (d.dropDownOpen)
        {
          d.hideDropDown();
          closed = true;
        }
      }
    }
    return closed;
  }

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
