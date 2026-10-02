package funkin.qol.ui;

#if FEATURE_HAXEUI
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxImageFrame;
import funkin.qol.util.QOLFS;
import funkin.util.FileUtil;
import haxe.io.Path;
import haxe.ui.components.Button;
import haxe.ui.components.Image;
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.containers.VBox;
import haxe.ui.containers.dialogs.Dialog;
import haxe.ui.data.ArrayDataSource;
import openfl.display.BitmapData;

/**
 * Pick a file from the active mod or from the base game.
 *
 * Files from your computer can be imported with one click: they are copied straight into
 * the right folder of the active mod (Sparrow/Packer atlas files next to a PNG come along automatically).
 */
class FileBrowser extends Dialog
{
  public static function open(editor:QOLEditorState, title:String, folder:String, extensions:Array<String>, onPick:String->Void,
      allowImport:Bool = true):FileBrowser
  {
    var browser = new FileBrowser(editor, title, folder, extensions, onPick, allowImport);
    browser.showDialog(true);
    return browser;
  }

  /**
   * List base-game asset keys inside `folder` (e.g. `images`) with the given extensions.
   * Returned keys are relative to the folder and have no extension: `characters/BOYFRIEND`.
   */
  public static function listGameAssets(folder:String, extensions:Array<String>):Array<String>
  {
    var result:Array<String> = [];
    var seen = new Map<String, Bool>();
    try
    {
      for (id in openfl.utils.Assets.list())
      {
        var path = id;
        var colon = path.indexOf(':');
        if (colon != -1) path = path.substr(colon + 1);
        var marker = '/$folder/';
        var idx = path.indexOf(marker);
        if (idx == -1) continue;
        var rel = path.substr(idx + marker.length);
        var ext = Path.extension(rel).toLowerCase();
        if (!extensions.contains(ext)) continue;
        var key = Path.withoutExtension(rel);
        if (seen.exists(key)) continue;
        seen.set(key, true);
        result.push(key);
      }
    }
    catch (e) {}
    result.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
    return result;
  }

  /**
   * List keys of files in the active mod's `folder`.
   */
  public static function listModAssets(folder:String, extensions:Array<String>):Array<String>
  {
    if (!ModWorkspace.hasMod) return [];
    var result:Array<String> = [];
    var seen = new Map<String, Bool>();
    for (rel in ModWorkspace.listRecursive(folder, extensions))
    {
      var key = Path.withoutExtension(rel);
      if (seen.exists(key)) continue;
      seen.set(key, true);
      result.push(key);
    }
    return result;
  }

  var editor:QOLEditorState;
  var folder:String;
  var extensions:Array<String>;
  var onPick:String->Void;
  var list:ListView;
  var search:TextField;
  var preview:Image;
  var info:Label;
  var source:String = 'mod';
  var modButton:Button;
  var gameButton:Button;
  var chosenKey:Null<String> = null;

  public function new(editor:QOLEditorState, title:String, folder:String, extensions:Array<String>, onPick:String->Void, allowImport:Bool)
  {
    super();
    this.editor = editor;
    this.folder = folder;
    this.extensions = extensions;
    this.onPick = onPick;
    this.title = title;
    this.buttons = DialogButton.CANCEL | DialogButton.OK;
    this.defaultButton = '{{ok}}';
    this.destroyOnClose = true;

    var main = new HBox();
    main.styleString = 'spacing: 10px;';
    addComponent(main);

    var left = new VBox();
    left.styleString = 'spacing: 6px;';
    main.addComponent(left);

    var tabs = new HBox();
    modButton = new Button();
    modButton.text = 'This mod';
    modButton.toggle = true;
    modButton.selected = true;
    modButton.onClick = _ -> setSource('mod');
    gameButton = new Button();
    gameButton.text = 'Base game';
    gameButton.toggle = true;
    gameButton.onClick = _ -> setSource('game');
    tabs.addComponent(modButton);
    tabs.addComponent(gameButton);
    if (allowImport)
    {
      var importBtn = new Button();
      importBtn.text = 'Import from computer...';
      importBtn.onClick = _ -> importFromComputer();
      tabs.addComponent(importBtn);
    }
    left.addComponent(tabs);

    search = new TextField();
    search.placeholder = 'Search...';
    search.width = 380;
    search.onChange = _ -> fill();
    left.addComponent(search);

    list = new ListView();
    list.width = 380;
    list.height = 380;
    list.onChange = _ -> select();
    list.onDblClick = _ -> {
      if (list.selectedItem != null) hideDialog(DialogButton.OK);
    };
    left.addComponent(list);

    var right = new VBox();
    right.styleString = 'spacing: 6px;';
    main.addComponent(right);
    var previewLabel = new Label();
    previewLabel.text = 'Preview';
    right.addComponent(previewLabel);
    preview = new Image();
    preview.width = 240;
    preview.height = 240;
    preview.scaleMode = 'fitinside';
    preview.styleString = 'background-color: #1B1D21; border: 1px solid #3A3F47;';
    right.addComponent(preview);
    info = new Label();
    info.width = 240;
    info.styleString = 'color: #9AA0A6;';
    right.addComponent(info);

    if (!ModWorkspace.hasMod || listModAssets(folder, extensions).length == 0) setSource('game');
    else
      fill();

    onDialogClosed = function(e) {
      if (e.button == DialogButton.OK && chosenKey != null) onPick(chosenKey);
    };
  }

