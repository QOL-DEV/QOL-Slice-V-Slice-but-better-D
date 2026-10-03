package funkin.qol.editors;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.data.song.SongRegistry;
import funkin.data.story.level.LevelRegistry;
import funkin.qol.runtime.QOLWeekOrder;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.ui.QOLTheme;
import funkin.qol.util.QOLIconGen;
import funkin.ui.story.Level;
import funkin.ui.story.LevelProp;
import haxe.ui.containers.ListView;
import haxe.ui.data.ArrayDataSource;
import openfl.utils.Assets;

/**
 * The Week Editor: story mode weeks. Their songs, the characters that dance on the banner, the title image, the
 * banner color or picture, the Freeplay capsule label, and the order of the weeks, with a live Story Mode preview.
 *
 * Saves to `mods/<mod>/data/levels/<id>.json`, and the order to `mods/<mod>/data/qol/week-order.json`.
 */
class WeekEditorState extends QOLEditorState
{
  static inline final PREVIEW_MARGIN:Int = 10;
  static inline final MENU_BPM:Float = 102;
  static inline final MAX_UNDO:Int = 100;
  static inline final BANNER_Y:Float = 56;
  static inline final BANNER_HEIGHT:Float = 400;
  static inline final SLOT_WIDTH:Float = 320;
  static final ANIM_NAMES:Array<String> = ['idle', 'confirm', 'danceLeft', 'danceRight'];

  var weekId:String = 'week1';
  var data:Dynamic;
  var order:Array<String> = [];
  var orderDirty:Bool = false;
  var selectedSong:Int = -1;
  var selectedProp:Int = -1;
  var selectedAnim:Int = -1;
  var filling:Bool = false;
  var lastBgColor:Int = 0xFFF9CF51;
  var prefixCache:Map<String, Array<String>> = new Map();

  // Undo.
  var undoStack:Array<String> = [];
  var redoStack:Array<String> = [];
  var lastSnapshot:String = '';
  var applyingUndo:Bool = false;

  // Preview.
  var camPreview:FlxCamera;
  var previewDisplay:Null<funkin.qol.ui.QOLScaledCameras> = null;
  var previewScale:Float = 0.5;
  var previewX:Float = 0;
  var previewY:Float = 0;
  var previewW:Int = 640;
  var previewH:Int = 360;
  var previewTitle:Null<FlxText> = null;
  var previewItems:Array<FlxSprite> = [];
  var propSprites:Array<Null<LevelProp>> = [];
  var titleSprite:Null<FlxSprite> = null;
  var selLines:Array<FlxSprite> = [];
  var rebuildQueued:Bool = false;
  var stepTimer:Float = 0;
  var stepCount:Int = 0;
  var confirmTimer:Float = 0;
  var flashTimer:Float = 0;
  var holdAnimTimer:Float = 0;
  var dragging:Bool = false;
  var dragStart:Array<Float> = [0, 0];
  var dragOffsets:Array<Float> = [0, 0];

  // Panels.
  var weekForm:QOLForm;
  var propForm:QOLForm;
  var animForm:QOLForm;
  var weekList:ListView;
  var songList:ListView;
  var propList:ListView;
  var animList:ListView;

  public function new(?id:String)
  {
    super();
    editorName = 'Week Editor';
    leftPanelWidth = 300;
    rightPanelWidth = 340;
    leftPanelTitle = 'Week';
    rightPanelTitle = 'Characters';
    if (id != null) weekId = id;
  }

  override function guidePage():String
    return 'week';

  override function buildEditor():Void
  {
    gridBG.visible = false;
    camWorld.bgColor = 0xFF120E1E;

    computePreviewLayout();
    camPreview = new FlxCamera(0, 0, FlxG.width, FlxG.height);
    camPreview.bgColor = FlxColor.BLACK;
    camPreview.flashSprite.scaleX = camPreview.flashSprite.scaleY = previewScale;
    previewDisplay = new funkin.qol.ui.QOLScaledCameras([camPreview], previewX, previewY, previewScale);
    FlxG.cameras.remove(camUI, false);
    FlxG.cameras.add(camPreview, false);
    FlxG.cameras.add(camUI, false);

    for (_ in 0...4)
    {
      var line = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
      line.color = 0xFF39E6FF;
      line.cameras = [camPreview];
      line.visible = false;
      selLines.push(line);
    }

    previewTitle = QOLTheme.outlinedText(previewX, previewY - 24, previewW, '', 14, QOLTheme.TEXT_DIM, 1.5);
    previewTitle.cameras = [camUI];
    add(previewTitle);

    buildMenus();
    buildWeekPanel();
    buildPropPanel();

    order = LevelRegistry.instance.listSortedLevelIds();
    var start = weekId;
    if (!order.contains(start)) start = order.length > 0 ? order[0] : null;
    if (start == null) newWeek('my-week');
    else
      openWeek(start);
  }

  //
  // Layout
  //

  function computePreviewLayout():Void
  {
    var areaW = Math.max(200, workRight - workLeft - PREVIEW_MARGIN * 2);
    var areaH = FlxG.height - QOLEditorState.MENUBAR_HEIGHT - QOLEditorState.STATUSBAR_HEIGHT - 44;
    previewScale = Math.min(areaW / FlxG.width, areaH / FlxG.height);
    previewW = Std.int(FlxG.width * previewScale);
    previewH = Std.int(FlxG.height * previewScale);
    previewX = workLeft + PREVIEW_MARGIN + (areaW - previewW) / 2;
    previewY = QOLEditorState.MENUBAR_HEIGHT + 32 + Math.max(0, (areaH - previewH) / 2);
  }

  override function onLayoutChanged():Void
  {
    if (previewDisplay == null) return;
    computePreviewLayout();
    camPreview.flashSprite.scaleX = camPreview.flashSprite.scaleY = previewScale;
    previewDisplay.x = previewX;
    previewDisplay.y = previewY;
    previewDisplay.scale = previewScale;
    previewDisplay.place();
    if (previewTitle != null)
    {
      previewTitle.x = previewX;
      previewTitle.y = previewY - 24;
      previewTitle.fieldWidth = previewW;
    }
  }

  /**
   * Mouse position in the 1280x720 preview "screen".
   */
  function previewMouse():Array<Float>
    return [(FlxG.mouse.viewX - previewX) / previewScale, (FlxG.mouse.viewY - previewY) / previewScale];

  function mouseInPreview():Bool
    return FlxG.mouse.viewX >= previewX && FlxG.mouse.viewX <= previewX + previewW && FlxG.mouse.viewY >= previewY
      && FlxG.mouse.viewY <= previewY + previewH;

  //
  // Menus and panels
  //

