package funkin.qol;

import funkin.qol.util.QOLFS;
import funkin.qol.util.QOLJson;
import funkin.modding.PolymodHandler;
import haxe.io.Bytes;
import haxe.io.Path;

/**
 * Information about a mod folder, read straight from its `_polymod_meta.json`.
 */
typedef QOLModInfo =
{
  /**
   * The folder name inside `mods/` (this is what Polymod uses as the ID).
   */
  var folder:String;

  var title:String;
  var description:String;
  var modVersion:String;
  var apiVersion:String;
  var hasIcon:Bool;
  var meta:Dynamic;
}

/**
 * The "workspace" every QOL Slice editor saves into.
 *
 * There are no save dialogs in QOL Slice: every editor writes straight into
 * `mods/<active mod>/<the right folder>`, exactly where the game reads it from.
 * Pick (or create) the active mod in the Mod Menu.
 */
class ModWorkspace
{
  /**
   * Folders created for every new mod. These match where V-Slice reads modded files from.
   */
  public static final ESSENTIAL_FOLDERS:Array<String> = [
    'data/characters',
    'data/stages',
    'data/songs',
    'data/levels',
    'data/notestyles',
    'data/players',
    'data/dialogue/conversations',
    'data/dialogue/speakers',
    'data/dialogue/boxes',
    'data/qol/deaths',
    'data/qol/menus',
    'data/qol/hud',
    'data/qol/shaders',
    'data/qol/stage-events',
    'data/qol/modcharts',
    'data/qol/songs',
    'data/qol/animations',
    'data/qol/achievements',
    'images/characters',
    'images/icons',
    'images/stages',
    'images/notestyles',
    'images/menus',
    'images/storymenu/titles',
    'songs',
    'music',
    'sounds',
    'shaders',
    'scripts'
  ];

  /**
   * Root folder that contains every mod.
   */
  public static var MOD_ROOT(get, never):String;

  static function get_MOD_ROOT():String
    return PolymodHandler.MOD_FOLDER;

  /**
   * The folder name of the mod editors save into, or `null` if none is selected.
   */
  public static var current(get, set):Null<String>;

  static function get_current():Null<String>
  {
    var mod = QOLConfig.activeMod;
    if (mod != null && !QOLFS.isDirectory('$MOD_ROOT/$mod')) return null;
    return mod;
  }

  static function set_current(value:Null<String>):Null<String>
  {
    QOLConfig.activeMod = value;
    if (value != null) ensureEnabled(value);
    return value;
  }

  public static var hasMod(get, never):Bool;

  static function get_hasMod():Bool
    return current != null;

  /**
   * Full path to the active mod's folder (e.g. `mods/MyMod`).
   */
  public static var modFolder(get, never):String;

  static function get_modFolder():String
    return '$MOD_ROOT/${current ?? '_unsaved'}';

  /**
   * Turns a path relative to the mod (`data/characters/bf.json`) into a real path (`mods/MyMod/data/characters/bf.json`).
   */
  public static function path(rel:String):String
  {
    rel = rel.split('\\').join('/');
    while (rel.startsWith('/'))
      rel = rel.substr(1);
    return '$modFolder/$rel';
  }

  public static function exists(rel:String):Bool
    return QOLFS.exists(path(rel));

  public static function getText(rel:String):Null<String>
    return QOLFS.getText(path(rel));

  public static function getBytes(rel:String):Null<Bytes>
    return QOLFS.getBytes(path(rel));

  public static function getJson(rel:String):Dynamic
  {
    var text = getText(rel);
    return text == null ? null : QOLJson.tryParse(text);
  }

  /**
   * Save text into the active mod. Returns the full path written to.
   */
  public static function saveText(rel:String, text:String):String
  {
    requireMod();
    var full = path(rel);
    QOLFS.saveText(full, text);
    trace('[QOL] Saved $full');
    onSaved(rel);
    return full;
  }

  public static function saveBytes(rel:String, bytes:Bytes):String
  {
    requireMod();
    var full = path(rel);
    QOLFS.saveBytes(full, bytes);
    trace('[QOL] Saved $full');
    onSaved(rel);
    return full;
  }