  function setSource(s:String)
  {
    source = s;
    modButton.selected = s == 'mod';
    gameButton.selected = s == 'game';
    fill();
  }

  function fill()
  {
    var items = source == 'mod' ? listModAssets(folder, extensions) : listGameAssets(folder, extensions);
    var filter = (search.text ?? '').toLowerCase();
    var ds = new ArrayDataSource<Dynamic>();
    for (item in items)
      if (filter == '' || item.toLowerCase().indexOf(filter) != -1) ds.add({text: item});
    list.dataSource = ds;
    info.text = '${ds.size} file(s) in ${source == 'mod' ? 'mods/${ModWorkspace.current}/$folder' : 'the base game'}';
  }

  function select()
  {
    var item = list.selectedItem;
    if (item == null) return;
    chosenKey = item.text;
    if (extensions.contains('png')) showImagePreview(chosenKey);
    info.text = '$folder/$chosenKey';
  }

  function showImagePreview(key:String)
  {
    try
    {
      var bmp:BitmapData = null;
      if (source == 'mod')
      {
        var bytes = ModWorkspace.getBytes('$folder/$key.png');
        if (bytes != null) bmp = BitmapData.fromBytes(bytes);
      }
      else
      {
        var graphic = FlxG.bitmap.add(Paths.image(key));
        if (graphic != null) bmp = graphic.bitmap;
      }
      if (bmp != null)
      {
        var g = FlxGraphic.fromBitmapData(bmp, false, null, false);
        preview.resource = FlxImageFrame.fromImage(g).frame;
      }
    }
    catch (e)
    {
      trace('[QOL] Preview failed: $e');
    }
  }

  function importFromComputer()
  {
    #if sys
    var filters = [new openfl.net.FileFilter(extensions.join(', ').toUpperCase(), extensions.map(e -> '*.$e').join(';'))];
    FileUtil.browseForFile('Import into ${ModWorkspace.current}/$folder', filters, function(file) {
      try
      {
        var sub = defaultImportSubfolder();
        editor.prompt('Import file', 'Save into mods/${ModWorkspace.current}/$folder/ as:', (sub == '' ? '' : '$sub/') + Path.withoutExtension(file.name),
          function(destKey:String) {
            destKey = destKey.split('\\').join('/');
            var ext = Path.extension(file.fullPath).toLowerCase();
            ModWorkspace.saveBytes('$folder/$destKey.$ext', file.bytes);
            // Bring atlas companions along.
            for (companion in ['xml', 'txt', 'json'])
            {
              var other = Path.withoutExtension(file.fullPath) + '.$companion';
              if (companion != ext && QOLFS.exists(other)) ModWorkspace.importFile(other, '$folder/$destKey.$companion');
            }
            editor.notify('Imported', '$folder/$destKey.$ext');
            setSource('mod');
            chosenKey = destKey;
            hideDialog(DialogButton.OK);
          });
      }
      catch (e)
      {
        editor.alert('Import failed', Std.string(e));
      }
    });
    #else
    editor.alert('Not available', 'Importing files needs the desktop version of the game.');
    #end
  }

  function defaultImportSubfolder():String
  {
    var t = title.toLowerCase();
    if (t.indexOf('character') != -1) return 'characters';
    if (t.indexOf('stage') != -1 || t.indexOf('background') != -1) return 'stages';
    if (t.indexOf('icon') != -1) return 'icons';
    if (t.indexOf('note') != -1) return 'notestyles';
    if (t.indexOf('menu') != -1) return 'menus';
    return '';
  }
}
#end