  function buildMenus():Void
  {
    var file = addMenu('File');
    addMenuItem(file, 'New Week...', 'Ctrl+N', newWeekDialog);
    addMenuItem(file, 'Open Week...', 'Ctrl+O', () -> chooseFromList('Open a week', order, id -> switchWeek(id), weekId));
    addMenuItem(file, 'Copy This Week...', null, copyWeek);
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuSeparator(file);
    addMenuItem(file, 'Delete This Week From My Mod', null, deleteWeek);

    var edit = addMenu('Edit');
    addMenuItem(edit, 'Undo', 'Ctrl+Z', undo);
    addMenuItem(edit, 'Redo', 'Ctrl+Y', redo);
    addMenuSeparator(edit);
    addMenuItem(edit, 'Add a Character...', null, addProp);
    addMenuItem(edit, 'Delete the Character', 'Delete', deleteProp);
    addMenuItem(edit, 'Add a Song...', null, addSong);

    var view = addMenu('Preview');
    addMenuItem(view, 'Play the "Week Picked" Animation', 'Space', playConfirm);
    addMenuItem(view, 'Restart', 'R', restartPreview);
    addMenuSeparator(view);
    addMenuItem(view, 'Open in Story Mode', null, openInStoryMode);
  }

  function makeList(height:Float, width:Float, onPick:Int->Void):ListView
  {
    var list = new ListView();
    list.width = width;
    list.height = height;
    list.onChange = _ -> {
      if (filling) return;
      if (list.selectedIndex >= 0) onPick(list.selectedIndex);
    };
    return list;
  }

  function buildWeekPanel():Void
  {
    var f = weekForm = new QOLForm(110, 150);
    f.onAnyChange = () -> {
      committed();
      queueRebuild();
    };

    f.section('Weeks');
    weekList = makeList(170, leftPanelWidth - 34, i -> {
      if (i < order.length && order[i] != weekId) switchWeek(order[i]);
    });
    f.custom(weekList);
    f.buttons([{text: 'New', cb: newWeekDialog}, {text: 'Copy', cb: copyWeek}, {text: 'Delete', cb: deleteWeek}]);
    f.buttons([{text: 'Move Up', cb: () -> moveWeek(-1)}, {text: 'Move Down', cb: () -> moveWeek(1)}]);
    f.note('This is the order of Story Mode. Save to keep it.');

    f.section('This week');
    f.textField('ID (file name)', () -> weekId, v -> renameWeek(cleanId(v)));
    f.textField('Name', () -> data?.name ?? '', v -> data.name = v);
    f.note('Shown at the top right of the Story Mode menu.');
    f.file('Title image', () -> data?.titleAsset ?? '', v -> data.titleAsset = v, cb -> browseModFile('Week title image', 'images', ['png'], cb));
    f.button('Make a title image from the name', makeTitleImage);
    f.colorField('Banner color', () -> bannerColor(), v -> {
      lastBgColor = v;
      data.background = toHex(v);
    });
    f.file('Banner image', () -> isImageBanner() ? data.background : '', v -> {
      data.background = (v == null || StringTools.trim(v) == '') ? toHex(lastBgColor) : v;
    }, cb -> browseModFile('Banner image (1280x400)', 'images', ['png'], cb));
    f.note('Behind the characters: a color, or a 1280x400 picture. Clear the picture to use the color.');
    f.check('Show in Story Mode', () -> data?.visible != false, v -> data.visible = v);

    f.section('Songs');
    songList = makeList(120, leftPanelWidth - 34, i -> selectedSong = i);
    f.custom(songList);
    f.buttons([{text: 'Add...', cb: addSong}, {text: 'Remove', cb: removeSong}]);
    f.buttons([{text: 'Move Up', cb: () -> moveSong(-1)}, {text: 'Move Down', cb: () -> moveSong(1)}]);
    f.note('Played in this order. The difficulties come from the first song.');

    f.section('Freeplay');
    f.textField('Capsule label', () -> data?.capsule?.name ?? '', v -> {
      var c = capsule();
      if (StringTools.trim(v) == '') Reflect.deleteField(c, 'name');
      else
        c.name = v;
    }, 'empty = made from the ID');
    f.pair('Label offset', () -> capsuleOffsets()[0], v -> capsuleOffsets()[0] = v, () -> capsuleOffsets()[1], v -> capsuleOffsets()[1] = v);
    f.note('The small week name on this week\'s Freeplay song capsules.');
    leftPanel.addComponent(f);
  }

  function buildPropPanel():Void
  {
    var f = propForm = new QOLForm(118, 170);
    f.onAnyChange = () -> {
      committed();
      queueRebuild();
    };
    f.section('Characters on the banner');
    f.note('They dance to the menu music. Click one in the preview to pick it, drag to move it, arrow keys to nudge (Shift = 10).');
    propList = makeList(110, rightPanelWidth - 34, i -> selectProp(i));
    f.custom(propList);
    f.buttons([{text: 'Add...', cb: addProp}, {text: 'Copy', cb: copyProp}, {text: 'Delete', cb: deleteProp}]);
    f.buttons([{text: 'Move Up', cb: () -> moveProp(-1)}, {text: 'Move Down', cb: () -> moveProp(1)}]);

    f.section('Selected character');
    f.file('Image', () -> prop()?.assetPath ?? '', v -> {
      var p = prop();
      if (p == null) return;
      p.assetPath = v;
      prefixCache.remove(v);
      if (anims().length == 0) autoDetect(false);
      refreshAnimList();
      animForm.refresh();
    }, cb -> browseModFile('Character sprite sheet', 'images', ['png'], cb));
    f.number('Scale', () -> prop()?.scale ?? 1, v -> setProp('scale', v), 0.05, 20, 0.05, 2);
    f.slider('Opacity', () -> prop()?.alpha ?? 1, v -> setProp('alpha', v), 0, 1, 0.05);
    f.check('Pixel art (x6)', () -> prop()?.isPixel == true, v -> setProp('isPixel', v));
    f.pair('Position', () -> propOffsets()[0], v -> propOffsets()[0] = v, () -> propOffsets()[1], v -> propOffsets()[1] = v);
    f.check('Flip X', () -> prop()?.flipX == true, v -> setProp('flipX', v));
    f.check('Flip Y', () -> prop()?.flipY == true, v -> setProp('flipY', v));
    f.number('Dance every', () -> prop()?.danceEvery ?? 1, v -> setProp('danceEvery', v), 0, 16, 0.25, 2);
    f.note('Beats between dances (0 = never: it plays the starting animation instead).');
    f.dropdown('Starting anim', () -> ['(dance)'].concat(animNames()), () -> {
      var s:String = prop()?.startingAnimation ?? '';
      return s == '' ? '(dance)' : s;
    }, v -> setProp('startingAnimation', v == '(dance)' ? '' : v));
    rightPanel.addComponent(f);

    var a = animForm = new QOLForm(118, 170);
    a.onAnyChange = () -> {
      committed();
      queueRebuild();
    };
    a.section('Animations');
    animList = makeList(100, rightPanelWidth - 34, i -> {
      selectedAnim = i;
      animForm.refresh();
      playSelectedAnim();
    });
    a.custom(animList);
    a.buttons([{text: 'Add', cb: addAnim}, {text: 'Delete', cb: deleteAnim}, {text: 'Auto-detect', cb: () -> autoDetect(true)}]);
    a.button('Split "idle" into danceLeft + danceRight', splitDance,
      'For characters that sway side to side (like Girlfriend): half the frames each way.');
    a.note('"idle" plays on the beat (or danceLeft and danceRight in turn). "confirm" plays when the week is picked.');
    a.section('Selected animation');
    a.dropdown('Name', () -> {
      var list = ANIM_NAMES.copy();
      var cur:String = anim()?.name;
      if (cur != null && !list.contains(cur)) list.unshift(cur);
      return list;
    }, () -> anim()?.name ?? '', v -> renameAnim(v));
    a.textField('Custom name', () -> anim()?.name ?? '', v -> {
      if (StringTools.trim(v) != '') renameAnim(StringTools.trim(v));
    });
    a.dropdown('Prefix', () -> {
      var names = prefixesOf(prop()?.assetPath);
      var cur:String = anim()?.prefix ?? '';
      return cur == '' || names.contains(cur) ? names : [cur].concat(names);
    }, () -> anim()?.prefix ?? '', v -> setAnim('prefix', v));
    a.textField('Custom prefix', () -> anim()?.prefix ?? '', v -> setAnim('prefix', v));
    a.textField('Frame indices', () -> indicesToText(anim()?.frameIndices), v -> {
      var list = textToIndices(v);
      setAnim('frameIndices', list.length == 0 ? null : list);
    }, 'e.g. 0-14, 30 (empty = all)');
    a.number('Frame rate', () -> anim()?.frameRate ?? 24, v -> setAnim('frameRate', Std.int(v)), 1, 120, 1, 0);
    a.check('Loop', () -> anim()?.looped == true, v -> setAnim('looped', v));
    a.pair('Offsets', () -> animOffsets()[0], v -> animOffsets()[0] = v, () -> animOffsets()[1], v -> animOffsets()[1] = v);
    a.button('Play', playSelectedAnim);
    rightPanel.addComponent(a);
  }

