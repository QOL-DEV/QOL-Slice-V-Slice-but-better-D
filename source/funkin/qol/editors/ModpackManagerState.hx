package funkin.qol.editors;

#if FEATURE_HAXEUI
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxImageFrame;
import funkin.qol.ModWorkspace.QOLModInfo;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.util.QOLFS;
import funkin.qol.util.QOLIconGen;
import funkin.qol.util.QOLJson;
import haxe.io.Bytes;
import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.Image;
import haxe.ui.components.Label;
import haxe.ui.components.TextArea;
import haxe.ui.components.TextField;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.containers.ScrollView;
import haxe.ui.containers.VBox;
import haxe.ui.data.ArrayDataSource;
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import openfl.geom.Rectangle;

/**
 * The Modpack Manager: create mods and edit everything in `_polymod_meta.json`,
 * the mod icon, the essential folders, and the load order / enabled state of every mod.
 */
class ModpackManagerState extends QOLEditorState
{
  static inline final LIST_W:Int = 300;
  static inline final ICON_W:Int = 300;

  var modList:ListView;
  var enabledBox:CheckBox;
  var folders:Array<String> = [];
  var current:Null<String> = null;
  var meta:Dynamic = null;

  var formBox:VBox;
  var titleField:TextField;
  var descField:TextArea;
  var homepageField:TextField;
  var apiField:TextField;
  var versionField:TextField;
  var licenseField:TextField;
  var depsField:TextArea;
  var optDepsField:TextArea;
  var contributorsBox:VBox;
  var contributorRows:Array<{name:TextField, role:TextField, url:TextField, box:HBox}> = [];

  var iconImage:Image;
  var folderStatus:Label;
  var headerLabel:Label;
  var activeButton:Button;
  var loading:Bool = false;

  public function new()
  {
    super();
    editorName = 'Modpack Manager';
  }

  override function guidePage():String
    return 'modpack';

