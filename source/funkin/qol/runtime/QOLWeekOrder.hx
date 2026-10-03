package funkin.qol.runtime;

import funkin.qol.util.QOLJson;
import openfl.utils.Assets;

/**
 * The order of story mode weeks, set in the Week Editor (`data/qol/week-order.json`). Weeks it doesn't list keep the
 * game's order after the ones it does.
 */
class QOLWeekOrder
{
  public static inline final PATH:String = 'qol/week-order';

  public static function load():Array<String>
  {
    try
    {
      var path = Paths.json(PATH);
      if (Assets.exists(path))
      {
        var parsed:Dynamic = QOLJson.tryParse(Assets.getText(path));
        if (parsed != null && Std.isOfType(parsed.order, Array)) return parsed.order;
      }
    }
    catch (e:Dynamic) {}
    return [];
  }

  /**
   * Sort level ids by the saved order.
   */
  public static function apply(ids:Array<String>):Array<String>
  {
    var order = load();
    if (order.length == 0) return ids;
    var out:Array<String> = [for (id in order) if (ids.contains(id)) id];
    for (id in ids)
      if (!out.contains(id)) out.push(id);
    return out;
  }
}