  //
  // Data helpers
  //

  static function cleanId(v:String):String
  {
    var s = StringTools.trim(v);
    s = ~/[^A-Za-z0-9_\-]+/g.replace(s, '-');
    return s == '' ? 'my-week' : s;
  }

  static function toHex(c:Int):String
    return '#' + StringTools.hex(c & 0xFFFFFF, 6);

  function isImageBanner():Bool
  {
    var bg:String = data?.background;
    return bg != null && bg != '' && !StringTools.startsWith(bg, '#');
  }

  function bannerColor():Int
  {
    var bg:String = data?.background;
    if (bg != null && StringTools.startsWith(bg, '#'))
    {
      var c:Null<FlxColor> = FlxColor.fromString(bg);
      if (c != null) lastBgColor = c;
    }
    return lastBgColor;
  }

  function capsule():Dynamic
  {
    if (data.capsule == null) data.capsule = {};
    return data.capsule;
  }

  function capsuleOffsets():Array<Float>
  {
    if (data == null) return [0, 0];
    var c = capsule();
    var o:Array<Float> = c.offsets;
    if (o == null || o.length < 2)
    {
      o = [0, 0];
      c.offsets = o;
    }
    return o;
  }

  function songs():Array<String>
  {
    if (data.songs == null) data.songs = [];
    return data.songs;
  }

  function props():Array<Dynamic>
  {
    if (data == null) return [];
    if (data.props == null) data.props = [];
    return data.props;
  }

  function prop():Null<Dynamic>
  {
    var list = props();
    return selectedProp >= 0 && selectedProp < list.length ? list[selectedProp] : null;
  }

  function setProp(field:String, value:Dynamic):Void
  {
    var p = prop();
    if (p != null) Reflect.setField(p, field, value);
  }

  function propOffsets():Array<Float>
  {
    var p = prop();
    if (p == null) return [0, 0];
    var o:Array<Float> = p.offsets;
    if (o == null || o.length < 2)
    {
      o = [0, 0];
      p.offsets = o;
    }
    return o;
  }

  function anims():Array<Dynamic>
  {
    var p = prop();
    if (p == null) return [];
    if (p.animations == null) p.animations = [];
    return p.animations;
  }

  function animNames():Array<String>
    return [for (a in anims()) a.name];

  function anim():Null<Dynamic>
  {
    var list = anims();
    return selectedAnim >= 0 && selectedAnim < list.length ? list[selectedAnim] : null;
  }

  function setAnim(field:String, value:Dynamic):Void
  {
    var a = anim();
    if (a == null) return;
    if (value == null) Reflect.deleteField(a, field);
    else
      Reflect.setField(a, field, value);
    refreshAnimList();
  }

  function animOffsets():Array<Float>
  {
    var a = anim();
    if (a == null) return [0, 0];
    var o:Array<Float> = a.offsets;
    if (o == null || o.length < 2)
    {
      o = [0, 0];
      a.offsets = o;
    }
    return o;
  }

  function renameAnim(name:String):Void
  {
    var a = anim();
    if (a == null || name == '' || a.name == name) return;
    var p = prop();
    if (p != null && p.startingAnimation == a.name) p.startingAnimation = name;
    a.name = name;
    refreshAnimList();
  }

  /**
   * Animation names in a sprite sheet (for the prefix lists).
   */
  function prefixesOf(assetPath:Null<String>):Array<String>
  {
    if (assetPath == null || assetPath == '') return [];
    if (prefixCache.exists(assetPath)) return prefixCache.get(assetPath);
    var out:Array<String> = [];
    try
    {
      if (Assets.exists(Paths.file('images/$assetPath.xml')))
      {
        var frames = Paths.getSparrowAtlas(assetPath);
        if (frames != null)
        {
          var seen = new Map<String, Bool>();
          var digits = ~/[0-9]+$/;
          for (f in frames.frames)
          {
            if (f == null || f.name == null) continue;
            var p = digits.replace(f.name, '');
            if (!seen.exists(p))
            {
              seen.set(p, true);
              out.push(p);
            }
          }
          out.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
        }
      }
    }
    catch (e:Dynamic) {}
    prefixCache.set(assetPath, out);
    return out;
  }

  function frameCount(assetPath:String, prefix:String):Int
  {
    try
    {
      var frames = Paths.getSparrowAtlas(assetPath);
      if (frames == null) return 0;
      var n = 0;
      for (f in frames.frames)
        if (f != null && f.name != null && StringTools.startsWith(f.name, prefix)) n++;
      return n;
    }
    catch (e:Dynamic)
    {
      return 0;
    }
  }

  static function indicesToText(indices:Array<Int>):String
  {
    if (indices == null || indices.length == 0) return '';
    var parts:Array<String> = [];
    var i = 0;
    while (i < indices.length)
    {
      var start = indices[i];
      var end = start;
      while (i + 1 < indices.length && indices[i + 1] == end + 1)
      {
        end++;
        i++;
      }
      parts.push(end > start + 1 ? '$start-$end' : (end == start ? '$start' : '$start, $end'));
      i++;
    }
    return parts.join(', ');
  }