  override function buildEditor():Void
  {
    gridBG.visible = false;
    camWorld.bgColor = 0xFF1B1530;

    var file = addMenu('Mod');
    addMenuItem(file, 'New Mod...', 'Ctrl+N', newMod);
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuItem(file, 'Duplicate Mod...', null, duplicateMod);
    addMenuItem(file, 'Rename Folder...', null, renameFolder);
    addMenuSeparator(file);
    addMenuItem(file, 'Delete Mod...', null, deleteMod);

    var top = QOLEditorState.MENUBAR_HEIGHT + 8;
    var height = FlxG.height - QOLEditorState.MENUBAR_HEIGHT - QOLEditorState.STATUSBAR_HEIGHT - 16;

    // Left: mod list & load order (a movable panel).
    var leftPanel = addDockPanel('mods', 'Your Mods', LIST_W, 'left');
    var left = new VBox();
    left.width = LIST_W - 28;
    left.styleString = 'spacing: 6px;';
    leftPanel.content.addComponent(left);

    var listTitle = new Label();
    listTitle.text = 'Your mods (load order)';
    listTitle.styleString = 'font-bold: true; color: #FF8FB8;';
    left.addComponent(listTitle);
    var listHint = new Label();
    listHint.width = LIST_W - 24;
    listHint.text = 'Mods lower in the list load later and override the ones above them.';
    listHint.styleString = 'color: #9AA0A6; font-size: 11px;';
    left.addComponent(listHint);

    modList = new ListView();
    modList.width = LIST_W - 22;
    modList.height = height - 220;
    modList.onChange = function(_) {
      var item = modList.selectedItem;
      if (item != null && item.folder != current) loadMod(item.folder);
    };
    left.addComponent(modList);

    var orderRow = new HBox();
    orderRow.addComponent(smallButton('Move Up', () -> moveMod(-1)));
    orderRow.addComponent(smallButton('Move Down', () -> moveMod(1)));
    left.addComponent(orderRow);

    enabledBox = new CheckBox();
    enabledBox.text = 'Enabled (loads in game)';
    enabledBox.onChange = function(_) {
      if (loading || current == null || enabledBox.selected == ModWorkspace.isEnabled(current)) return;
      ModWorkspace.setEnabled(current, enabledBox.selected);
      refreshList();
      setStatus('${current} is now ${enabledBox.selected ? 'enabled' : 'disabled'}. Reload game data to apply.');
    };
    left.addComponent(enabledBox);

    var newButton = new Button();
    newButton.text = '+ New Mod';
    newButton.percentWidth = 100;
    newButton.onClick = _ -> newMod();
    left.addComponent(newButton);

    // Center: metadata form (fills the space between the panels).
    centerScroll = new funkin.qol.ui.QOLScrollView();
    centerScroll.left = LIST_W + 16;
    centerScroll.top = top;
    centerScroll.width = FlxG.width - LIST_W - ICON_W - 32;
    naturalCenterWidth = centerScroll.width;
    centerScroll.height = height;
    centerScroll.horizontalScrollPolicy = 'never';
    centerScroll.styleString = 'background-color: #2B2340; border: 1px solid #5A4F80; border-radius: 8px; padding: 12px;';
    root.addComponent(centerScroll);

    formBox = new VBox();
    formBox.width = FlxG.width - LIST_W - ICON_W - 32 - 40;
    formBox.styleString = 'spacing: 6px;';
    centerScroll.addComponent(formBox);

    headerLabel = new Label();
    headerLabel.styleString = 'font-size: 20px; font-bold: true; color: #5CE1FF;';
    formBox.addComponent(headerLabel);

    var fw = formBox.width - 130;
    titleField = addField('Title', fw);
    descField = addArea('Description', fw, 70);
    homepageField = addField('Homepage', fw);
    homepageField.placeholder = 'https://gamebanana.com/mods/...';
    var versionRow = new HBox();
    versionField = new TextField();
    versionField.width = 120;
    apiField = new TextField();
    apiField.width = 120;
    versionRow.addComponent(labelOf('Mod version', 120));
    versionRow.addComponent(versionField);
    versionRow.addComponent(labelOf('  API version', 100));
    versionRow.addComponent(apiField);
    formBox.addComponent(versionRow);
    licenseField = addField('License', fw);

    var contribTitle = new Label();
    contribTitle.text = 'Contributors';
    contribTitle.styleString = 'font-bold: true; color: #FFD84A; padding-top: 8px;';
    formBox.addComponent(contribTitle);
    contributorsBox = new VBox();
    contributorsBox.styleString = 'spacing: 4px;';
    formBox.addComponent(contributorsBox);
    var addContributor = new Button();
    addContributor.text = '+ Add contributor';
    addContributor.onClick = _ -> {
      addContributorRow('', '', '');
      dirty = true;
    };
    formBox.addComponent(addContributor);

    var depsTitle = new Label();
    depsTitle.text = 'Dependencies (one per line: modFolder: >=1.0.0)';
    depsTitle.styleString = 'font-bold: true; color: #FFD84A; padding-top: 8px;';
    formBox.addComponent(depsTitle);
    depsField = addArea('Required', fw, 50);
    optDepsField = addArea('Optional', fw, 50);

    for (f in [titleField, homepageField, versionField, apiField, licenseField])
      f.onChange = _ -> markDirty();
    for (a in [descField, depsField, optDepsField])
      a.onChange = _ -> markDirty();

    // Right: icon & folders (a movable panel).
    var rightPanel = addDockPanel('icon', 'Icon & Folders', ICON_W, 'right');
    var right = new VBox();
    right.width = ICON_W - 28;
    right.styleString = 'spacing: 6px;';
    rightPanel.content.addComponent(right);

    var iconTitle = new Label();
    iconTitle.text = 'Mod icon (_polymod_icon.png)';
    iconTitle.styleString = 'font-bold: true; color: #FF8FB8;';
    right.addComponent(iconTitle);
    iconImage = new Image();
    iconImage.width = 160;
    iconImage.height = 160;
    iconImage.scaleMode = 'fitinside';
    iconImage.styleString = 'background-color: #1B1530; border: 1px solid #5A4F80;';
    right.addComponent(iconImage);
    var iconRow = new HBox();
    iconRow.addComponent(smallButton('Import PNG...', importIcon));
    iconRow.addComponent(smallButton('From health icon...', iconFromHealthIcon));
    right.addComponent(iconRow);
    right.addComponent(smallButton('Generate temporary icon', () -> {
      if (current == null) return;
      var bytes = QOLIconGen.generate(titleField.text ?? current);
      if (bytes != null) writeIcon(bytes);
    }));

    var foldersTitle = new Label();
    foldersTitle.text = 'Essential folders';
    foldersTitle.styleString = 'font-bold: true; color: #FF8FB8; padding-top: 8px;';
    right.addComponent(foldersTitle);
    var foldersScroll = new funkin.qol.ui.QOLScrollView();
    foldersScroll.width = ICON_W - 22;
    foldersScroll.height = height - 390;
    foldersScroll.horizontalScrollPolicy = 'never';
    folderStatus = new Label();
    folderStatus.width = ICON_W - 50;
    folderStatus.styleString = 'font-size: 12px;';
    foldersScroll.addComponent(folderStatus);
    right.addComponent(foldersScroll);
    right.addComponent(smallButton('Create missing folders', createMissingFolders));

    activeButton = new Button();
    activeButton.text = 'Make this the active mod';
    activeButton.percentWidth = 100;
    activeButton.styleString = 'font-bold: true;';
    activeButton.onClick = _ -> {
      if (current == null) return;
      ModWorkspace.current = current;
      updateModStatus();
      refreshList();
      notify('Active mod', 'Editors now save into mods/$current');
    };
    right.addComponent(activeButton);
    right.addComponent(smallButton('Open mod folder', () -> {
      if (current != null) QOLFS.openInExplorer('${ModWorkspace.MOD_ROOT}/$current');
    }));

    onLayoutChanged();
    refreshList();
    var first = ModWorkspace.current ?? (folders.length > 0 ? folders[0] : null);
    if (first != null) loadMod(first);
    else
      showEmpty();
  }

