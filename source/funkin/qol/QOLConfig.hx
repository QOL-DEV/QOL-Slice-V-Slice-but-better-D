package funkin.qol;

import funkin.qol.util.QOLFS;
import funkin.qol.util.QOLJson;

/**
 * Engine-wide QOL Slice settings, stored in `qolslice.json` next to the game executable.
 *
 * The important one for finished mods is `modMenuEnabled`:
 * set it to `false` (Engine Settings has a "Lock for release" button that does this)
 * and pressing 7 / ~ will no longer open any editors.
 *
 * You can also hard-lock a build by compiling with `-DQOL_LOCK_MOD_MENU`.
 */
class QOLConfig
{
  public static final CONFIG_PATH:String = 'qolslice.json';

  /**
   * Whether the Mod Menu (and every editor in it) can be opened.
   */
  public static var modMenuEnabled(get, set):Bool;

  /**
   * The mod folder that editors save into.
   */
  public static var activeMod(get, set):Null<String>;

  /**
   * Recently used mods, most recent first.
   */
  public static var recentMods(get, never):Array<String>;

  /**
   * Show V-Slice's original editors in the Mod Menu as "Legacy" tools.
   */
  public static var showLegacyTools(get, set):Bool;

  /**
   * Automatically hot-reload the game's data after an editor saves.
   */
  public static var autoReload(get, set):Bool;

  /**
   * Whether the Mod Menu has shown the "first time" welcome card.
   */
  public static var seenWelcome(get, set):Bool;

  /**
   * Fancy Mod Menu effects (beat bumps, floating arrows...). Turn off on slow PCs.
   */
  public static var fancyMenus(get, set):Bool;

  static var data:Dynamic = null;

  static function ensureLoaded():Void
  {
    if (data != null) return;
    data = {};
    try
    {
      if (QOLFS.exists(CONFIG_PATH))
      {
        var parsed = QOLJson.tryParse(QOLFS.getText(CONFIG_PATH));
        if (parsed != null) data = parsed;
      }
    }
    catch (e)
    {
      trace('[QOL] Could not read $CONFIG_PATH: $e');
    }
  }

  public static function save():Void
  {
    ensureLoaded();
    try
    {
      QOLFS.saveText(CONFIG_PATH, QOLJson.stringify(data, ['modMenuEnabled', 'activeMod', 'recentMods']));
    }
    catch (e)
    {
      trace('[QOL] Could not write $CONFIG_PATH: $e');
    }
  }

  public static function reload():Void
  {
    data = null;
    ensureLoaded();
  }

  static function getField<T>(name:String, def:T):T
  {
    ensureLoaded();
    var v:Dynamic = Reflect.field(data, name);
    return v == null ? def : cast v;
  }

  static function setField<T>(name:String, value:T):T
  {
    ensureLoaded();
    Reflect.setField(data, name, value);
    save();
    return value;
  }

  static function get_modMenuEnabled():Bool
  {
    #if QOL_LOCK_MOD_MENU
    return false;
    #else
    return getField('modMenuEnabled', true);
    #end
  }

  static function set_modMenuEnabled(value:Bool):Bool
    return setField('modMenuEnabled', value);

  static function get_activeMod():Null<String>
    return getField('activeMod', null);

  static function set_activeMod(value:Null<String>):Null<String>
  {
    if (value != null)
    {
      var recents:Array<String> = recentMods.copy();
      recents.remove(value);
      recents.insert(0, value);
      while (recents.length > 8)
        recents.pop();
      ensureLoaded();
      Reflect.setField(data, 'recentMods', recents);
    }
    return setField('activeMod', value);
  }

  static function get_recentMods():Array<String>
    return getField('recentMods', []);

  static function get_showLegacyTools():Bool
    return getField('showLegacyTools', true);

  static function set_showLegacyTools(value:Bool):Bool
    return setField('showLegacyTools', value);

  static function get_autoReload():Bool
    return getField('autoReload', true);

  static function set_autoReload(value:Bool):Bool
    return setField('autoReload', value);

  static function get_seenWelcome():Bool
    return getField('seenWelcome', false);

  static function set_seenWelcome(value:Bool):Bool
    return setField('seenWelcome', value);

  static function get_fancyMenus():Bool
    return getField('fancyMenus', true);

  static function set_fancyMenus(value:Bool):Bool
    return setField('fancyMenus', value);

  /**
   * Mod load order (folder names). Mods not listed load after these, alphabetically.
   */
  public static var modOrder(get, set):Array<String>;

  static function get_modOrder():Array<String>
    return getField('modOrder', []);

  static function set_modOrder(value:Array<String>):Array<String>
    return setField('modOrder', value);

  /**
   * Mods that are turned off (folder names). Every other mod in mods/ loads.
   */
  public static var disabledMods(get, set):Array<String>;

  static function get_disabledMods():Array<String>
    return getField('disabledMods', []);

  static function set_disabledMods(value:Array<String>):Array<String>
    return setField('disabledMods', value);

  /**
   * Generic access for editor preferences (e.g. last opened file, panel layout).
   */
  public static function getPref<T>(key:String, def:T):T
  {
    ensureLoaded();
    var prefs:Dynamic = Reflect.field(data, 'prefs');
    if (prefs == null) return def;
    var v:Dynamic = Reflect.field(prefs, key);
    return v == null ? def : cast v;
  }

  public static function setPref<T>(key:String, value:T):T
  {
    ensureLoaded();
    var prefs:Dynamic = Reflect.field(data, 'prefs');
    if (prefs == null)
    {
      prefs = {};
      Reflect.setField(data, 'prefs', prefs);
    }
    Reflect.setField(prefs, key, value);
    save();
    return value;
  }
}