  static function textToIndices(text:String):Array<Int>
  {
    var result:Array<Int> = [];
    for (part in text.split(','))
    {
      part = StringTools.trim(part);
      if (part == '') continue;
      var dash = part.indexOf('-', 1);
      if (dash > 0)
      {
        var a = Std.parseInt(StringTools.trim(part.substr(0, dash)));
        var b = Std.parseInt(StringTools.trim(part.substr(dash + 1)));
        if (a == null || b == null) continue;
        if (a <= b) for (n in a...b + 1)
          result.push(n);
        else
        {
          var n = a;
          while (n >= b)
            result.push(n--);
        }
      }
      else
      {
        var n = Std.parseInt(part);
        if (n != null) result.push(n);
      }
    }
    return result;
  }

  static function shortName(path:String):String
  {
    if (path == null || path == '') return '(no image)';
    var slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substr(slash + 1) : path;
  }

  //
  // Lists
  //

  function fillList(list:ListView, items:Array<String>, selected:Int):Void
  {
    filling = true;
    var ds = new ArrayDataSource<Dynamic>();
    for (item in items)
      ds.add({text: item});
    list.dataSource = ds;
    list.selectedIndex = selected >= 0 && selected < items.length ? selected : -1;
    filling = false;
  }

  function refreshWeekList():Void
  {
    var items = [];
    for (id in order)
    {
      var label = id;
      if (id == weekId)
      {
        if (data?.name != null && data.name != '') label += '   ·   ${data.name}';
        if (data?.visible == false) label += '   (hidden)';
      }
      else
      {
        var level = LevelRegistry.instance.fetchEntry(id);
        if (level != null)
        {
          var name = level.getTitle();
          if (name != null && name != '') label += '   ·   $name';
          if (!level.isVisible()) label += '   (hidden)';
        }
        else
          label += '   (not saved)';
      }
      items.push(label);
    }
    fillList(weekList, items, order.indexOf(weekId));
  }

  function refreshSongList():Void
  {
    var items = [];
    for (id in songs())
    {
      var song = SongRegistry.instance.fetchEntry(id, {variation: Constants.DEFAULT_VARIATION});
      items.push(song == null ? '$id   (not found!)' : '$id   ·   ${song.songName}');
    }
    if (selectedSong >= items.length) selectedSong = items.length - 1;
    fillList(songList, items, selectedSong);
  }

  function refreshPropList():Void
  {
    var list = props();
    var items = [];
    for (i in 0...list.length)
      items.push('${i + 1}. ${shortName(list[i].assetPath)}');
    if (selectedProp >= list.length) selectedProp = list.length - 1;
    fillList(propList, items, selectedProp);
    propForm.refresh();
    refreshAnimList();
  }

  function refreshAnimList():Void
  {
    var list = anims();
    var items = [];
    for (a in list)
    {
      var extra = a.frameIndices != null && a.frameIndices.length > 0 ? '  [${a.frameIndices.length} frames]' : '';
      items.push('${a.name}   ·   ${a.prefix ?? '?'}$extra');
    }
    if (selectedAnim >= list.length) selectedAnim = list.length - 1;
    if (selectedAnim < 0 && list.length > 0) selectedAnim = 0;
    fillList(animList, items, selectedAnim);
    animForm.hidden = prop() == null;
  }

  function refreshAll():Void
  {
    refreshWeekList();
    refreshSongList();
    weekForm.refresh();
    refreshPropList();
    animForm.refresh();
  }

  //
  // Weeks
  //

  function rawData(id:String):Dynamic
  {
    var rel = 'data/levels/$id.json';
    if (ModWorkspace.hasMod && ModWorkspace.exists(rel))
    {
      var d = ModWorkspace.getJson(rel);
      if (d != null) return d;
    }
    try
    {
      var text = Assets.getText(Paths.json('levels/$id'));
      if (text != null) return funkin.qol.util.QOLJson.parse(text);
    }
    catch (e:Dynamic) {}
    return null;
  }

  /**
   * Open another week, offering to save this one first.
   */
  function switchWeek(id:String):Void
  {
    if (id == weekId) return;
    if (dirty)
    {
      confirm('Unsaved changes', 'Save "$weekId" before opening "$id"?', () -> {
        doSave();
        openWeek(id);
      }, () -> openWeek(id));
      refreshWeekList();
    }
    else
      openWeek(id);
  }

  function openWeek(id:String):Void
  {
    var d = rawData(id);
    if (d == null)
    {
      alert('Could not open', 'The week "$id" could not be read.');
      refreshWeekList();
      return;
    }
    weekId = id;
    data = d;
    if (!order.contains(id)) order.push(id);
    afterLoad();
  }

  function defaultData():Dynamic
  {
    return {
      version: LevelRegistry.LEVEL_DATA_VERSION.toString(),
      name: 'MY WEEK',
      titleAsset: '',
      props: [],
      background: '#F9CF51',
      songs: []
    };
  }

  function newWeekDialog():Void
  {
    prompt('New week', 'ID (file name)', uniqueId('my-week'), v -> newWeek(cleanId(v)));
  }

  /**
   * A new week: Boyfriend and Girlfriend on a yellow banner, no songs yet.
   */
  function newWeek(id:String):Void
  {
    if (order.contains(id)) id = uniqueId(id);
    var d:Dynamic = defaultData();
    var template = rawData('week1');
    if (template != null && Std.isOfType(template.props, Array))
    {
      var list:Array<Dynamic> = haxe.Json.parse(haxe.Json.stringify(template.props));
      // An empty left slot for the opponent, then Boyfriend and Girlfriend.
      if (list.length >= 3) d.props = [list[1], list[2]];
      for (p in (d.props : Array<Dynamic>))
        if (p.offsets != null) p.offsets[0] += SLOT_WIDTH;
    }
    var first = order.indexOf(weekId);
    weekId = id;
    data = d;
    order.insert(first < 0 ? order.length : first + 1, id);
    orderDirty = true;
    afterLoad();
    dirty = true;
  }

  function copyWeek():Void
  {
    if (data == null) return;
    var copy:Dynamic = haxe.Json.parse(haxe.Json.stringify(data));
    var id = uniqueId(weekId + '-copy');
    var at = order.indexOf(weekId);
    weekId = id;
    data = copy;
    order.insert(at < 0 ? order.length : at + 1, id);
    orderDirty = true;
    afterLoad();
    dirty = true;
    notify('Copied', 'Now editing "$id". Save to keep it.');
  }

  function uniqueId(base:String):String
  {
    var id = base;
    var n = 2;
    while (order.contains(id) || LevelRegistry.instance.listEntryIds().contains(id))
      id = '$base-${n++}';
    return id;
  }

  function renameWeek(id:String):Void
  {
    if (id == weekId) return;
    if (order.contains(id) || LevelRegistry.instance.listEntryIds().contains(id))
    {
      setStatus('There\'s already a week called "$id".');
      return;
    }
    var at = order.indexOf(weekId);
    // A saved week keeps its file, so the renamed one is a new week next to it. An unsaved one just gets the new name.
    if (LevelRegistry.instance.listEntryIds().contains(weekId)) order.insert(at + 1, id);
    else if (at >= 0) order[at] = id;
    else
      order.push(id);
    weekId = id;
    orderDirty = true;
    refreshWeekList();
    setStatus('Saving makes data/levels/$id.json.');
  }