  var centerScroll:Null<funkin.qol.ui.QOLScrollView> = null;
  var naturalCenterWidth:Float = 0;

  override function onLayoutChanged():Void
  {
    if (centerScroll == null) return;
    var w = Math.max(300, workRight - workLeft - 16);
    centerScroll.left = workLeft + 8;
    centerScroll.width = w;
    var delta = w - naturalCenterWidth;
    formBox.width = naturalCenterWidth - 40 + delta;
    var fw = formBox.width - 130;
    for (f in [titleField, homepageField, licenseField])
      f.width = fw;
    for (a in [descField, depsField, optDepsField])
      a.width = fw;
  }

  function labelOf(text:String, width:Float):Label
  {
    var l = new Label();
    l.text = text;
    l.width = width;
    l.styleString = 'padding-top: 4px;';
    return l;
  }

  function addField(label:String, width:Float):TextField
  {
    var row = new HBox();
    row.addComponent(labelOf(label, 120));
    var f = new TextField();
    f.width = width;
    row.addComponent(f);
    formBox.addComponent(row);
    return f;
  }

  function addArea(label:String, width:Float, height:Float):TextArea
  {
    var row = new HBox();
    row.addComponent(labelOf(label, 120));
    var a = new TextArea();
    a.width = width;
    a.height = height;
    row.addComponent(a);
    formBox.addComponent(row);
    return a;
  }

  function smallButton(text:String, cb:Void->Void):Button
  {
    var b = new Button();
    b.text = text;
    b.onClick = _ -> cb();
    return b;
  }

  function markDirty()
  {
    if (!loading) dirty = true;
  }

  //
  // Mod list
  //

  function refreshList()
  {
    folders = ModWorkspace.orderedModFolders();
    var ds = new ArrayDataSource<Dynamic>();
    var active = ModWorkspace.current;
    for (folder in folders)
    {
      var info = ModWorkspace.readModInfo(folder);
      var marks = (folder == active ? '★ ' : '') + (ModWorkspace.isEnabled(folder) ? '' : '(off) ');
      ds.add({text: '$marks${info?.title ?? folder}', folder: folder});
    }
    loading = true;
    modList.dataSource = ds;
    if (current != null) modList.selectedIndex = folders.indexOf(current);
    loading = false;
  }

  function moveMod(dir:Int)
  {
    if (current == null) return;
    var order = folders.copy();
    var i = order.indexOf(current);
    var j = i + dir;
    if (i < 0 || j < 0 || j >= order.length) return;
    order[i] = order[j];
    order[j] = current;
    QOLConfig.modOrder = order;
    refreshList();
    setStatus('Load order changed. Reload game data (F5) to apply.');
  }

