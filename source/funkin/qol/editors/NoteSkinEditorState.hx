package funkin.qol.editors;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.data.notestyle.NoteStyleRegistry;
import funkin.data.song.SongData.SongNoteData;
import funkin.graphics.FunkinSprite;
import funkin.play.Countdown.CountdownStep;
import funkin.play.components.PopUpStuff;
import funkin.play.notes.NoteDirection;
import funkin.play.notes.NoteSprite;
import funkin.play.notes.Strumline;
import funkin.play.notes.notestyle.NoteStyle;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.ui.QOLTheme;
import funkin.qol.util.QOLAssets;
import haxe.ui.components.Button;
import haxe.ui.containers.HBox;

/**
 * The Note Skin Editor: make note styles (V-Slice's skins for notes, strums, hold notes, note splashes, hold covers,
 * the countdown, ratings and combo numbers) with a live preview that plays notes exactly like the game does.
 *
 * Saves to `mods/<mod>/data/notestyles/<id>.json`. Pick the skin for a song in the Chart Editor (Song > Note style).
 */
class NoteSkinEditorState extends QOLEditorState
{
  static inline final PREVIEW_MARGIN:Int = 10;
  static final DIRS:Array<String> = ['left', 'down', 'up', 'right'];
  static final DIR_NAMES:Array<String> = ['Left', 'Down', 'Up', 'Right'];
  static final SECTIONS:Array<{id:String, name:String}> = [
    {id: 'note', name: 'Notes'},
    {id: 'strum', name: 'Strums'},
    {id: 'hold', name: 'Hold notes'},
    {id: 'splash', name: 'Note splashes'},
    {id: 'cover', name: 'Hold covers'},
    {id: 'countdown', name: 'Countdown'},
    {id: 'popups', name: 'Ratings & combo'}
  ];
  static final COUNTDOWN:Array<{key:String, name:String, step:CountdownStep}> = [
    {key: 'countdownThree', name: 'Three', step: THREE},
    {key: 'countdownTwo', name: 'Two (Ready)', step: TWO},
    {key: 'countdownOne', name: 'One (Set)', step: ONE},
    {key: 'countdownGo', name: 'Go!', step: GO}
  ];
  static final RATINGS:Array<String> = ['sick', 'good', 'bad', 'shit'];

  var styleId:String = 'my-noteskin';
  var data:Dynamic;
  var section:String = 'note';

  // Preview.
  var camPreview:FlxCamera;
  var previewDisplay:Null<funkin.qol.ui.QOLScaledCameras> = null;
  var previewScale:Float = 0.5;
  var previewX:Float = 0;
  var previewY:Float = 0;
  var previewW:Int = 640;
  var previewH:Int = 360;
  var previewTitle:Null<FlxText> = null;
  var bg:FlxSprite;
  var previewStyle:Null<NoteStyle> = null;
  var player:Null<Strumline> = null;
  var opponent:Null<Strumline> = null;
  var popups:Null<PopUpStuff> = null;
  var conductor:Conductor;
  var songPos:Float = -1200;
  var playing:Bool = true;
  var speed:Float = 1;
  var scrollSpeed:Float = 1.6;
  var downscroll:Bool = false;
  var showOpponent:Bool = true;
  var autoplay:Bool = true;
  var combo:Int = 0;
  var bpm:Float = 120;
  var pattern:Array<SongNoteData> = [];
  var patternLength:Float = 8000;
  var holdUntil:Array<Array<Float>> = [[-1, -1, -1, -1], [-1, -1, -1, -1]];
  var tapUntil:Array<Array<Float>> = [[-1, -1, -1, -1], [-1, -1, -1, -1]];
  var rebuildQueued:Bool = false;
  var prefixCache:Map<String, Array<String>> = new Map();
  var formAfterLibrary:Bool = false;

  var skinForm:QOLForm;
  var sectionForm:QOLForm;
  var sectionButtons:Map<String, Button> = new Map();

  public function new(?id:String)
  {
    super();
    editorName = 'Note Skin Editor';
    leftPanelWidth = 300;
    rightPanelWidth = 360;
    leftPanelTitle = 'Note Skin';
    rightPanelTitle = 'Parts';
    if (id != null) styleId = id;
  }

  override function guidePage():String
    return 'noteskin';