  function deleteWeek():Void
  {
    var rel = 'data/levels/$weekId.json';
    if (!ModWorkspace.hasMod || !ModWorkspace.exists(rel))
    {
      if (!LevelRegistry.instance.listEntryIds().contains(weekId))
      {
        // Never saved: just drop it.
        var at = order.indexOf(weekId);
        order.remove(weekId);
        dirty = false;
        openWeek(order[Std.int(Math.max(0, Math.min(at, order.length - 1)))]);
        return;
      }
      alert('Can\'t delete', 'This week comes with the game (or another mod), so it can\'t be deleted. Untick "Show in Story Mode" to hide it instead.');
      return;
    }
    confirm('Delete', 'Delete $rel from your mod?', () -> {
      var at = order.indexOf(weekId);
      clearPreview();
      ModWorkspace.delete(rel);
      ModWorkspace.reloadGameData();
      notify('Deleted', rel);
      var ids = LevelRegistry.instance.listEntryIds();
      if (!ids.contains(weekId)) order.remove(weekId);
      if (orderDirty) saveOrder();
      dirty = false;
      if (order.length == 0) newWeek('my-week');
      else
        openWeek(order.contains(weekId) ? weekId : order[Std.int(Math.max(0, Math.min(at, order.length - 1)))]);
    });
  }

  function moveWeek(dir:Int):Void
  {
    var at = order.indexOf(weekId);
    var to = at + dir;
    if (at < 0 || to < 0 || to >= order.length) return;
    order[at] = order[to];
    order[to] = weekId;
    orderDirty = true;
    dirty = true;
    refreshWeekList();
  }

  function afterLoad():Void
  {
    prefixCache = new Map();
    selectedProp = props().length > 0 ? 0 : -1;
    selectedAnim = 0;
    selectedSong = -1;
    var bg:String = data.background;
    if (bg != null && StringTools.startsWith(bg, '#'))
    {
      var c:Null<FlxColor> = FlxColor.fromString(bg);
      if (c != null) lastBgColor = c;
    }
    undoStack = [];
    redoStack = [];
    lastSnapshot = snapshot();
    refreshAll();
    queueRebuild();
    dirty = false;
  }

  //
  // Songs
  //

  function addSong():Void
  {
    var ids = SongRegistry.instance.listEntryIds();
    ids.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
    chooseFromList('Add a song', ids, id -> {
      changing();
      var at = selectedSong >= 0 ? selectedSong + 1 : songs().length;
      songs().insert(at, id);
      selectedSong = at;
      refreshSongList();
      committed();
      queueRebuild();
    });
  }

  function removeSong():Void
  {
    if (selectedSong < 0 || selectedSong >= songs().length) return;
    changing();
    songs().splice(selectedSong, 1);
    refreshSongList();
    committed();
    queueRebuild();
  }

  function moveSong(dir:Int):Void
  {
    var list = songs();
    var to = selectedSong + dir;
    if (selectedSong < 0 || to < 0 || to >= list.length) return;
    changing();
    var s = list[selectedSong];
    list[selectedSong] = list[to];
    list[to] = s;
    selectedSong = to;
    refreshSongList();
    committed();
    queueRebuild();
  }

  //
  // Characters (props)
  //

  function selectProp(i:Int):Void
  {
    selectedProp = i;
    selectedAnim = 0;
    if (propList.selectedIndex != i)
    {
      filling = true;
      propList.selectedIndex = i;
      filling = false;
    }
    propForm.refresh();
    refreshAnimList();
    animForm.refresh();
  }

  function addProp():Void
  {
    browseModFile('Character sprite sheet', 'images', ['png'], key -> {
      changing();
      var list = props();
      var p:Dynamic = {
        assetPath: key,
        scale: 1.0,
        offsets: [100.0, 80.0],
        animations: []
      };
      list.push(p);
      selectedProp = list.length - 1;
      selectedAnim = 0;
      autoDetect(false);
      refreshPropList();
      committed();
      queueRebuild();
    });
  }

  function copyProp():Void
  {
    var p = prop();
    if (p == null) return;
    changing();
    props().insert(selectedProp + 1, haxe.Json.parse(haxe.Json.stringify(p)));
    selectedProp++;
    refreshPropList();
    committed();
    queueRebuild();
  }

  function deleteProp():Void
  {
    if (prop() == null) return;
    changing();
    props().splice(selectedProp, 1);
    if (selectedProp >= props().length) selectedProp = props().length - 1;
    refreshPropList();
    committed();
    queueRebuild();
  }

  /**
   * Moving a character to another slot keeps it where it is on screen.
   */
  function moveProp(dir:Int):Void
  {
    var list = props();
    var to = selectedProp + dir;
    if (selectedProp < 0 || to < 0 || to >= list.length) return;
    changing();
    var a = list[selectedProp];
    var b = list[to];
    list[selectedProp] = b;
    list[to] = a;
    for (pair in [{p: a, from: selectedProp, to: to}, {p: b, from: to, to: selectedProp}])
    {
      var o:Array<Float> = pair.p.offsets ?? [0.0, 0.0];
      o[0] += (pair.from - pair.to) * SLOT_WIDTH;
      pair.p.offsets = o;
    }
    selectedProp = to;
    refreshPropList();
    committed();
    queueRebuild();
  }

  function addAnim():Void
  {
    if (prop() == null) return;
    changing();
    var have = animNames();
    var name = 'idle';
    for (n in ANIM_NAMES)
      if (!have.contains(n))
      {
        name = n;
        break;
      }
    var names = prefixesOf(prop().assetPath);
    anims().push({name: name, prefix: names.length > 0 ? names[0] : '', frameRate: 24});
    selectedAnim = anims().length - 1;
    refreshAnimList();
    animForm.refresh();
    committed();
    queueRebuild();
  }

  function deleteAnim():Void
  {
    if (anim() == null) return;
    changing();
    anims().splice(selectedAnim, 1);
    refreshAnimList();
    animForm.refresh();
    committed();
    queueRebuild();
  }

  /**
   * Guess the animations from the sprite sheet's names ("idle", "confirm"...).
   */
  function autoDetect(tell:Bool):Void
  {
    var p = prop();
    if (p == null) return;
    var names = prefixesOf(p.assetPath);
    if (names.length == 0)
    {
      if (tell) alert('Nothing to detect', 'This picture has no sprite sheet (.xml) next to it, so it doesn\'t animate.');
      return;
    }
    if (tell) changing();
    var added = 0;
    for (prefix in names)
    {
      var low = prefix.toLowerCase();
      var name = low.indexOf('confirm') != -1 || low.indexOf('hey') != -1 ? 'confirm' : (low.indexOf('idle') != -1
        || low.indexOf('dance') != -1 ? 'idle' : StringTools.trim(prefix));
      if (name == '' || animNames().contains(name)) continue;
      anims().push({name: name, prefix: prefix, frameRate: 24});
      added++;
    }
    // A single animation of any name is the dance.
    if (anims().length == 1 && anims()[0].name != 'idle' && anims()[0].name != 'confirm') anims()[0].name = 'idle';
    if (tell)
    {
      refreshAnimList();
      animForm.refresh();
      committed();
      queueRebuild();
      notify('Auto-detect', added == 0 ? 'No new animations found.' : 'Added $added animation(s).');
    }
  }