  function showEmpty()
  {
    current = null;
    headerLabel.text = 'No mods yet - click "+ New Mod" to make your first one!';
  }

  function loadMod(folder:String)
  {
    if (dirty && current != null) save();
    var info:QOLModInfo = ModWorkspace.readModInfo(folder);
    if (info == null) return;
    loading = true;
    current = folder;
    meta = QOLJson.clone(info.meta);
    headerLabel.text = 'mods/$folder';
    titleField.text = info.title;
    descField.text = info.description;
    homepageField.text = Reflect.field(meta, 'homepage') ?? '';
    versionField.text = info.modVersion;
    apiField.text = info.apiVersion;
    licenseField.text = Reflect.field(meta, 'license') ?? '';
    depsField.text = depsToText(Reflect.field(meta, 'dependencies'));
    optDepsField.text = depsToText(Reflect.field(meta, 'optionalDependencies'));

    contributorsBox.removeAllComponents();
    contributorRows = [];
    var contributors:Array<Dynamic> = Reflect.field(meta, 'contributors') ?? [];
    var author:String = Reflect.field(meta, 'author');
    if (contributors.length == 0 && author != null) contributors = [{name: author}];
    for (c in contributors)
      addContributorRow(c.name ?? '', c.role ?? '', c.url ?? '');

    enabledBox.selected = ModWorkspace.isEnabled(folder);
    loadIcon();
    refreshFolders();
    loading = false;
    dirty = false;
    var idx = folders.indexOf(folder);
    if (modList.selectedIndex != idx) modList.selectedIndex = idx;
    activeButton.text = ModWorkspace.current == folder ? 'This is the active mod ★' : 'Make this the active mod';
  }

  function addContributorRow(name:String, role:String, url:String)
  {
    var row = new HBox();
    row.styleString = 'spacing: 4px;';
    var n = new TextField();
    n.placeholder = 'Name';
    n.width = 150;
    n.text = name;
    var r = new TextField();
    r.placeholder = 'Role (Artist, Charter...)';
    r.width = 150;
    r.text = role;
    var u = new TextField();
    u.placeholder = 'Link (optional)';
    u.width = 150;
    u.text = url;
    var remove = new Button();
    remove.text = 'X';
    var entry = {
      name: n,
      role: r,
      url: u,
      box: row
    };
    remove.onClick = _ -> {
      contributorsBox.removeComponent(row);
      contributorRows.remove(entry);
      markDirty();
    };
    for (f in [n, r, u])
      f.onChange = _ -> markDirty();
    row.addComponent(n);
    row.addComponent(r);
    row.addComponent(u);
    row.addComponent(remove);
    contributorsBox.addComponent(row);
    contributorRows.push(entry);
  }

  function depsToText(deps:Dynamic):String
  {
    if (deps == null) return '';
    return [for (k in Reflect.fields(deps)) '$k: ${Reflect.field(deps, k)}'].join('\n');
  }

  function textToDeps(text:String):Null<Dynamic>
  {
    var result:Dynamic = {};
    var any = false;
    for (line in (text ?? '').split('\n'))
    {
      var parts = line.split(':');
      if (parts.length < 2) continue;
      var key = parts[0].trim();
      var value = parts.slice(1).join(':').trim();
      if (key == '') continue;
      Reflect.setField(result, key, value == '' ? '*' : value);
      any = true;
    }
    return any ? result : null;
  }