  public static function saveJson(rel:String, data:Dynamic, ?keyOrder:Array<String>):String
  {
    return saveText(rel, QOLJson.stringify(data, keyOrder));
  }

  public static function delete(rel:String):Void
  {
    requireMod();
    QOLFS.delete(path(rel));
    onSaved(rel);
  }

  /**
   * List the entries of a folder inside the mod.
   */
  public static function list(relDir:String):Array<String>
    return QOLFS.readDirectory(path(relDir));

  /**
   * List every file below a folder inside the mod, relative to that folder.
   */
  public static function listRecursive(relDir:String, ?extensions:Array<String>):Array<String>
    return QOLFS.listFilesRecursive(path(relDir), extensions);

  /**
   * Copy a file from anywhere on disk into the active mod.
   */
  public static function importFile(sourcePath:String, relDest:String):String
  {
    var bytes = QOLFS.getBytes(sourcePath);
    if (bytes == null) throw 'Could not read $sourcePath';
    return saveBytes(relDest, bytes);
  }

  /**
   * Throws a friendly error if no mod is selected.
   */
  public static function requireMod():Void
  {
    if (current == null) throw 'No mod selected! Open the Mod Menu (press 7) and choose or create a mod first.';
  }

  /**
   * Called after anything is written. Listeners can refresh their file lists.
   */
  public static var onFileSaved:Array<String->Void> = [];

  static function onSaved(rel:String):Void
  {
    for (cb in onFileSaved)
      cb(rel);
  }

  //
  // Mod list management
  //

  /**
   * Read the metadata for every folder in `mods/`.
   */
  public static function listMods():Array<QOLModInfo>
  {
    var result:Array<QOLModInfo> = [];
    QOLFS.createDirectory(MOD_ROOT);
    for (folder in QOLFS.readDirectory(MOD_ROOT))
    {
      var info = readModInfo(folder);
      if (info != null) result.push(info);
    }
    return result;
  }

  public static function readModInfo(folder:String):Null<QOLModInfo>
  {
    var dir = '$MOD_ROOT/$folder';
    if (!QOLFS.isDirectory(dir)) return null;
    var meta:Dynamic = null;
    var metaPath = '$dir/_polymod_meta.json';
    if (QOLFS.exists(metaPath)) meta = QOLJson.tryParse(QOLFS.getText(metaPath));
    if (meta == null) meta = {};
    return {
      folder: folder,
      title: Reflect.field(meta, 'title') ?? folder,
      description: Reflect.field(meta, 'description') ?? '',
      modVersion: Reflect.field(meta, 'mod_version') ?? '1.0.0',
      apiVersion: Reflect.field(meta, 'api_version') ?? QOLSlice.GAME_VERSION,
      hasIcon: QOLFS.exists('$dir/_polymod_icon.png'),
      meta: meta
    };
  }

  /**
   * Makes a folder name safe to use on every OS.
   */
  public static function sanitizeFolderName(name:String):String
  {
    var result = ~/[^A-Za-z0-9_\- ]/g.replace(name.trim(), '');
    result = result.split(' ').join('-');
    return result == '' ? 'my-mod' : result;
  }

  /**
   * The default metadata written for brand new mods.
   */
  public static function defaultMeta(title:String):Dynamic
  {
    return {
      title: title,
      description: 'A Friday Night Funkin\' mod made with QOL Slice.',
      contributors: [{name: 'You', role: 'Creator'}],
      api_version: QOLSlice.GAME_VERSION,
      mod_version: '1.0.0',
      license: 'All Rights Reserved',
      homepage: ''
    };
  }