  override function buildEditor():Void
  {
    gridBG.visible = false;
    camWorld.bgColor = 0xFF120E1E;
    conductor = new Conductor();
    conductor.forceBPM(bpm);

    computePreviewLayout();
    camPreview = new FlxCamera(0, 0, FlxG.width, FlxG.height);
    camPreview.bgColor = FlxColor.BLACK;
    camPreview.flashSprite.scaleX = camPreview.flashSprite.scaleY = previewScale;
    previewDisplay = new funkin.qol.ui.QOLScaledCameras([camPreview], previewX, previewY, previewScale);
    FlxG.cameras.remove(camUI, false);
    FlxG.cameras.add(camPreview, false);
    FlxG.cameras.add(camUI, false);

    bg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
    bg.setGraphicSize(FlxG.width, FlxG.height);
    bg.updateHitbox();
    bg.color = 0xFF232038;
    bg.cameras = [camPreview];
    add(bg);

    previewTitle = QOLTheme.outlinedText(previewX, previewY - 24, previewW, '', 14, QOLTheme.TEXT_DIM, 1.5);
    previewTitle.cameras = [camUI];
    add(previewTitle);

    buildMenus();
    buildSkinPanel();
    buildSectionPanel();
    buildPattern();

    var start = styleId;
    if (!NoteStyleRegistry.instance.listEntryIds().contains(start)) start = Constants.DEFAULT_NOTE_STYLE;
    if (start != styleId) newSkin(start);
    else
      openSkin(start);
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

  //
  // Menus and panels
  //

  function buildMenus():Void
  {
    var file = addMenu('File');
    addMenuItem(file, 'New Skin...', 'Ctrl+N', () -> chooseFromList('Start from which skin?', NoteStyleRegistry.instance.listEntryIds(), id -> newSkin(id)));
    addMenuItem(file, 'Open Skin...', 'Ctrl+O', () -> chooseFromList('Open a note skin', NoteStyleRegistry.instance.listEntryIds(), id -> openSkin(id), styleId));
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuSeparator(file);
    addMenuItem(file, 'Delete This Skin From My Mod', null, () -> confirm('Delete', 'Delete data/notestyles/$styleId.json from your mod?', () -> {
      ModWorkspace.delete('data/notestyles/$styleId.json');
      ModWorkspace.reloadGameData();
      notify('Deleted', 'data/notestyles/$styleId.json');
      openSkin(Constants.DEFAULT_NOTE_STYLE);
    }));

    var view = addMenu('Preview');
    addMenuItem(view, 'Play / Pause', 'Space', () -> playing = !playing);
    addMenuItem(view, 'Restart', 'R', restartPreview);
    addMenuItem(view, 'Show the Countdown', 'C', playCountdown);
    addMenuItem(view, 'Show a Rating', 'P', () -> showRating(RATINGS[FlxG.random.int(0, 3)]));
    addMenuSeparator(view);
    addMenuCheck(view, 'Downscroll', downscroll, v -> {
      downscroll = v;
      queueRebuild();
    });
    addMenuCheck(view, 'Show the Opponent', showOpponent, v -> {
      showOpponent = v;
      queueRebuild();
    });
    addMenuCheck(view, 'Autoplay', autoplay, v -> autoplay = v);
  }

  function buildSkinPanel():Void
  {
    skinForm = new QOLForm(100, 160);
    skinForm.onAnyChange = () -> dirty = true;
    skinForm.section('Skin');
    skinForm.textField('ID (file name)', () -> styleId, v -> styleId = cleanId(v));
    skinForm.textField('Name', () -> data?.name ?? '', v -> data.name = v);
    skinForm.textField('Author', () -> data?.author ?? '', v -> data.author = v);
    skinForm.dropdown('Based on', () -> ['(none)'].concat([for (id in NoteStyleRegistry.instance.listEntryIds()) if (id != styleId) id]),
      () -> data?.fallback ?? '(none)', v -> {
        data.fallback = v == '(none)' ? null : v;
        queueRebuild();
      });
    skinForm.note('Anything this skin leaves out comes from the skin it\'s based on.');

    skinForm.section('Parts');
    var grid = new haxe.ui.containers.Grid();
    grid.columns = 2;
    for (s in SECTIONS)
    {
      var b = new Button();
      b.text = s.name;
      b.width = 128;
      b.onClick = _ -> selectSection(s.id);
      grid.addComponent(b);
      sectionButtons.set(s.id, b);
    }
    skinForm.custom(grid);

    skinForm.section('Preview');
    skinForm.buttons([
      {text: 'Play / Pause', cb: () -> playing = !playing},
      {text: 'Restart', cb: restartPreview}
    ]);
    skinForm.buttons([
      {text: 'Countdown', cb: playCountdown},
      {text: 'Rating', cb: () -> showRating(RATINGS[FlxG.random.int(0, 3)])}
    ]);
    skinForm.slider('Speed', () -> speed, v -> speed = v, 0.1, 2, 0.05);
    skinForm.slider('Scroll speed', () -> scrollSpeed, v -> {
      scrollSpeed = v;
      if (player != null) player.scrollSpeed = v;
      if (opponent != null) opponent.scrollSpeed = v;
    }, 0.5, 4, 0.1);
    skinForm.check('Downscroll', () -> downscroll, v -> {
      downscroll = v;
      queueRebuild();
    });
    skinForm.check('Show the opponent', () -> showOpponent, v -> {
      showOpponent = v;
      queueRebuild();
    });
    skinForm.check('Autoplay', () -> autoplay, v -> autoplay = v);
    skinForm.colorField('Background', () -> bg.color, v -> bg.color = v);
    skinForm.note('Test it yourself: D F J K or the arrow keys press the strums.');
    leftPanel.addComponent(skinForm);
  }

  function buildSectionPanel():Void
  {
    sectionForm = new QOLForm(118, 190);
    sectionForm.onAnyChange = () -> {
      dirty = true;
      queueRebuild();
    };
    rightPanel.addComponent(sectionForm);
  }

  function selectSection(id:String):Void
  {
    section = id;
    for (s in SECTIONS)
    {
      var b = sectionButtons.get(s.id);
      if (b == null) continue;
      b.text = s.id == id ? '\u25B8 ${s.name}' : s.name;
      b.styleString = s.id == id ? 'color: #FFD84A;' : 'color: #D8D2EE;';
    }
    buildSectionForm();
  }

  //
  // Data helpers
  //

  static function cleanId(v:String):String
  {
    var s = StringTools.trim(v).toLowerCase();
    s = ~/[^a-z0-9_\-]+/g.replace(s, '-');
    return s == '' ? 'my-noteskin' : s;
  }

  function assets():Dynamic
  {
    if (data.assets == null) data.assets = {};
    return data.assets;
  }

  /**
   * One part of the skin (`note`, `noteSplash`...), made if it's missing.
   */
  function asset(key:String):Dynamic
  {
    var a:Dynamic = Reflect.field(assets(), key);
    if (a == null)
    {
      a = {assetPath: ''};
      Reflect.setField(assets(), key, a);
    }
    return a;
  }

  function assetData(key:String):Dynamic
  {
    var a = asset(key);
    if (a.data == null) a.data = {};
    return a.data;
  }

  /**
   * An animation entry (`{prefix: ...}`) in a data object.
   */
  function anim(obj:Dynamic, field:String):Dynamic
  {
    var a:Dynamic = Reflect.field(obj, field);
    if (a == null)
    {
      a = {prefix: ''};
      Reflect.setField(obj, field, a);
    }
    return a;
  }

  function offsetsOf(obj:Dynamic):Array<Float>
  {
    var o:Array<Float> = obj.offsets;
    if (o == null || o.length < 2)
    {
      o = [0, 0];
      obj.offsets = o;
    }
    return o;
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
      var parts = assetPath.split(Constants.LIBRARY_SEPARATOR);
      var key = parts.length > 1 ? parts[1] : parts[0];
      var lib = parts.length > 1 ? parts[0] : null;
      var frames = Paths.getSparrowAtlas(key, lib);
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
    catch (e:Dynamic) {}
    // Sheets that aren't loaded yet (web builds load libraries on demand) are looked at again later.
    if (out.length > 0) prefixCache.set(assetPath, out);
    return out;
  }

  //
  // Section forms
  //

  function buildSectionForm():Void
  {
    if (data == null) return;
    var f = sectionForm;
    f.clearForm();
    switch (section)
    {
      case 'note':
        f.section('Notes');
        commonFields(f, 'note', 'The four arrows that scroll toward the strums (a Sparrow sprite sheet).');
        f.check('Animated', () -> asset('note').animated == true, v -> asset('note').animated = v);
        f.section('Animation names');
        for (i in 0...4)
          prefixField(f, DIR_NAMES[i], 'note', () -> anim(assetData('note'), DIRS[i]));
      case 'strum':
        f.section('Strums');
        commonFields(f, 'noteStrumline', 'The receptors the notes hit (a Sparrow sprite sheet).');
        for (i in 0...4)
        {
          f.section('${DIR_NAMES[i]} strum');
          for (state in [['Static', 'Static'], ['Pressed', 'Press'], ['Hit', 'Confirm'], ['Hit (holding)', 'ConfirmHold']])
            prefixField(f, state[0], 'noteStrumline', () -> anim(assetData('noteStrumline'), DIRS[i] + state[1]));
        }
      case 'hold':
        f.section('Hold notes');
        commonFields(f, 'holdNote', 'A strip image: the hold\'s body and end for each color, side by side (like NOTE_hold_assets).');
      case 'splash':
        f.section('Note splashes');
        f.check('Splashes on', () -> assetData('noteSplash').enabled != false, v -> assetData('noteSplash').enabled = v);
        commonFields(f, 'noteSplash', 'Plays on SICK! hits. Each direction picks one of its animations at random.');
        f.number('Frame rate', () -> assetData('noteSplash').framerateDefault ?? 24, v -> assetData('noteSplash').framerateDefault = Std.int(v), 1, 120, 1, 0);
        f.number('Rate variety', () -> assetData('noteSplash').framerateVariance ?? 2, v -> assetData('noteSplash').framerateVariance = Std.int(v), 0, 60, 1,
          0);
        f.dropdown('Blend mode', () -> ['normal', 'add', 'screen', 'multiply', 'lighten', 'overlay'], () -> assetData('noteSplash').blendMode ?? 'normal',
          v -> assetData('noteSplash').blendMode = v);
        f.section('Animation names (comma between several)');
        for (i in 0...4)
        {
          var field = DIRS[i] + 'Splashes';
          f.textField(DIR_NAMES[i], () -> {
            var list:Array<Dynamic> = Reflect.field(assetData('noteSplash'), field);
            return list == null ? '' : [for (a in list) a.prefix].join(', ');
          }, v -> {
            var names = [for (n in v.split(',')) StringTools.trim(n)].filter(n -> n != '');
            Reflect.setField(assetData('noteSplash'), field, [for (n in names) {prefix: n}]);
          });
        }
        var names = prefixesOf(asset('noteSplash').assetPath);
        if (names.length > 0) f.note('In this sheet: ' + names.join(', '));
      case 'cover':
        f.section('Hold covers');
        f.check('Covers on', () -> assetData('holdNoteCover').enabled != false, v -> assetData('holdNoteCover').enabled = v);
        f.pair('Offset', () -> offsetsOf(asset('holdNoteCover'))[0], v -> offsetsOf(asset('holdNoteCover'))[0] = v,
          () -> offsetsOf(asset('holdNoteCover'))[1], v -> offsetsOf(asset('holdNoteCover'))[1] = v);
        f.note('The flame on a strum while a hold note is held: a start, a loop and an end animation.');
        for (i in 0...4)
        {
          var dir = DIRS[i];
          f.section('${DIR_NAMES[i]} cover');
          var dd = () -> {
            var d = assetData('holdNoteCover');
            var o:Dynamic = Reflect.field(d, dir);
            if (o == null)
            {
              o = {assetPath: ''};
              Reflect.setField(d, dir, o);
            }
            return o;
          };
          f.file('Image', () -> dd().assetPath ?? '', v -> {
            var o:Dynamic = dd();
            o.assetPath = v;
          }, cb -> browseModFile('Hold cover sheet', 'images', ['png'], cb));
          for (part in [['Start', 'start'], ['Loop', 'hold'], ['End', 'end']])
            prefixDropdown(f, part[0], () -> dd().assetPath, () -> anim(dd(), part[1]));
        }
      case 'countdown':
        f.section('Countdown');
        f.note('Before the song: a sound for each beat, and the READY, SET, GO! pictures.');
        for (c in COUNTDOWN)
        {
          f.section(c.name);
          var key = c.key;
          if (key != 'countdownThree')
          {
            f.file('Picture', () -> asset(key).assetPath ?? '', v -> asset(key).assetPath = v, cb -> browseModFile('Countdown picture', 'images', ['png'], cb));
            f.number('Scale', () -> asset(key).scale ?? 1, v -> asset(key).scale = v, 0.05, 20, 0.05, 2);
            f.check('Pixel art', () -> asset(key).isPixel == true, v -> asset(key).isPixel = v);
          }
          f.file('Sound', () -> assetData(key).audioPath ?? '', v -> assetData(key).audioPath = v,
            cb -> browseModFile('Countdown sound', 'sounds', ['ogg', 'mp3', 'wav'], cb));
          f.button('Play', () -> {
            var path = previewStyle?.getCountdownSoundPath(c.step);
            if (path != null) FunkinSound.playOnce(path, 1.0);
          });
        }
      case 'popups':
        f.section('Ratings');
        f.note('The SICK!/GOOD!/BAD!/SHIT! pop-ups and the combo numbers.');
        for (r in RATINGS)
        {
          var key = 'judgement' + r.charAt(0).toUpperCase() + r.substr(1);
          f.file(r.toUpperCase(), () -> asset(key).assetPath ?? '', v -> asset(key).assetPath = v, cb -> browseModFile('Rating picture', 'images', ['png'], cb));
          f.number('  Scale', () -> asset(key).scale ?? 1, v -> asset(key).scale = v, 0.05, 20, 0.05, 2);
        }
        f.check('Pixel art ratings', () -> asset('judgementSick').isPixel == true, v -> {
          for (r in RATINGS)
            asset('judgement' + r.charAt(0).toUpperCase() + r.substr(1)).isPixel = v;
        });
        f.button('Show a rating', () -> showRating(RATINGS[FlxG.random.int(0, 3)]));
        f.section('Combo numbers');
        for (i in 0...10)
        {
          var key = 'comboNumber$i';
          f.file('$i', () -> asset(key).assetPath ?? '', v -> asset(key).assetPath = v, cb -> browseModFile('Combo number $i', 'images', ['png'], cb));
        }
        f.number('Number scale', () -> asset('comboNumber0').scale ?? 1, v -> {
          for (i in 0...10)
            asset('comboNumber$i').scale = v;
        }, 0.05, 20, 0.05, 2);
        f.check('Pixel art numbers', () -> asset('comboNumber0').isPixel == true, v -> {
          for (i in 0...10)
            asset('comboNumber$i').isPixel = v;
        });
      default:
    }
    f.refresh();
  }

  function commonFields(f:QOLForm, key:String, help:String):Void
  {
    f.note(help);
    f.file('Image', () -> asset(key).assetPath ?? '', v -> {
      asset(key).assetPath = v;
      prefixCache.remove(v);
      buildSectionForm();
    }, cb -> browseModFile('Choose the sprite sheet', 'images', ['png'], cb));
    f.number('Scale', () -> asset(key).scale ?? 1, v -> asset(key).scale = v, 0.05, 20, 0.05, 2);
    f.pair('Offset', () -> offsetsOf(asset(key))[0], v -> offsetsOf(asset(key))[0] = v, () -> offsetsOf(asset(key))[1], v -> offsetsOf(asset(key))[1] = v);
    f.slider('Opacity', () -> asset(key).alpha ?? 1, v -> asset(key).alpha = v, 0, 1, 0.05);
    f.check('Pixel art', () -> asset(key).isPixel == true, v -> asset(key).isPixel = v);
  }

  function prefixField(f:QOLForm, label:String, key:String, entry:Void->Dynamic):Void
    prefixDropdown(f, label, () -> asset(key).assetPath, entry);

  /**
   * An animation name: picked from the sprite sheet's animations (or typed).
   */
  function prefixDropdown(f:QOLForm, label:String, path:Void->Null<String>, entry:Void->Dynamic):Void
  {
    var names = prefixesOf(path());
    if (names.length > 0)
    {
      f.dropdown(label, () -> {
        var cur:String = entry().prefix ?? '';
        return names.contains(cur) || cur == '' ? names : [cur].concat(names);
      }, () -> entry().prefix ?? '', v -> entry().prefix = v);
    }
    else
      f.textField(label, () -> entry().prefix ?? '', v -> entry().prefix = v);
  }

  //
  // Opening and saving
  //

  function rawData(id:String):Dynamic
  {
    var rel = 'data/notestyles/$id.json';
    if (ModWorkspace.hasMod && ModWorkspace.exists(rel))
    {
      var d = ModWorkspace.getJson(rel);
      if (d != null) return d;
    }
    try
    {
      var text = openfl.utils.Assets.getText(Paths.json('notestyles/$id'));
      if (text != null) return haxe.Json.parse(text);
    }
    catch (e:Dynamic) {}
    return null;
  }

  function openSkin(id:String):Void
  {
    var d = rawData(id);
    if (d == null)
    {
      alert('Could not open', 'The note skin "$id" could not be read.');
      return;
    }
    styleId = id;
    data = d;
    afterLoad();
  }

  /**
   * A new skin: a copy of another one, based on it.
   */
  function newSkin(baseId:String):Void
  {
    var d:Dynamic = rawData(baseId);
    if (d == null) d = {version: NoteStyleRegistry.NOTE_STYLE_DATA_VERSION.toString(), name: 'My Note Skin', author: '', assets: {}};
    d = haxe.Json.parse(haxe.Json.stringify(d));
    d.name = 'My Note Skin';
    d.author = '';
    d.fallback = baseId;
    var id = 'my-noteskin';
    var n = 2;
    var ids = NoteStyleRegistry.instance.listEntryIds();
    while (ids.contains(id))
      id = 'my-noteskin-${n++}';
    styleId = id;
    data = d;
    afterLoad();
    dirty = true;
  }

  function afterLoad():Void
  {
    prefixCache = new Map();
    skinForm.refresh();
    selectSection(section);
    queueRebuild();
    dirty = false;
  }

  override function save():Bool
  {
    data.version = NoteStyleRegistry.NOTE_STYLE_DATA_VERSION.toString();
    var order = ['version', 'name', 'author', 'fallback', 'assets', 'note', 'noteStrumline', 'holdNote', 'noteSplash', 'holdNoteCover', 'countdownThree',
      'countdownTwo', 'countdownOne', 'countdownGo', 'judgementSick', 'judgementGood', 'judgementBad', 'judgementShit'];
    for (i in 0...10)
      order.push('comboNumber$i');
    order = order.concat(['assetPath', 'scale', 'offsets', 'isPixel', 'alpha', 'animated', 'data', 'enabled', 'left', 'down', 'up', 'right']);
    var path = ModWorkspace.saveJson('data/notestyles/$styleId.json', clean(data), order);
    notifySaved(path);
    return true;
  }

  override function afterSaveReload():Void
  {
    ModWorkspace.reloadGameData();
    queueRebuild();
  }

  /**
   * Drop empty bits (an empty image path means "use the skin this is based on").
   */
  static function clean(d:Dynamic):Dynamic
  {
    var out:Dynamic = haxe.Json.parse(haxe.Json.stringify(d));
    var a:Dynamic = out.assets;
    if (a != null)
    {
      for (k in Reflect.fields(a))
      {
        var v:Dynamic = Reflect.field(a, k);
        if (v == null) continue;
        if (v.assetPath == '' && k != 'holdNoteCover' && k != 'countdownThree' && (v.data == null || Reflect.fields(v.data).length == 0))
          Reflect.deleteField(a, k);
      }
    }
    return out;
  }

  //
  // Preview
  //

  function queueRebuild():Void
    rebuildQueued = true;

  /**
   * The skin being edited as a real note style (read the same way the game reads it).
   */
  function buildStyle():Null<NoteStyle>
  {
    try
    {
      var parsed = NoteStyleRegistry.instance.parseEntryDataRaw(haxe.Json.stringify(clean(data)), '$styleId.json');
      if (parsed == null) return null;
      var style:NoteStyle = Type.createEmptyInstance(NoteStyle);
      Reflect.setField(style, 'id', styleId);
      Reflect.setField(style, '_data', parsed);
      return style;
    }
    catch (e:Dynamic)
    {
      setStatus('Preview: $e');
      return null;
    }
  }

  function rebuildPreview():Void
  {
    rebuildQueued = false;
    var style = buildStyle();
    if (style == null) return;
    QOLAssets.withLibrary('shared', () -> {
      clearPreview();
      previewStyle = style;
      try
      {
        player = makeLine(style, true);
        if (showOpponent) opponent = makeLine(style, false);
        popups = new PopUpStuff(style);
        popups.cameras = [camPreview];
        add(popups);
      }
      catch (e:Dynamic)
      {
        setStatus('Preview: $e');
      }
      restartPreview();
      if (!formAfterLibrary)
      {
        // The shared library is ready now: the animation lists can be filled in.
        formAfterLibrary = true;
        buildSectionForm();
      }
      if (previewTitle != null) previewTitle.text = '${data.name ?? styleId}  ·  ${downscroll ? 'downscroll' : 'upscroll'}';
    });
  }

  function makeLine(style:NoteStyle, isPlayer:Bool):Strumline
  {
    var line = new Strumline(style, true, scrollSpeed);
    line.conductorInUse = conductor;
    line.isDownscroll = downscroll;
    line.cameras = [camPreview];
    add(line);
    line.x = isPlayer ? FlxG.width / 2 + Constants.STRUMLINE_X_OFFSET : Constants.STRUMLINE_X_OFFSET;
    line.y = downscroll ? FlxG.height - line.height - Constants.STRUMLINE_Y_OFFSET - style.getStrumlineOffsets()[1] : Constants.STRUMLINE_Y_OFFSET;
    line.fadeInArrows();
    return line;
  }

  function clearPreview():Void
  {
    for (line in [player, opponent])
    {
      if (line == null) continue;
      remove(line, true);
      line.destroy();
    }
    player = opponent = null;
    if (popups != null)
    {
      remove(popups, true);
      popups.destroy();
      popups = null;
    }
  }

  /**
   * A looping pattern: taps, chords, jacks and holds of different lengths.
   */
  function buildPattern():Void
  {
    pattern = [];
    var beat = 60000 / bpm;
    var steps:Array<Array<Float>> = [
      // [beat, direction, length in beats]
      [0, 0, 0], [0.5, 1, 0], [1, 2, 0], [1.5, 3, 0], [2, 0, 1.5], [2, 3, 1.5], [4, 1, 0], [4.25, 2, 0], [4.5, 1, 0], [4.75, 2, 0],
      [5, 0, 0], [5.5, 3, 0], [6, 1, 2.5], [6.5, 3, 0], [7, 0, 0], [7.5, 2, 0], [9, 0, 0], [9, 3, 0], [9.5, 1, 0], [9.5, 2, 0],
      [10, 2, 3], [10.5, 0, 0], [11, 1, 0], [11.5, 3, 0], [12, 0, 0], [12.5, 3, 0], [13, 1, 0.75], [14, 2, 0.75], [15, 3, 0]
    ];
    for (s in steps)
      pattern.push(new SongNoteData(s[0] * beat, Std.int(s[1]), s[2] * beat));
    patternLength = 16 * beat;
  }

  function restartPreview():Void
  {
    songPos = -1200;
    combo = 0;
    holdUntil = [[-1, -1, -1, -1], [-1, -1, -1, -1]];
    tapUntil = [[-1, -1, -1, -1], [-1, -1, -1, -1]];
    for (line in [player, opponent])
    {
      if (line == null) continue;
      line.clean();
      line.scrollSpeed = scrollSpeed;
      line.applyNoteData([for (n in pattern) new SongNoteData(n.time, n.data, n.length)]);
    }
    conductor.update(songPos, false);
  }

  function playCountdown():Void
  {
    if (previewStyle == null) return;
    var steps = [THREE, TWO, ONE, GO];
    var beat = 60 / bpm;
    for (i in 0...steps.length)
    {
      var step = steps[i];
      new flixel.util.FlxTimer().start(beat * i + 0.001, _ -> {
        if (previewStyle == null) return;
        var path = previewStyle.getCountdownSoundPath(step);
        if (path != null) FunkinSound.playOnce(path, Constants.COUNTDOWN_VOLUME);
        var spr:Null<FunkinSprite> = previewStyle.buildCountdownSprite(step);
        if (spr == null) return;
        spr.cameras = [camPreview];
        add(spr);
        spr.screenCenter();
        var o = previewStyle.getCountdownSpriteOffsets(step);
        spr.x += o[0];
        spr.y += o[1];
        var ease = previewStyle.isCountdownSpritePixel(step) ? funkin.util.EaseUtil.stepped(8) : FlxEase.cubeInOut;
        FlxTween.tween(spr, {alpha: 0}, beat, {ease: ease, onComplete: _ -> {
          remove(spr, true);
          spr.destroy();
        }});
      });
    }
  }

  function showRating(r:String):Void
  {
    if (popups == null) return;
    combo++;
    popups.displayRating(r);
    if (combo >= 2) popups.displayCombo(combo);
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);
    if (rebuildQueued) rebuildPreview();
    if (player == null) return;

    if (playing)
    {
      songPos += elapsed * 1000 * speed;
      if (songPos > patternLength + 600) restartPreview();
    }
    conductor.update(songPos, false);

    var lines = [player, opponent];
    for (li in 0...2)
    {
      var line = lines[li];
      if (line == null) continue;
      var isPlayerLine = li == 0;
      if (autoplay || !isPlayerLine)
      {
        for (note in line.notes.members)
        {
          if (note == null || !note.alive || note.hasBeenHit || note.strumTime > songPos) continue;
          hitNote(line, li, note, isPlayerLine);
        }
      }
      for (d in 0...4)
      {
        if (holdUntil[li][d] >= 0 && songPos >= holdUntil[li][d])
        {
          holdUntil[li][d] = -1;
          line.releaseKey(d, 777);
        }
        if (tapUntil[li][d] >= 0 && songPos >= tapUntil[li][d])
        {
          tapUntil[li][d] = -1;
          if (!line.isKeyHeld(d)) line.playStatic(d);
        }
      }
    }

    // Test keys.
    if (!isTyping && !dialogOpen)
    {
      var keys = [[FlxG.keys.justPressed.D, FlxG.keys.justPressed.LEFT], [FlxG.keys.justPressed.F, FlxG.keys.justPressed.DOWN],
        [FlxG.keys.justPressed.J, FlxG.keys.justPressed.UP], [FlxG.keys.justPressed.K, FlxG.keys.justPressed.RIGHT]];
      var released = [[FlxG.keys.justReleased.D, FlxG.keys.justReleased.LEFT], [FlxG.keys.justReleased.F, FlxG.keys.justReleased.DOWN],
        [FlxG.keys.justReleased.J, FlxG.keys.justReleased.UP], [FlxG.keys.justReleased.K, FlxG.keys.justReleased.RIGHT]];
      for (d in 0...4)
      {
        if (keys[d][0] || keys[d][1]) pressTest(d);
        if (released[d][0] || released[d][1])
        {
          player.releaseKey(d, 555);
          if (!player.isKeyHeld(d)) player.playStatic(d);
        }
      }
      if (FlxG.keys.justPressed.SPACE) playing = !playing;
      if (FlxG.keys.justPressed.R) restartPreview();
      if (FlxG.keys.justPressed.C) playCountdown();
      if (FlxG.keys.justPressed.P) showRating(RATINGS[FlxG.random.int(0, 3)]);
    }
  }