  override function save():Bool
  {
    if (current == null) return false;
    var newMeta:Dynamic = meta ?? {};
    newMeta.title = titleField.text ?? current;
    newMeta.description = descField.text ?? '';
    newMeta.homepage = homepageField.text ?? '';
    newMeta.mod_version = (versionField.text ?? '').trim() == '' ? '1.0.0' : versionField.text.trim();
    newMeta.api_version = (apiField.text ?? '').trim() == '' ? QOLSlice.GAME_VERSION : apiField.text.trim();
    if (newMeta.api_version.startsWith('v')) newMeta.api_version = newMeta.api_version.substr(1);
    newMeta.license = licenseField.text ?? '';
    newMeta.contributors = [
      for (row in contributorRows)
        if ((row.name.text ?? '').trim() != '')
        {
          var c:Dynamic = {name: row.name.text.trim()};
          if ((row.role.text ?? '').trim() != '') c.role = row.role.text.trim();
          if ((row.url.text ?? '').trim() != '') c.url = row.url.text.trim();
          c;
        }
    ];
    Reflect.deleteField(newMeta, 'author');
    var deps = textToDeps(depsField.text);
    if (deps != null) newMeta.dependencies = deps;
    else
      Reflect.deleteField(newMeta, 'dependencies');
    var opt = textToDeps(optDepsField.text);
    if (opt != null) newMeta.optionalDependencies = opt;
    else
      Reflect.deleteField(newMeta, 'optionalDependencies');

    if (!~/^[0-9]+\.[0-9]+\.[0-9]+/.match(newMeta.mod_version))
    {
      alert('Version format', 'Mod version should look like 1.0.0 (major.minor.patch).');
      return false;
    }

    meta = newMeta;
    ModWorkspace.writeMeta(current, meta);
    notifySaved('mods/$current/_polymod_meta.json');
    refreshList();
    return true;
  }

  //
  // Icon
  //

  function loadIcon()
  {
    var bytes = QOLFS.getBytes('${ModWorkspace.MOD_ROOT}/$current/_polymod_icon.png');
    var bmp:BitmapData = null;
    if (bytes != null)
    {
      try
      {
        bmp = BitmapData.fromBytes(bytes);
      }
      catch (e) {}
    }
    if (bmp == null) bmp = QOLIconGen.render(titleField.text ?? current, 160);
    if (bmp != null) iconImage.resource = FlxImageFrame.fromImage(FlxGraphic.fromBitmapData(bmp, false, null, false)).frame;
  }

  function writeIcon(bytes:Bytes)
  {
    if (current == null) return;
    QOLFS.saveBytes('${ModWorkspace.MOD_ROOT}/$current/_polymod_icon.png', bytes);
    loadIcon();
    notifySaved('mods/$current/_polymod_icon.png');
  }

  /**
   * Fit any image into a 256x256 square icon.
   */
  function squareIcon(src:BitmapData, ?srcRect:Rectangle):Null<Bytes>
  {
    var rect = srcRect ?? src.rect;
    var out = new BitmapData(256, 256, true, 0);
    var scale = Math.min(256 / rect.width, 256 / rect.height);
    var m = new Matrix();
    m.translate(-rect.x, -rect.y);
    m.scale(scale, scale);
    m.translate((256 - rect.width * scale) / 2, (256 - rect.height * scale) / 2);
    var clip = new Rectangle((256 - rect.width * scale) / 2, (256 - rect.height * scale) / 2, rect.width * scale, rect.height * scale);
    out.draw(src, m, null, null, clip, true);
    return QOLIconGen.encodePNG(out);
  }

  function importIcon()
  {
    if (current == null) return;
    #if sys
    funkin.util.FileUtil.browseForFile('Choose a PNG for the mod icon', [funkin.util.FileUtil.FILE_FILTER_PNG], function(file) {
      try
      {
        var bmp = BitmapData.fromBytes(file.bytes);
        var bytes = squareIcon(bmp);
        if (bytes != null) writeIcon(bytes);
      }
      catch (e)
      {
        alert('Import failed', Std.string(e));
      }
    });
    #else
    alert('Not available', 'Importing files needs the desktop version of the game.');
    #end
  }

  function iconFromHealthIcon()
  {
    if (current == null) return;
    browseModFile('Pick a health icon', 'images', ['png'], function(key:String) {
      try
      {
        var bmp:BitmapData = null;
        var modBytes = ModWorkspace.getBytes('images/$key.png');
        if (modBytes != null) bmp = BitmapData.fromBytes(modBytes);
        else
          bmp = FlxG.bitmap.add(Paths.image(key))?.bitmap;
        if (bmp == null) throw 'Could not load $key';
        // Health icons are two (or three) square frames side by side; use the first one.
        var rect = bmp.width >= bmp.height * 2 ? new Rectangle(0, 0, bmp.height, bmp.height) : bmp.rect;
        var bytes = squareIcon(bmp, rect);
        if (bytes != null) writeIcon(bytes);
      }
      catch (e)
      {
        alert('Icon failed', Std.string(e));
      }
    }, false);
  }