  /**
   * Create a new mod folder with metadata, a temporary icon and the essential folders.
   * @return The folder name that was created.
   */
  public static function createMod(title:String, ?folder:String, ?meta:Dynamic, createFolders:Bool = true):String
  {
    folder = sanitizeFolderName(folder ?? title);
    var base = folder;
    var n = 2;
    while (QOLFS.exists('$MOD_ROOT/$folder'))
      folder = '$base-${n++}';

    var dir = '$MOD_ROOT/$folder';
    QOLFS.createDirectory(dir);
    writeMeta(folder, meta ?? defaultMeta(title));

    if (createFolders)
    {
      for (sub in ESSENTIAL_FOLDERS)
        QOLFS.createDirectory('$dir/$sub');
    }

    var icon = funkin.qol.util.QOLIconGen.generate(title);
    if (icon != null) QOLFS.saveBytes('$dir/_polymod_icon.png', icon);

    QOLFS.saveText('$dir/README.txt', 'This mod was created with QOL Slice.\n\n'
      + 'Every QOL Slice editor saves directly into this folder.\n'
      + 'Open the Mod Menu in-game (press 7 on the main menu) to edit it.\n');

    ensureEnabled(folder);
    return folder;
  }

  public static function writeMeta(folder:String, meta:Dynamic):Void
  {
    QOLFS.saveText('$MOD_ROOT/$folder/_polymod_meta.json',
      QOLJson.stringify(meta, [
        'title', 'description', 'author', 'contributors', 'homepage', 'api_version', 'mod_version', 'license', 'metadata', 'dependencies',
        'optionalDependencies'
      ]));
  }

  /**
   * Make sure a mod is turned on, so its files actually load.
   */
  public static function ensureEnabled(folder:String):Void
  {
    setEnabled(folder, true);
  }

  public static function isEnabled(folder:String):Bool
  {
    return !QOLConfig.disabledMods.contains(folder);
  }

  public static function setEnabled(folder:String, enabled:Bool):Void
  {
    var disabled = QOLConfig.disabledMods.copy();
    if (enabled) disabled.remove(folder);
    else if (!disabled.contains(folder)) disabled.push(folder);
    QOLConfig.disabledMods = disabled;
    try
    {
      var saved:Array<String> = funkin.save.Save.instance.enabledModDirs.value.copy();
      if (enabled && !saved.contains(folder)) saved.push(folder);
      if (!enabled) saved.remove(folder);
      funkin.save.Save.instance.enabledModDirs.value = saved;
    }
    catch (e) {}
  }

  /**
   * Sorts the mods in `mods/` by the QOL Slice load order and removes disabled ones.
   * Mods load in this order, so later mods override earlier ones.
   */
  public static function resolveLoadOrder(all:Array<String>):Array<String>
  {
    var order = QOLConfig.modOrder;
    var disabled = QOLConfig.disabledMods;
    var result:Array<String> = [];
    for (dir in order)
      if (all.contains(dir) && !disabled.contains(dir) && !result.contains(dir)) result.push(dir);
    var rest = [for (dir in all) if (!result.contains(dir) && !disabled.contains(dir)) dir];
    rest.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
    return result.concat(rest);
  }

  /**
   * Every mod folder in load order (including disabled ones).
   */
  public static function orderedModFolders():Array<String>
  {
    var all = [for (m in listMods()) m.folder];
    var result:Array<String> = [];
    for (dir in QOLConfig.modOrder)
      if (all.contains(dir) && !result.contains(dir)) result.push(dir);
    var rest = [for (dir in all) if (!result.contains(dir)) dir];
    rest.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
    return result.concat(rest);
  }

  /**
   * Reload every mod and data registry so the game sees freshly saved files.
   * This is the same as V-Slice's hot reload (F5).
   */
  public static function reloadGameData():Void
  {
    try
    {
      PolymodHandler.forceReloadAssets();
    }
    catch (e)
    {
      trace('[QOL] Reload failed: $e');
    }
  }

  /**
   * Remove a mod folder completely.
   */
  public static function deleteMod(folder:String):Void
  {
    QOLFS.delete('$MOD_ROOT/$folder');
    if (QOLConfig.activeMod == folder) QOLConfig.activeMod = null;
  }

  /**
   * Turns an asset key like `characters/bf` into the mod-relative file path `images/characters/bf.png`.
   */
  public static inline function imagePath(key:String):String
    return 'images/$key.png';

  /**
   * Strips extensions/folders to get an image key: `images/characters/bf.png` -> `characters/bf`.
   */
  public static function imageKeyFromPath(rel:String):String
  {
    rel = rel.split('\\').join('/');
    if (rel.startsWith('images/')) rel = rel.substr(7);
    return Path.withoutExtension(rel);
  }
}