  function hitNote(line:Strumline, li:Int, note:NoteSprite, isPlayerLine:Bool):Void
  {
    var d:Int = note.direction;
    line.hitNote(note);
    if (note.holdNoteSprite != null)
    {
      line.pressKey(d, 777);
      holdUntil[li][d] = note.strumTime + note.holdNoteSprite.fullSustainLength;
      line.playNoteHoldCover(note.holdNoteSprite);
    }
    else
      tapUntil[li][d] = songPos + 140;
    if (isPlayerLine)
    {
      line.playNoteSplash(d);
      showRating('sick');
    }
  }

  /**
   * A key pressed by hand: hit a note close enough, or just press the strum.
   */
  function pressTest(d:Int):Void
  {
    player.pressKey(d, 555);
    var best:Null<NoteSprite> = null;
    for (note in player.notes.members)
    {
      if (note == null || !note.alive || note.hasBeenHit || note.direction != d) continue;
      if (Math.abs(note.strumTime - songPos) > Constants.HIT_WINDOW_MS) continue;
      if (best == null || note.strumTime < best.strumTime) best = note;
    }
    if (best != null)
    {
      var diff = Math.abs(best.strumTime - songPos);
      var rating = diff < 45 ? 'sick' : (diff < 90 ? 'good' : (diff < 135 ? 'bad' : 'shit'));
      player.hitNote(best);
      if (best.holdNoteSprite != null) player.playNoteHoldCover(best.holdNoteSprite);
      if (rating == 'sick') player.playNoteSplash(d);
      showRating(rating);
    }
    else
      player.playPress(d);
  }

  override public function destroy():Void
  {
    clearPreview();
    previewDisplay?.destroy();
    super.destroy();
  }
}
#end
