package funkin.qol.util;

import haxe.io.Bytes;
import haxe.io.Path;

/**
 * A tiny file-system layer used by every QOL Slice editor.
 *
 * On desktop builds this talks directly to the disk, which is what lets every editor
 * save straight into `mods/<your mod>/...` with no save dialogs.
 *
 * On the web there is no disk, so a simple in-memory file system is used instead.
 * This keeps the editors usable (and testable) in browser builds.
 */
class QOLFS
{
  #if !sys
  static var memFiles:Map<String, Bytes> = new Map<String, Bytes>();
  static var memDirs:Map<String, Bool> = new Map<String, Bool>();
  #end

  public static inline function normalize(path:String):String
  {
    var p = Path.normalize(path.split('\\').join('/'));
    while (p.endsWith('/') && p.length > 1)
      p = p.substr(0, p.length - 1);
    return p;
  }

  public static function exists(path:String):Bool
  {
    path = normalize(path);
    #if sys
    return sys.FileSystem.exists(path);
    #else
    return memFiles.exists(path) || memDirs.exists(path);
    #end
  }

  public static function isDirectory(path:String):Bool
  {
    path = normalize(path);
    #if sys
    return sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path);
    #else
    return memDirs.exists(path);
    #end
  }

  public static function createDirectory(path:String):Void
  {
    path = normalize(path);
    if (path == '' || path == '.') return;
    #if sys
    if (!sys.FileSystem.exists(path)) sys.FileSystem.createDirectory(path);
    #else
    var parts = path.split('/');
    var cur = '';
    for (part in parts)
    {
      cur = cur == '' ? part : '$cur/$part';
      memDirs.set(cur, true);
    }
    #end
  }

  static function sortNames(list:Array<String>):Array<String>
  {
    list.sort((a, b) -> {
      var la = a.toLowerCase();
      var lb = b.toLowerCase();
      return la < lb ? -1 : (la > lb ? 1 : 0);
    });
    return list;
  }

  public static function readDirectory(path:String):Array<String>
  {
    path = normalize(path);
    #if sys
    if (!isDirectory(path)) return [];
    return sortNames(sys.FileSystem.readDirectory(path));
    #else
    var result:Array<String> = [];
    var prefix = path + '/';
    for (key in memFiles.keys())
      if (key.startsWith(prefix) && key.substr(prefix.length).indexOf('/') == -1) result.push(key.substr(prefix.length));
    for (key in memDirs.keys())
      if (key.startsWith(prefix) && key.substr(prefix.length).indexOf('/') == -1) result.push(key.substr(prefix.length));
    return sortNames(result);
    #end
  }

  /**
   * Lists every file below a folder (recursively), returned relative to `path`.
   */
  public static function listFilesRecursive(path:String, ?extensions:Array<String>):Array<String>
  {
    var result:Array<String> = [];
    function walk(dir:String, rel:String)
    {
      for (entry in readDirectory(dir))
      {
        var full = '$dir/$entry';
        var relPath = rel == '' ? entry : '$rel/$entry';
        if (isDirectory(full)) walk(full, relPath);
        else if (extensions == null || extensions.contains(Path.extension(entry).toLowerCase())) result.push(relPath);
      }
    }
    walk(normalize(path), '');
    return result;
  }

  public static function getText(path:String):Null<String>
  {
    var bytes = getBytes(path);
    return bytes == null ? null : bytes.toString();
  }

  public static function getBytes(path:String):Null<Bytes>
  {
    path = normalize(path);
    #if sys
    if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path)) return null;
    return sys.io.File.getBytes(path);
    #else
    return memFiles.get(path);
    #end
  }

  public static function saveText(path:String, text:String):Void
  {
    saveBytes(path, Bytes.ofString(text));
  }

  public static function saveBytes(path:String, bytes:Bytes):Void
  {
    path = normalize(path);
    createDirectory(Path.directory(path));
    #if sys
    sys.io.File.saveBytes(path, bytes);
    #else
    memFiles.set(path, bytes);
    #end
  }

  public static function delete(path:String):Void
  {
    path = normalize(path);
    #if sys
    if (!sys.FileSystem.exists(path)) return;
    if (sys.FileSystem.isDirectory(path))
    {
      for (entry in sys.FileSystem.readDirectory(path))
        delete('$path/$entry');
      sys.FileSystem.deleteDirectory(path);
    }
    else
    {
      sys.FileSystem.deleteFile(path);
    }
    #else
    for (key in [for (k in memFiles.keys()) k])
      if (key == path || key.startsWith(path + '/')) memFiles.remove(key);
    for (key in [for (k in memDirs.keys()) k])
      if (key == path || key.startsWith(path + '/')) memDirs.remove(key);
    #end
  }

  public static function rename(from:String, to:String):Void
  {
    from = normalize(from);
    to = normalize(to);
    #if sys
    createDirectory(Path.directory(to));
    sys.FileSystem.rename(from, to);
    #else
    var bytes = memFiles.get(from);
    if (bytes != null)
    {
      memFiles.remove(from);
      memFiles.set(to, bytes);
    }
    #end
  }

  public static function copy(from:String, to:String):Void
  {
    var bytes = getBytes(from);
    if (bytes != null) saveBytes(to, bytes);
  }

  /**
   * Returns the absolute version of a path, for showing to the user or opening in the OS file browser.
   */
  public static function absolute(path:String):String
  {
    #if sys
    try
    {
      return normalize(sys.FileSystem.absolutePath(path));
    }
    catch (e) {}
    #end
    return normalize(path);
  }

  public static function openInExplorer(path:String):Void
  {
    #if sys
    createDirectory(path);
    funkin.util.FileUtil.openFolder(absolute(path));
    #end
  }
}
