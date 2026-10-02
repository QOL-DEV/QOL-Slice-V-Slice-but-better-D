package funkin.qol.util;

import haxe.io.Bytes;

typedef QOLPickedFile =
{
  var name:String;
  var bytes:Bytes;

  /**
   * Full path on disk (desktop only), so related files next to it can be found.
   */
  var ?path:String;
}

/**
 * Pick files from anywhere on the computer: the system file dialog on desktop, the browser's file picker on the web.
 */
class QOLFilePicker
{
  /**
   * @param extensions Without dots, e.g. ['png', 'xml'].
   */
  public static function open(title:String, extensions:Array<String>, multiple:Bool, onPick:Array<QOLPickedFile>->Void):Void
  {
    #if html5
    var input:js.html.InputElement = cast js.Browser.document.createElement('input');
    input.type = 'file';
    input.multiple = multiple;
    if (extensions.length > 0) input.accept = [for (e in extensions) '.$e'].join(',');
    input.style.display = 'none';
    js.Browser.document.body.appendChild(input);
    input.onchange = function(_) {
      var files = [for (i in 0...input.files.length) input.files[i]];
      var out:Array<QOLPickedFile> = [];
      var left = files.length;
      if (left == 0) return;
      for (f in files)
      {
        var reader = new js.html.FileReader();
        reader.onload = function(_) {
          out.push({name: f.name, bytes: Bytes.ofData(cast reader.result)});
          left--;
          if (left == 0)
          {
            input.remove();
            onPick(out);
          }
        };
        reader.readAsArrayBuffer(f);
      }
    };
    input.click();
    #elseif desktop
    var filters = [new lime.ui.FileDialogFilter(title, extensions.length > 0 ? extensions.join(';') : '*'), new lime.ui.FileDialogFilter('All files', '*')];
    lime.ui.FileDialog.openFile(openfl.Lib.current.stage.window, title, function(paths:Array<String>, _) {
      if (paths == null || paths.length == 0) return;
      var out:Array<QOLPickedFile> = [];
      for (p in paths)
      {
        try
        {
          out.push({name: haxe.io.Path.withoutDirectory(p), bytes: sys.io.File.getBytes(p), path: p});
        }
        catch (e)
        {
          trace('[QOL] Could not read $p: $e');
        }
      }
      if (out.length > 0) onPick(out);
    }, filters, null, multiple);
    #else
    trace('[QOL] File picking is not available on this platform.');
    #end
  }

  /**
   * Call `onDrop` with the files dropped onto the game window (everything dropped at once arrives together; a dropped
   * folder brings every file inside it, named by their path inside it). `x` and `y` are in window pixels. Returns a
   * function that stops listening.
   */
  public static function listenForDrops(onDrop:(files:Array<QOLPickedFile>, x:Float, y:Float) -> Void):Void->Void
  {
    var window = lime.app.Application.current?.window;
    if (window == null) return () -> {};
    var pending:Array<Dynamic> = [];
    var dropX = 0.0, dropY = 0.0;
    var scheduled = false;
    function handler(file:String, _:String, x:Float, y:Float):Void
    {
      pending.push(file);
      dropX = x;
      dropY = y;
      if (scheduled) return;
      scheduled = true;
      // Several files dropped together come one at a time.
      haxe.Timer.delay(() -> {
        scheduled = false;
        var list = pending;
        pending = [];
        readDropped(list, files -> if (files.length > 0) onDrop(files, dropX, dropY));
      }, 40);
    }
    window.onDropFile.add(handler);
    return () -> window.onDropFile.remove(handler);
  }

  static function readDropped(items:Array<Dynamic>, done:Array<QOLPickedFile>->Void):Void
  {
    #if html5
    var out:Array<QOLPickedFile> = [];
    var left = items.length;
    for (item in items)
    {
      var f:js.html.File = cast item;
      var reader = new js.html.FileReader();
      reader.onload = function(_) {
        out.push({name: f.name, bytes: Bytes.ofData(cast reader.result)});
        if (--left == 0) done(out);
      };
      reader.onerror = function(_) {
        if (--left == 0) done(out);
      };
      reader.readAsArrayBuffer(f);
    }
    #elseif sys
    var out:Array<QOLPickedFile> = [];
    for (item in items)
    {
      var path:String = cast item;
      try
      {
        if (sys.FileSystem.isDirectory(path))
        {
          // A folder (like an .xfl project): every file in it, named by its path inside the folder.
          var base = haxe.io.Path.withoutDirectory(haxe.io.Path.removeTrailingSlashes(path));
          function walk(dir:String, rel:String)
          {
            for (name in sys.FileSystem.readDirectory(dir))
            {
              var full = haxe.io.Path.join([dir, name]);
              var r = rel == '' ? name : rel + '/' + name;
              if (sys.FileSystem.isDirectory(full)) walk(full, r);
              else
                out.push({name: r, bytes: sys.io.File.getBytes(full), path: full});
            }
          }
          walk(path, '');
          if (StringTools.endsWith(base.toLowerCase(), '.xfl')) out.push({name: base, bytes: Bytes.alloc(0), path: path});
        }
        else
          out.push({name: haxe.io.Path.withoutDirectory(path), bytes: sys.io.File.getBytes(path), path: path});
      }
      catch (e)
      {
        trace('[QOL] Could not read dropped file $path: $e');
      }
    }
    done(out);
    #else
    done([]);
    #end
  }

  /**
   * Read a file next to a picked one (desktop only; on the web, pick both files instead).
   */
  public static function sibling(file:QOLPickedFile, name:String):Null<Bytes>
  {
    #if sys
    if (file.path == null) return null;
    var p = haxe.io.Path.join([haxe.io.Path.directory(file.path), name]);
    if (sys.FileSystem.exists(p)) return sys.io.File.getBytes(p);
    #end
    return null;
  }

  public static function ext(name:String):String
    return (haxe.io.Path.extension(name) ?? '').toLowerCase();
}