  /**
   * Turn "idle" into danceLeft (first half of the frames) and danceRight (second half).
   */
  function splitDance():Void
  {
    var p = prop();
    if (p == null) return;
    var idle:Dynamic = null;
    for (a in anims())
      if (a.name == 'idle') idle = a;
    if (idle == null)
    {
      alert('No idle', 'Add an "idle" animation first.');
      return;
    }
    var n = frameCount(p.assetPath, idle.prefix);
    if (n < 2)
    {
      alert('Too short', 'The idle animation needs at least 2 frames to split.');
      return;
    }
    changing();
    var half = Std.int(n / 2);
    var list = anims();
    var at = list.indexOf(idle);
    list.splice(at, 1);
    list.insert(at, {name: 'danceRight', prefix: idle.prefix, frameIndices: [for (i in half...n) i], frameRate: idle.frameRate ?? 24});
    list.insert(at, {name: 'danceLeft', prefix: idle.prefix, frameIndices: [for (i in 0...half) i], frameRate: idle.frameRate ?? 24});
    if (p.startingAnimation == 'idle') p.startingAnimation = '';
    selectedAnim = at;
    refreshAnimList();
    animForm.refresh();
    committed();
    queueRebuild();
  }

  function playSelectedAnim():Void
  {
    var a = anim();
    if (a == null || selectedProp < 0 || selectedProp >= propSprites.length) return;
    var spr = propSprites[selectedProp];
    if (spr == null || !spr.hasAnimation(a.name)) return;
    spr.animation.paused = false;
    spr.playAnimation(a.name, true, true);
    holdAnimTimer = 1.5;
  }

  //
  // Title image
  //

  /**
   * Draw the week's name as a title picture and save it into the mod (`images/storymenu/titles/<id>.png`).
   */
  function makeTitleImage():Void
  {
    if (!ModWorkspace.hasMod)
    {
      alert('No mod selected', 'Choose or create a mod in the Mod Menu first.');
      return;
    }
    var text:String = StringTools.trim(data?.name ?? '');
    if (text == '') text = weekId.toUpperCase();
    var t = new FlxText(0, 0, 0, text, 64);
    t.setFormat(Paths.font('vcr.ttf'), 64, FlxColor.WHITE, CENTER, SHADOW, 0xFF3A3A3A);
    t.borderSize = 4;
    @:privateAccess t.regenGraphic();
    var bytes = QOLIconGen.encodePNG(t.pixels);
    t.destroy();
    if (bytes == null)
    {
      alert('Could not make it', 'The title picture could not be drawn.');
      return;
    }
    var key = 'storymenu/titles/$weekId';
    ModWorkspace.saveBytes('images/$key.png', bytes);
    changing();
    data.titleAsset = key;
    clearPreview();
    forgetImage(key);
    ModWorkspace.reloadGameData();
    weekForm.refresh();
    committed();
    queueRebuild();
    notify('Title made', 'images/$key.png');
  }

  /**
   * Drop a picture from the caches, so a new file with the same name is loaded fresh.
   */
  static function forgetImage(key:String):Void
  {
    try
    {
      var path = Paths.image(key);
      FlxG.bitmap.removeByKey(path);
      Assets.cache.removeBitmapData(path);
    }
    catch (e:Dynamic) {}
  }

  //
  // Undo / redo
  //

  function snapshot():String
    return haxe.Json.stringify({id: weekId, data: data});

  /**
   * Call before a change that isn't made through a form (forms record automatically).
   */
  function changing():Void
  {
    if (snapshot() != lastSnapshot) committed();
  }

  function committed():Void
  {
    if (applyingUndo || data == null) return;
    var now = snapshot();
    if (now == lastSnapshot) return;
    undoStack.push(lastSnapshot);
    if (undoStack.length > MAX_UNDO) undoStack.shift();
    redoStack = [];
    lastSnapshot = now;
    dirty = true;
    refreshWeekList();
  }

  function undo():Void
  {
    if (undoStack.length == 0) return;
    redoStack.push(snapshot());
    restore(undoStack.pop());
  }

  function redo():Void
  {
    if (redoStack.length == 0) return;
    undoStack.push(snapshot());
    restore(redoStack.pop());
  }

  function restore(snap:String):Void
  {
    applyingUndo = true;
    var s:Dynamic = haxe.Json.parse(snap);
    if (s.id != weekId)
    {
      var at = order.indexOf(weekId);
      if (at >= 0 && !LevelRegistry.instance.listEntryIds().contains(weekId)) order[at] = s.id;
      else if (!order.contains(s.id)) order.insert(at + 1, s.id);
      weekId = s.id;
    }
    data = s.data;
    lastSnapshot = snap;
    refreshAll();
    queueRebuild();
    applyingUndo = false;
    dirty = true;
  }

  //
  // Saving
  //

  /**
   * The data as it's saved: no empty capsule, numbers where the game wants numbers.
   */
  function cleanData():Dynamic
  {
    var out:Dynamic = haxe.Json.parse(haxe.Json.stringify(data));
    out.version = LevelRegistry.LEVEL_DATA_VERSION.toString();
    var c:Dynamic = out.capsule;
    if (c != null)
    {
      var o:Array<Float> = c.offsets;
      if (o != null && o.length >= 2 && o[0] == 0 && o[1] == 0) Reflect.deleteField(c, 'offsets');
      if (c.name == null || c.name == '') Reflect.deleteField(c, 'name');
      if (Reflect.fields(c).length == 0) Reflect.deleteField(out, 'capsule');
    }
    if (out.visible == true) Reflect.deleteField(out, 'visible');
    for (p in (out.props ?? [] : Array<Dynamic>))
    {
      if (p.startingAnimation == '') Reflect.deleteField(p, 'startingAnimation');
      if (p.flipX == false) Reflect.deleteField(p, 'flipX');
      if (p.flipY == false) Reflect.deleteField(p, 'flipY');
      if (p.isPixel == false) Reflect.deleteField(p, 'isPixel');
      for (a in (p.animations ?? [] : Array<Dynamic>))
      {
        var o:Array<Float> = a.offsets;
        if (o != null && o.length >= 2 && o[0] == 0 && o[1] == 0) Reflect.deleteField(a, 'offsets');
        if (a.looped == false) Reflect.deleteField(a, 'looped');
      }
    }
    return out;
  }