  //
  // Folders
  //

  function refreshFolders()
  {
    if (current == null) return;
    var lines:Array<String> = [];
    var missing = 0;
    for (sub in ModWorkspace.ESSENTIAL_FOLDERS)
    {
      var ok = QOLFS.isDirectory('${ModWorkspace.MOD_ROOT}/$current/$sub');
      if (!ok) missing++;
      lines.push('${ok ? '✓' : '✗'}  $sub');
    }
    folderStatus.text = (missing == 0 ? 'All folders are here!\n\n' : '$missing missing\n\n') + lines.join('\n');
  }

  function createMissingFolders()
  {
    if (current == null) return;
    for (sub in ModWorkspace.ESSENTIAL_FOLDERS)
      QOLFS.createDirectory('${ModWorkspace.MOD_ROOT}/$current/$sub');
    refreshFolders();
    notify('Folders', 'Created every essential folder in mods/$current');
  }

  //
  // Mod actions
  //

  function newMod()
  {
    prompt('New mod', 'Name of your new mod:', 'My Cool Mod', function(title:String) {
      if (title.trim() == '') return;
      var folder = ModWorkspace.createMod(title.trim());
      if (!ModWorkspace.hasMod) ModWorkspace.current = folder;
      refreshList();
      loadMod(folder);
      notify('Created', 'mods/$folder');
    });
  }

  function duplicateMod()
  {
    if (current == null) return;
    var source = current;
    prompt('Duplicate mod', 'Folder name for the copy:', '$source-copy', function(name:String) {
      var target = ModWorkspace.sanitizeFolderName(name);
      if (QOLFS.exists('${ModWorkspace.MOD_ROOT}/$target'))
      {
        alert('Already exists', 'mods/$target already exists.');
        return;
      }
      for (rel in QOLFS.listFilesRecursive('${ModWorkspace.MOD_ROOT}/$source'))
        QOLFS.copy('${ModWorkspace.MOD_ROOT}/$source/$rel', '${ModWorkspace.MOD_ROOT}/$target/$rel');
      for (sub in ModWorkspace.ESSENTIAL_FOLDERS)
        if (QOLFS.isDirectory('${ModWorkspace.MOD_ROOT}/$source/$sub')) QOLFS.createDirectory('${ModWorkspace.MOD_ROOT}/$target/$sub');
      refreshList();
      loadMod(target);
      notify('Duplicated', 'mods/$source -> mods/$target');
    });
  }

  function renameFolder()
  {
    if (current == null) return;
    var old = current;
    prompt('Rename folder', 'New folder name for mods/$old:', old, function(name:String) {
      var target = ModWorkspace.sanitizeFolderName(name);
      if (target == old) return;
      if (QOLFS.exists('${ModWorkspace.MOD_ROOT}/$target'))
      {
        alert('Already exists', 'mods/$target already exists.');
        return;
      }
      QOLFS.rename('${ModWorkspace.MOD_ROOT}/$old', '${ModWorkspace.MOD_ROOT}/$target');
      var order = QOLConfig.modOrder.map(f -> f == old ? target : f);
      QOLConfig.modOrder = order;
      if (!ModWorkspace.isEnabled(old))
      {
        ModWorkspace.setEnabled(old, true);
        ModWorkspace.setEnabled(target, false);
      }
      if (QOLConfig.activeMod == old) QOLConfig.activeMod = target;
      current = null;
      refreshList();
      loadMod(target);
      updateModStatus();
    });
  }

  function deleteMod()
  {
    if (current == null) return;
    var victim = current;
    confirm('Delete mod?', 'This permanently deletes mods/$victim and everything in it.\n\nAre you sure?', () -> {
      ModWorkspace.deleteMod(victim);
      current = null;
      dirty = false;
      refreshList();
      if (folders.length > 0) loadMod(folders[0]);
      else
        showEmpty();
      updateModStatus();
      notify('Deleted', 'mods/$victim');
    });
  }

  override function handleShortcuts():Void
  {
    if (ctrl() && FlxG.keys.justPressed.N) newMod();
  }
}
#end