  override function save():Bool
  {
    if (data.titleAsset == null || StringTools.trim(data.titleAsset) == '')
    {
      alert('No title image', 'A week needs a title image (the game skips weeks without one). Pick one, or use "Make a title image from the name".');
      return false;
    }
    if (songs().length == 0)
    {
      alert('No songs', 'Add at least one song to this week first.');
      return false;
    }
    var keyOrder = [
      'version', 'name', 'capsule', 'titleAsset', 'background', 'visible', 'songs', 'props', 'assetPath', 'scale', 'alpha', 'isPixel', 'danceEvery',
      'offsets', 'flipX', 'flipY', 'startingAnimation', 'animations', 'prefix', 'frameIndices', 'frameRate', 'looped'
    ];
    var path = ModWorkspace.saveJson('data/levels/$weekId.json', cleanData(), keyOrder);
    if (orderDirty) saveOrder();
    notifySaved(path);
    return true;
  }

  function saveOrder():Void
  {
    ModWorkspace.saveJson('data/${QOLWeekOrder.PATH}.json', {order: order});
    orderDirty = false;
  }

  override function afterSaveReload():Void
  {
    clearPreview();
    ModWorkspace.reloadGameData();
    prefixCache = new Map();
    refreshAll();
    queueRebuild();
  }

  function openInStoryMode():Void
  {
    var go = () -> {
      @:privateAccess funkin.ui.story.StoryMenuState.rememberedLevelId = weekId;
      funkin.util.WindowUtil.setWindowTitle(QOLSlice.WINDOW_TITLE);
      FlxG.switchState(() -> new funkin.ui.story.StoryMenuState());
    };
    if (dirty || !LevelRegistry.instance.listEntryIds().contains(weekId))
    {
      confirm('Save first?', 'Save "$weekId" and open Story Mode?', () -> {
        doSave();
        if (!dirty) go();
      });
    }
    else
      go();
  }

  //
  // Preview
  //

  function queueRebuild():Void
    rebuildQueued = true;

  /**
   * The week being edited as a real level (read the same way the game reads it).
   */
  function buildLevel():Null<Level>
  {
    try
    {
      var d:Dynamic = cleanData();
      if (d.titleAsset == null || d.titleAsset == '') d.titleAsset = '__none__';
      if (d.songs == null || d.songs.length == 0) d.songs = ['__none__'];
      var parsed = LevelRegistry.instance.parseEntryDataRaw(haxe.Json.stringify(d), '$weekId.json');
      if (parsed == null) return null;
      var level:Level = Type.createEmptyInstance(Level);
      Reflect.setField(level, 'id', weekId);
      Reflect.setField(level, '_data', parsed);
      return level;
    }
    catch (e:Dynamic)
    {
      setStatus('Preview: $e');
      return null;
    }
  }

  function addItem<T:FlxSprite>(s:T):T
  {
    s.cameras = [camPreview];
    add(s);
    previewItems.push(s);
    return s;
  }

  static function imageExists(key:Null<String>):Bool
  {
    if (key == null || key == '') return false;
    try
    {
      return Assets.exists(Paths.image(key));
    }
    catch (e:Dynamic)
    {
      return false;
    }
  }

  function rebuildPreview():Void
  {
    rebuildQueued = false;
    clearPreview();
    var level = buildLevel();
    if (level == null) return;
    var d:Dynamic = cleanData();

    // The banner.
    addItem(new FlxSprite(0, 0).makeGraphic(FlxG.width, Std.int(BANNER_Y + BANNER_HEIGHT), FlxColor.BLACK));
    var banner:FlxSprite;
    if (isImageBanner() && imageExists(data.background)) banner = new FlxSprite().loadGraphic(Paths.image(data.background));
    else
    {
      banner = new FlxSprite().makeGraphic(FlxG.width, Std.int(BANNER_HEIGHT), FlxColor.WHITE);
      banner.color = bannerColor();
      if (isImageBanner()) setStatus('Banner image not found: ${data.background}');
    }
    banner.setPosition(0, BANNER_Y);
    addItem(banner);

    // The characters.
    var list:Array<Dynamic> = @:privateAccess level._data.props;
    propSprites = [];
    for (i in 0...list.length)
    {
      var spr:Null<LevelProp> = null;
      try
      {
        if (imageExists(list[i].assetPath))
        {
          spr = LevelProp.build(list[i]);
          if (spr != null && (spr.frames == null || spr.frames.numFrames == 0))
          {
            spr.destroy();
            spr = null;
          }
        }
      }
      catch (e:Dynamic)
      {
        setStatus('Character ${i + 1}: $e');
        spr = null;
      }
      if (spr != null)
      {
        spr.x = list[i].offsets[0] + SLOT_WIDTH * i;
        spr.y = list[i].offsets[1];
        addItem(spr);
      }
      propSprites.push(spr);
    }

    // The title, with the next weeks below it.
    var at = order.indexOf(weekId);
    var y = 480.0;
    titleSprite = null;
    for (n in 0...3)
    {
      var title:Null<FlxSprite> = null;
      if (n == 0)
      {
        if (imageExists(d.titleAsset)) title = level.buildTitleGraphic();
        else
        {
          var t = new FlxText(0, 0, 0, '(no title image)', 32);
          t.setFormat('VCR OSD Mono', 32, 0xFF8A8AA0);
          title = t;
        }
        titleSprite = title;
      }
      else
      {
        var id = at >= 0 && at + n < order.length ? order[at + n] : null;
        var other = id == null ? null : LevelRegistry.instance.fetchEntry(id);
        if (other == null) break;
        var key:String = @:privateAccess other._data.titleAsset;
        if (!imageExists(key)) continue;
        title = other.buildTitleGraphic();
        title.alpha = 0.6;
      }
      title.screenCenter(X);
      title.y = y;
      addItem(title);
      y += Math.max(title.height + 20, 125);
    }

    // Track list.
    var tracks = new FlxText(0, 500, 0, 'TRACKS\n\n' + [for (id in songs()) songName(id)].join('\n'), 32);
    tracks.setFormat('VCR OSD Mono', 32);
    tracks.alignment = CENTER;
    tracks.color = 0xFFE55777;
    tracks.screenCenter(X);
    tracks.x -= FlxG.width * 0.33;
    addItem(tracks);

    // Difficulty.
    try
    {
      var left = new FlxSprite(FlxG.width - 410, 480);
      left.frames = Paths.getSparrowAtlas('storymenu/ui/arrows');
      left.animation.addByPrefix('idle', 'leftIdle0');
      left.animation.play('idle');
      addItem(left);
      var diff = new FlxSprite(left.x + left.width + 10, left.y + 10).loadGraphic(Paths.image('storymenu/difficulties/normal'));
      addItem(diff);
      var right = new FlxSprite(FlxG.width - 35, left.y);
      right.frames = left.frames;
      right.animation.addByPrefix('idle', 'rightIdle0');
      right.animation.play('idle');
      addItem(right);
    }
    catch (e:Dynamic) {}

    // Top bar (drawn over the titles that scroll up, like the game).
    addItem(new FlxSprite(0, 0).makeGraphic(FlxG.width, Std.int(BANNER_Y), FlxColor.BLACK));
    var score = new FlxText(10, 10, 0, 'LEVEL SCORE: 0');
    score.setFormat('VCR OSD Mono', 32);
    addItem(score);
    var name = new FlxText(0, 10, 0, d.name ?? '');
    name.setFormat('VCR OSD Mono', 32, FlxColor.WHITE, RIGHT);
    name.alpha = 0.7;
    name.x = FlxG.width - name.width - 10;
    addItem(name);

    for (line in selLines)
    {
      remove(line, true);
      add(line);
    }
    restartPreview();
    if (previewTitle != null) previewTitle.text = 'Story Mode preview  ·  ${weekId}  ·  drag the characters';
  }

  function songName(id:String):String
  {
    if (id == '__none__') return '';
    var song = SongRegistry.instance.fetchEntry(id, {variation: Constants.DEFAULT_VARIATION});
    return song == null ? 'Unknown' : song.songName;
  }

  function clearPreview():Void
  {
    for (s in previewItems)
    {
      remove(s, true);
      s.destroy();
    }
    previewItems = [];
    propSprites = [];
    titleSprite = null;
  }

  function restartPreview():Void
  {
    stepTimer = 0;
    stepCount = 0;
    confirmTimer = 0;
    holdAnimTimer = 0;
    if (titleSprite != null) titleSprite.color = FlxColor.WHITE;
    for (spr in propSprites)
      if (spr != null) startProp(spr);
  }

  function startProp(spr:LevelProp):Void
  {
    var start:String = spr.propData?.startingAnimation ?? '';
    if (start != '' && spr.hasAnimation(start)) spr.playAnimation(start, true);
    else
    {
      spr.animation.paused = false;
      spr.dance(true);
    }
  }

  /**
   * What happens when the week is picked: the confirm sound, the title flashing and the characters cheering.
   */
  function playConfirm():Void
  {
    FunkinSound.playOnce(Paths.sound('confirmMenu'));
    confirmTimer = 1.6;
    flashTimer = 0;
    for (spr in propSprites)
      if (spr != null)
      {
        spr.animation.paused = false;
        spr.playConfirm();
      }
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);
    if (rebuildQueued) rebuildPreview();

    // Dancing to the menu music's beat.
    var stepLength = 60 / MENU_BPM / 4;
    stepTimer += elapsed;
    while (stepTimer >= stepLength)
    {
      stepTimer -= stepLength;
      stepCount++;
      if (confirmTimer > 0 || holdAnimTimer > 0) continue;
      for (spr in propSprites)
      {
        if (spr == null || spr.danceEvery <= 0) continue;
        var every = Std.int(Math.max(1, Math.round(spr.danceEvery * 4)));
        if (stepCount % every == 0) spr.dance(spr.shouldBop);
      }
    }
    if (holdAnimTimer > 0) holdAnimTimer -= elapsed;
    if (confirmTimer > 0)
    {
      confirmTimer -= elapsed;
      flashTimer += elapsed;
      if (titleSprite != null && flashTimer >= 0.05)
      {
        flashTimer %= 0.05;
        titleSprite.color = titleSprite.color == FlxColor.WHITE ? 0xFF33FFFF : FlxColor.WHITE;
      }
      if (confirmTimer <= 0) restartPreview();
    }

    handlePreviewMouse();
    updateSelectionBox();
  }

  function handlePreviewMouse():Void
  {
    if (data == null) return;
    var pm = previewMouse();
    if (FlxG.mouse.justPressed && !mouseOverUI && !dialogOpen && mouseInPreview())
    {
      var i = propSprites.length - 1;
      while (i >= 0)
      {
        var spr = propSprites[i];
        if (spr != null && spr.visible)
        {
          var r = spr.getScreenBounds(null, camPreview);
          var hit = r.containsXY(pm[0], pm[1]);
          r.put();
          if (hit)
          {
            if (selectedProp != i) selectProp(i);
            changing();
            dragging = true;
            dragStart = pm;
            var o = propOffsets();
            dragOffsets = [o[0], o[1]];
            break;
          }
        }
        i--;
      }
    }
    if (dragging)
    {
      var o = propOffsets();
      o[0] = Math.round(dragOffsets[0] + pm[0] - dragStart[0]);
      o[1] = Math.round(dragOffsets[1] + pm[1] - dragStart[1]);
      placeProp(selectedProp);
      if (!FlxG.mouse.pressed)
      {
        dragging = false;
        propForm.refresh();
        committed();
      }
    }
  }

  function placeProp(i:Int):Void
  {
    if (i < 0 || i >= propSprites.length) return;
    var spr = propSprites[i];
    var p = props()[i];
    if (spr == null || p == null) return;
    var o:Array<Float> = p.offsets ?? [0.0, 0.0];
    spr.x = o[0] + SLOT_WIDTH * i;
    spr.y = o[1];
  }

  function updateSelectionBox():Void
  {
    var spr = selectedProp >= 0 && selectedProp < propSprites.length ? propSprites[selectedProp] : null;
    for (line in selLines)
      line.visible = spr != null && spr.visible;
    if (spr == null || !spr.visible) return;
    var r = spr.getScreenBounds(null, camPreview);
    var t = 3;
    selLines[0].setPosition(r.x, r.y);
    selLines[0].setGraphicSize(Std.int(Math.max(1, r.width)), t);
    selLines[1].setPosition(r.x, r.bottom - t);
    selLines[1].setGraphicSize(Std.int(Math.max(1, r.width)), t);
    selLines[2].setPosition(r.x, r.y);
    selLines[2].setGraphicSize(t, Std.int(Math.max(1, r.height)));
    selLines[3].setPosition(r.right - t, r.y);
    selLines[3].setGraphicSize(t, Std.int(Math.max(1, r.height)));
    for (line in selLines)
    {
      line.updateHitbox();
      line.alpha = dragging ? 1 : 0.75;
    }
    r.put();
  }

  override function handleShortcuts():Void
  {
    if (ctrl())
    {
      if (FlxG.keys.justPressed.Z) undo();
      if (FlxG.keys.justPressed.Y) redo();
      if (FlxG.keys.justPressed.N) newWeekDialog();
      if (FlxG.keys.justPressed.O) chooseFromList('Open a week', order, id -> switchWeek(id), weekId);
      return;
    }
    if (FlxG.keys.justPressed.SPACE) playConfirm();
    if (FlxG.keys.justPressed.R) restartPreview();
    if (FlxG.keys.justPressed.DELETE) deleteProp();
    if (prop() != null)
    {
      var step = FlxG.keys.pressed.SHIFT ? 10 : 1;
      var dx = (FlxG.keys.justPressed.RIGHT ? step : 0) - (FlxG.keys.justPressed.LEFT ? step : 0);
      var dy = (FlxG.keys.justPressed.DOWN ? step : 0) - (FlxG.keys.justPressed.UP ? step : 0);
      if (dx != 0 || dy != 0)
      {
        changing();
        var o = propOffsets();
        o[0] += dx;
        o[1] += dy;
        placeProp(selectedProp);
        propForm.refresh();
        committed();
      }
    }
  }

  override public function destroy():Void
  {
    clearPreview();
    previewDisplay?.destroy();
    super.destroy();
  }
}
#end
