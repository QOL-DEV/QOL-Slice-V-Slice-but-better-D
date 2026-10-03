package funkin.qol.editors;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.data.freeplay.album.AlbumRegistry;
import funkin.data.freeplay.style.FreeplayStyleRegistry;
import funkin.data.song.SongRegistry;
import funkin.data.story.level.LevelRegistry;
import funkin.graphics.FunkinSprite;
import funkin.qol.runtime.QOLFreeplay;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.ui.QOLTheme;
import funkin.qol.util.QOLIconGen;
import funkin.qol.util.QOLSongAudio;
import funkin.ui.freeplay.DifficultyStars;
import funkin.ui.freeplay.SongMenuItem;
import funkin.ui.freeplay.components.DifficultySprite;
import haxe.ui.components.Label;
import haxe.ui.containers.ListView;
import haxe.ui.data.ArrayDataSource;
import openfl.utils.Assets;

/**
 * The Freeplay Editor: the songs in Freeplay (add songs that aren't in a week, hide songs), each song's difficulty
 * ratings, album and music preview, and the albums themselves. With a live Freeplay preview.
 *
 * Saves song settings into the songs' metadata (`data/songs/<id>/<id>-metadata.json`), albums to
 * `data/ui/freeplay/albums/<id>.json`, and the song list changes to `data/qol/freeplay.json`.
 */
class FreeplayEditorState extends QOLEditorState
{
  static inline final PREVIEW_MARGIN:Int = 10;
  static inline final CAPSULES:Int = 7;
  static inline final CAPSULES_ABOVE:Int = 2;
  static inline final MAX_UNDO:Int = 100;
  static inline final ART_SYMBOL:String = 'album art placeholder';
  static final META_ORDER:Array<String> = [
    'version', 'songName', 'artist', 'charter', 'divisions', 'looped', 'offsets', 'playData', 'songVariations', 'difficulties', 'characters', 'player',
    'girlfriend', 'opponent', 'altInstrumentals', 'opponentVocals', 'playerVocals', 'stage', 'noteStyle', 'ratings', 'easy', 'normal', 'hard', 'erect',
    'nightmare', 'album', 'previewStart', 'previewEnd', 'stickerPack', 'generatedBy', 'timeChanges', 't', 'b', 'bpm', 'n', 'd', 'bt'
  ];
  static final ALBUM_ORDER:Array<String> = [
    'version', 'name', 'artists', 'albumArtAsset', 'albumTitleAsset', 'albumTitleOffsets', 'albumTitleAnimations', 'albumOSTName', 'discordRPCImage'
  ];

  var fp:QOLFreeplayData;
  var entries:Array<QOLFreeplayExtra> = [];
  var selected:Int = -1;
  var selectedAlbum:Null<String> = null;
  var variation:String = 'default';
  var previewDifficulty:String = 'normal';
  var styleId:String = 'bf';

  /**
   * Loaded song metadata (`id:variation`) and albums, edited in place. `saved` holds each one as it was loaded or
   * last saved, so saving writes only what changed.
   */
  var metas:Map<String, Dynamic> = new Map();
  var albums:Map<String, Dynamic> = new Map();
  var saved:Map<String, String> = new Map();

  // Undo.
  var undoStack:Array<String> = [];
  var redoStack:Array<String> = [];
  var lastSnapshot:String = '';
  var applyingUndo:Bool = false;

  // Music preview.
  var inst:Null<FunkinSound> = null;
  var instKey:String = '';
  var instLoading:Bool = false;
  var playingPreview:Bool = false;
  var timesLabel:Null<Label> = null;

  // Preview.
  var camPreview:FlxCamera;
  var previewDisplay:Null<funkin.qol.ui.QOLScaledCameras> = null;
  var previewScale:Float = 0.5;
  var previewX:Float = 0;
  var previewY:Float = 0;
  var previewW:Int = 640;
  var previewH:Int = 360;
  var previewTitle:Null<FlxText> = null;
  var sceneItems:Array<FlxSprite> = [];
  var capsules:Array<SongMenuItem> = [];
  var capsuleEntry:Array<Int> = [];
  var art:Null<FunkinSprite> = null;
  var albumTitle:Null<FunkinSprite> = null;
  var stars:Null<DifficultyStars> = null;
  var diffSprite:Null<FlxSprite> = null;
  var refreshQueued:Bool = false;
  var sceneQueued:Bool = false;
  var shownArt:String = '';
  var shownTitle:String = '';
  var ostText:Null<FlxText> = null;

  // Panels.
  var listForm:QOLForm;
  var form:QOLForm;
  var songList:ListView;
  var albumList:ListView;
  var filling:Bool = false;

  public function new(?songId:String)
  {
    super();
    editorName = 'Freeplay Editor';
    leftPanelWidth = 300;
    rightPanelWidth = 340;
    leftPanelTitle = 'Freeplay';
    rightPanelTitle = 'Settings';
    startSong = songId;
  }

  var startSong:Null<String> = null;

  override function guidePage():String
    return 'freeplay';

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

    previewTitle = QOLTheme.outlinedText(previewX, previewY - 24, previewW, '', 14, QOLTheme.TEXT_DIM, 1.5);
    previewTitle.cameras = [camUI];
    add(previewTitle);

    fp = loadConfig();
    saved.set('fp', haxe.Json.stringify(fp));

    buildMenus();
    buildListPanel();
    form = new QOLForm(118, 170);
    form.onAnyChange = () -> {
      committed();
      queueRefresh();
    };
    rightPanel.addComponent(form);

    var styles = FreeplayStyleRegistry.instance.listEntryIds();
    if (!styles.contains(styleId) && styles.length > 0) styleId = styles[0];

    buildScene();
    refreshEntries();
    var at = 0;
    if (startSong != null) for (i in 0...entries.length)
      if (entries[i].song == startSong) at = i;
    selectSong(entries.length > 0 ? at : -1);
    lastSnapshot = snapshot();
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
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuSeparator(file);
    addMenuItem(file, 'Add a Song to Freeplay...', null, addExtraSong);
    addMenuItem(file, 'New Album...', null, newAlbumDialog);

    var edit = addMenu('Edit');
    addMenuItem(edit, 'Undo', 'Ctrl+Z', undo);
    addMenuItem(edit, 'Redo', 'Ctrl+Y', redo);

    var view = addMenu('Preview');
    addMenuItem(view, 'Play the Music Preview', 'Space', togglePreviewMusic);
    addMenuItem(view, 'Previous Song', 'Up', () -> moveSelection(-1));
    addMenuItem(view, 'Next Song', 'Down', () -> moveSelection(1));
  }

  function makeList(height:Float, onPick:Int->Void):ListView
  {
    var list = new ListView();
    list.width = leftPanelWidth - 34;
    list.height = height;
    list.onChange = _ -> {
      if (filling) return;
      if (list.selectedIndex >= 0) onPick(list.selectedIndex);
    };
    return list;
  }

  function buildListPanel():Void
  {
    var f = listForm = new QOLForm(100, 160);
    f.onAnyChange = () -> queueScene();
    f.section('Songs in Freeplay');
    songList = makeList(250, i -> {
      if (i != selected || selectedAlbum != null) selectSong(i);
    });
    f.custom(songList);
    f.buttons([{text: 'Add a song...', cb: addExtraSong}, {text: 'Hide / Show', cb: toggleHidden}]);
    f.note('Every week\'s songs are in Freeplay already. Add songs that aren\'t in a week, or hide songs.');

    f.section('Albums');
    albumList = makeList(110, i -> {
      var id = albumIds()[i];
      if (id != selectedAlbum) selectAlbum(id);
    });
    f.custom(albumList);
    f.buttons([{text: 'New...', cb: newAlbumDialog}, {text: 'Copy', cb: copyAlbum}, {text: 'Delete', cb: deleteAlbum}]);

    f.section('Preview');
    f.dropdown('Difficulty', () -> {
      var list = selected >= 0 ? difficultiesOf(entries[selected].song, variation) : [];
      if (list.length == 0) list = ['normal'];
      if (!list.contains(previewDifficulty)) previewDifficulty = list.contains('normal') ? 'normal' : list[0];
      return list;
    }, () -> previewDifficulty, v -> {
      previewDifficulty = v;
      stopPreviewMusic();
      instKey = '';
    });
    f.dropdown('Style', () -> FreeplayStyleRegistry.instance.listEntryIds(), () -> styleId, v -> {
      styleId = v;
      rebuildScene();
    });
    f.buttons([{text: 'Play music (Space)', cb: togglePreviewMusic}, {text: 'Stop', cb: stopPreviewMusic}]);
    leftPanel.addComponent(f);
  }

  //
  // Data
  //

  static function readJson(rel:String, assetKey:String):Dynamic
  {
    if (ModWorkspace.hasMod && ModWorkspace.exists(rel))
    {
      var d = ModWorkspace.getJson(rel);
      if (d != null) return d;
    }
    try
    {
      var path = Paths.json(assetKey);
      if (Assets.exists(path)) return funkin.qol.util.QOLJson.parse(Assets.getText(path));
    }
    catch (e:Dynamic) {}
    return null;
  }

  function loadConfig():QOLFreeplayData
    return QOLFreeplay.parse(readJson('data/${QOLFreeplay.PATH}.json', QOLFreeplay.PATH));

  static function variationSuffix(v:String):String
    return v == null || v == '' || v == Constants.DEFAULT_VARIATION ? '' : '-$v';

  static function metaPath(id:String, v:String):String
    return 'data/songs/$id/$id-metadata${variationSuffix(v)}.json';

  /**
   * A song's metadata for a variation (loaded the first time it's needed).
   */
  function meta(id:String, ?v:String):Dynamic
  {
    if (v == null) v = Constants.DEFAULT_VARIATION;
    var key = '$id:$v';
    if (!metas.exists(key))
    {
      var d:Dynamic = readJson(metaPath(id, v), 'songs/$id/$id-metadata${variationSuffix(v)}');
      metas.set(key, d);
      saved.set('m:$key', d == null ? '' : haxe.Json.stringify(d));
    }
    return metas.get(key);
  }

  function playData(id:String, ?v:String):Dynamic
  {
    var m = meta(id, v);
    if (m == null) return null;
    if (m.playData == null) m.playData = {};
    return m.playData;
  }

  function variationsOf(id:String):Array<String>
  {
    var out = [Constants.DEFAULT_VARIATION];
    var pd = playData(id);
    if (pd != null && Std.isOfType(pd.songVariations, Array)) for (v in (pd.songVariations : Array<String>))
      if (!out.contains(v)) out.push(v);
    return out;
  }

  function difficultiesOf(id:String, v:String):Array<String>
  {
    var pd = playData(id, v);
    if (pd == null || !Std.isOfType(pd.difficulties, Array)) return [];
    return (pd.difficulties : Array<String>).copy();
  }

  function ratingOf(id:String, v:String, diff:String):Int
  {
    var pd = playData(id, v);
    if (pd?.ratings == null) return 0;
    var r:Dynamic = Reflect.field(pd.ratings, diff);
    return r == null ? 0 : Std.int(r);
  }

  function songName(id:String):String
  {
    var m = meta(id);
    return m?.songName ?? id;
  }

  function albumIds():Array<String>
  {
    var out = [for (id in AlbumRegistry.instance.listEntryIds()) if (albums.get(id) != DELETED) id];
    for (id in albums.keys())
      if (!out.contains(id) && albums.get(id) != null && albums.get(id) != DELETED) out.push(id);
    out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
    return out;
  }

  static final DELETED:Dynamic = {deleted: true};

  function album(id:String):Dynamic
  {
    if (id == null || id == '') return null;
    if (!albums.exists(id))
    {
      var d:Dynamic = readJson('data/ui/freeplay/albums/$id.json', 'ui/freeplay/albums/$id');
      albums.set(id, d);
      saved.set('a:$id', d == null ? '' : haxe.Json.stringify(d));
    }
    var a = albums.get(id);
    return a == DELETED ? null : a;
  }

  function extraOf(id:String):Null<QOLFreeplayExtra>
  {
    for (e in fp.extra)
      if (e.song == id) return e;
    return null;
  }

  static function cleanId(v:String):String
  {
    var s = StringTools.trim(v).toLowerCase();
    s = ~/[^a-z0-9_\-]+/g.replace(s, '-');
    return s == '' ? 'my-album' : s;
  }

  static function capitalize(s:String):String
    return s.length == 0 ? s : s.charAt(0).toUpperCase() + s.substr(1);

  /**
   * The little week name on a capsule, made the same way the game makes it.
   */
  static function weekLabel(levelId:String):String
  {
    var level = LevelRegistry.instance.fetchEntry(levelId);
    if (level != null && level.getCapsuleTitle() != null) return level.getCapsuleTitle();
    var out = '';
    for (i in 0...levelId.length)
    {
      if (i == 0)
      {
        out += levelId.charAt(i);
        continue;
      }
      var prev = levelId.charAt(i - 1);
      var cur = levelId.charAt(i);
      if (prev.toLowerCase() == prev && cur.toLowerCase() != cur) out += ' ';
      if (Std.parseInt(prev) == null && Std.parseInt(cur) != null) out += ' ';
      if (Std.parseInt(prev) != null && Std.parseInt(cur) == null) out += ' ';
      out += cur;
    }
    return out;
  }

  //
  // Lists
  //

  function fillList(list:ListView, items:Array<String>, sel:Int):Void
  {
    filling = true;
    var ds = new ArrayDataSource<Dynamic>();
    for (item in items)
      ds.add({text: item});
    list.dataSource = ds;
    list.selectedIndex = sel >= 0 && sel < items.length ? sel : -1;
    filling = false;
  }

  /**
   * Work out the Freeplay list again (after adding, hiding or moving songs).
   */
  function refreshEntries():Void
  {
    var current = selected >= 0 && selected < entries.length ? entries[selected].song : null;
    entries = QOLFreeplay.listEntries(fp, true);
    selected = -1;
    if (current != null) for (i in 0...entries.length)
      if (entries[i].song == current) selected = i;
    refreshSongList();
  }

  function refreshSongList():Void
  {
    var items = [];
    for (e in entries)
    {
      var label = '${songName(e.song)}   ·   ${e.week}';
      if (fp.hidden.contains(e.song)) label += '   (hidden)';
      else if (extraOf(e.song) != null) label += '   (added)';
      items.push(label);
    }
    fillList(songList, items, selectedAlbum == null ? selected : -1);
  }

  function refreshAlbumList():Void
  {
    var ids = albumIds();
    var items = [for (id in ids) '$id   ·   ${album(id)?.name ?? '?'}'];
    fillList(albumList, items, selectedAlbum == null ? -1 : ids.indexOf(selectedAlbum));
  }

  //
  // Selection and forms
  //

  function selectSong(i:Int):Void
  {
    if (i != selected || selectedAlbum != null) stopPreviewMusic();
    selected = i;
    selectedAlbum = null;
    variation = Constants.DEFAULT_VARIATION;
    refreshSongList();
    refreshAlbumList();
    listForm.refresh();
    buildForm();
    queueRefresh();
  }

  function selectAlbum(id:Null<String>):Void
  {
    selectedAlbum = id;
    refreshSongList();
    refreshAlbumList();
    buildForm();
    queueRefresh();
  }

  function moveSelection(dir:Int):Void
  {
    if (entries.length == 0) return;
    var i = selected < 0 ? 0 : selected + dir;
    if (i < 0) i = entries.length - 1;
    if (i >= entries.length) i = 0;
    selectSong(i);
  }

  function buildForm():Void
  {
    var f = form;
    f.clearForm();
    timesLabel = null;
    if (selectedAlbum != null) buildAlbumForm(f);
    else if (selected >= 0 && selected < entries.length) buildSongForm(f);
    else
      f.note('Pick a song or an album on the left.');
    f.refresh();
  }

  function buildSongForm(f:QOLForm):Void
  {
    var id = entries[selected].song;
    var m = meta(id, variation);
    f.section(songName(id));
    f.note('Song "$id", listed with ${entries[selected].week}.');
    if (m == null)
    {
      f.note('This song\'s metadata could not be read.');
      return;
    }
    var vars = variationsOf(id);
    if (vars.length > 1) f.dropdown('Variation', () -> vars, () -> variation, v -> {
      variation = v;
      stopPreviewMusic();
      instKey = '';
      buildForm();
      queueRefresh();
    });
    f.textField('Name', () -> meta(id, variation)?.songName ?? '', v -> meta(id, variation).songName = v);
    f.textField('Artist', () -> meta(id, variation)?.artist ?? '', v -> meta(id, variation).artist = v);
    f.dropdown('Album', () -> ['(none)'].concat(albumIds()), () -> playData(id, variation)?.album ?? '(none)', v -> {
      var pd = playData(id, variation);
      if (v == '(none)') Reflect.deleteField(pd, 'album');
      else
        pd.album = v;
    });

    f.section('Difficulty ratings');
    var diffs = difficultiesOf(id, variation);
    if (diffs.length == 0) f.note('This variation has no difficulties.');
    for (d in diffs)
    {
      f.number(capitalize(d), () -> ratingOf(id, variation, d), v -> {
        var pd = playData(id, variation);
        if (pd.ratings == null) pd.ratings = {};
        Reflect.setField(pd.ratings, d, Std.int(v));
      }, 0, 99, 1, 0);
    }
    f.note('The number on the song\'s capsule and the stars under the album (up to 15).');

    f.section('Music preview');
    f.slider('Starts at', () -> playData(id, variation)?.previewStart ?? Constants.DEFAULT_PREVIEW_START_TIME, v -> {
      playData(id, variation).previewStart = Math.round(v * 1000) / 1000;
      updateTimesLabel();
    }, 0, 1, 0.005);
    f.slider('Ends at', () -> playData(id, variation)?.previewEnd ?? Constants.DEFAULT_PREVIEW_END_TIME, v -> {
      playData(id, variation).previewEnd = Math.round(v * 1000) / 1000;
      updateTimesLabel();
    }, 0, 1, 0.005);
    timesLabel = f.note('');
    updateTimesLabel();
    f.buttons([{text: 'Play', cb: playPreviewMusic}, {text: 'Stop', cb: stopPreviewMusic}]);

    f.section('In Freeplay');
    f.check('Hidden', () -> fp.hidden.contains(id), v -> setHidden(id, v));
    var extra = extraOf(id);
    if (extra != null)
    {
      f.dropdown('Listed with', () -> LevelRegistry.instance.listSortedLevelIds(), () -> extra.week, v -> {
        extra.week = v;
        refreshEntries();
      });
      f.note('Its capsule shows that week\'s name, and it comes after that week\'s songs.');
      f.button('Remove from Freeplay', () -> removeExtra(id));
    }
    f.note('The icon, BPM and difficulties come from the chart (Chart Editor).');
  }

  function buildAlbumForm(f:QOLForm):Void
  {
    var id = selectedAlbum;
    var a = album(id);
    f.section('Album "$id"');
    if (a == null)
    {
      f.note('This album could not be read.');
      return;
    }
    f.textField('Name', () -> album(id)?.name ?? '', v -> album(id).name = v);
    f.textField('Artists', () -> {
      var list:Array<String> = album(id)?.artists;
      if (list == null) list = [];
      return list.join(', ');
    }, v -> album(id).artists = [for (s in v.split(',')) StringTools.trim(s)].filter(s -> s != ''), 'comma between names');
    f.file('Album art', () -> album(id)?.albumArtAsset ?? '', v -> album(id).albumArtAsset = v,
      cb -> browseModFile('Album art (262x262)', 'images', ['png'], cb));
    f.note('A square picture, 262x262.');
    f.file('Title', () -> album(id)?.albumTitleAsset ?? '', v -> album(id).albumTitleAsset = v,
      cb -> browseModFile('Album title', 'images', ['png'], cb));
    f.button('Make a title from the name', () -> makeAlbumTitle(id));
    f.pair('Title offset', () -> titleOffsets(id)[0], v -> titleOffsets(id)[0] = v, () -> titleOffsets(id)[1], v -> titleOffsets(id)[1] = v);
    f.textField('OST name', () -> album(id)?.albumOSTName ?? '', v -> {
      if (StringTools.trim(v) == '') Reflect.deleteField(album(id), 'albumOSTName');
      else
        album(id).albumOSTName = v;
    }, 'shown at the top right');
    f.note('The title can be a plain picture, or a sprite sheet with "idle" and "switch" animations.');
    var users = [for (e in entries) if (playData(e.song)?.album == id) songName(e.song)];
    f.section('Songs on this album');
    f.note(users.length == 0 ? 'None yet. Pick this album in a song\'s settings.' : users.join(', '));
  }

  function titleOffsets(id:String):Array<Float>
  {
    var a = album(id);
    if (a == null) return [0, 0];
    var o:Array<Float> = a.albumTitleOffsets;
    if (o == null || o.length < 2)
    {
      o = [0, 0];
      a.albumTitleOffsets = o;
    }
    return o;
  }

  //
  // Songs in Freeplay
  //

  function addExtraSong():Void
  {
    var listed = [for (e in entries) e.song];
    var ids = [for (id in SongRegistry.instance.listEntryIds()) if (!listed.contains(id)) id];
    ids.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
    if (ids.length == 0)
    {
      alert('Nothing to add', 'Every song is in Freeplay already. Make a song in the Chart Editor first.');
      return;
    }
    chooseFromList('Add a song to Freeplay', ids, id -> {
      changing();
      var levels = LevelRegistry.instance.listSortedLevelIds();
      var week = selected >= 0 && selected < entries.length ? entries[selected].week : (levels.length > 0 ? levels[levels.length - 1] : '');
      fp.extra.push({song: id, week: week});
      fp.hidden.remove(id);
      refreshEntries();
      for (i in 0...entries.length)
        if (entries[i].song == id) selected = i;
      committed();
      selectSong(selected);
    });
  }

  function removeExtra(id:String):Void
  {
    changing();
    fp.extra = fp.extra.filter(e -> e.song != id);
    var at = selected;
    refreshEntries();
    committed();
    selectSong(Std.int(Math.min(at, entries.length - 1)));
  }

  function setHidden(id:String, hidden:Bool):Void
  {
    fp.hidden.remove(id);
    if (hidden) fp.hidden.push(id);
    refreshSongList();
  }

  function toggleHidden():Void
  {
    if (selected < 0 || selected >= entries.length) return;
    changing();
    var id = entries[selected].song;
    setHidden(id, !fp.hidden.contains(id));
    committed();
    buildForm();
    queueRefresh();
  }

  //
  // Albums
  //

  function newAlbumDialog():Void
  {
    prompt('New album', 'ID (file name)', uniqueAlbumId('my-album'), v -> newAlbum(cleanId(v), null));
  }

  function uniqueAlbumId(base:String):String
  {
    var id = base;
    var n = 2;
    while (albumIds().contains(id))
      id = '$base-${n++}';
    return id;
  }

  function newAlbum(id:String, ?from:Dynamic):Void
  {
    if (albumIds().contains(id)) id = uniqueAlbumId(id);
    changing();
    var d:Dynamic = from != null ? haxe.Json.parse(haxe.Json.stringify(from)) : {
      version: '1.0.0',
      name: 'My Album',
      artists: [],
      albumArtAsset: 'freeplay/albumRoll/volume1',
      albumTitleAsset: '',
      albumTitleOffsets: [0, 0]
    };
    // Not loaded from a file: `saved` stays empty so it gets written.
    albums.set(id, d);
    saved.set('a:$id', '');
    committed();
    selectAlbum(id);
  }

  function copyAlbum():Void
  {
    if (selectedAlbum == null || album(selectedAlbum) == null) return;
    var a:Dynamic = haxe.Json.parse(haxe.Json.stringify(album(selectedAlbum)));
    a.name = '${a.name} (copy)';
    newAlbum(uniqueAlbumId(selectedAlbum + '-copy'), a);
  }

  function deleteAlbum():Void
  {
    var id = selectedAlbum;
    if (id == null) return;
    var rel = 'data/ui/freeplay/albums/$id.json';
    var inMod = ModWorkspace.hasMod && ModWorkspace.exists(rel);
    var registered = AlbumRegistry.instance.listEntryIds().contains(id);
    if (registered && !inMod)
    {
      alert('Can\'t delete', 'This album comes with the game (or another mod), so it can\'t be deleted.');
      return;
    }
    confirm('Delete', 'Delete the album "$id"?' + (inMod ? ' This removes $rel from your mod.' : ''), () -> {
      changing();
      if (inMod)
      {
        ModWorkspace.delete(rel);
        notify('Deleted', rel);
      }
      albums.set(id, DELETED);
      saved.set('a:$id', '');
      committed();
      selectedAlbum = null;
      selectSong(selected);
    });
  }

  /**
   * Draw the album's name as its title picture and save it into the mod.
   */
  function makeAlbumTitle(id:String):Void
  {
    if (!ModWorkspace.hasMod)
    {
      alert('No mod selected', 'Choose or create a mod in the Mod Menu first.');
      return;
    }
    var a = album(id);
    if (a == null) return;
    var text:String = StringTools.trim(a.name ?? '');
    if (text == '') text = id;
    var t = new FlxText(0, 0, 230, text.toUpperCase(), 40);
    t.setFormat(Paths.font('vcr.ttf'), 40, FlxColor.WHITE, CENTER, OUTLINE, 0xFF1A1A2E);
    t.borderSize = 3;
    @:privateAccess t.regenGraphic();
    var bytes = QOLIconGen.encodePNG(t.pixels);
    t.destroy();
    if (bytes == null) return;
    var key = 'freeplay/albumRoll/$id-text';
    ModWorkspace.saveBytes('images/$key.png', bytes);
    changing();
    a.albumTitleAsset = key;
    forgetImage(key);
    ModWorkspace.reloadGameData();
    shownTitle = '';
    committed();
    form.refresh();
    queueRefresh();
    notify('Title made', 'images/$key.png');
  }

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
  // Music preview
  //

  function updateTimesLabel():Void
  {
    if (timesLabel == null || selected < 0) return;
    var pd = playData(entries[selected].song, variation);
    var s:Float = pd?.previewStart ?? Constants.DEFAULT_PREVIEW_START_TIME;
    var e:Float = pd?.previewEnd ?? Constants.DEFAULT_PREVIEW_END_TIME;
    var warn = s >= e ? '  (the end must be after the start!)' : '';
    if (inst != null && instKey == previewKey() && inst.length > 0)
    {
      var len = inst.length / 1000;
      timesLabel.text = 'Plays ${time(s * len)} to ${time(e * len)} of ${time(len)}$warn';
    }
    else
      timesLabel.text = 'Plays from ${Math.round(s * 100)}% to ${Math.round(e * 100)}% of the song$warn';
  }

  static function time(sec:Float):String
  {
    var m = Std.int(sec / 60);
    var s = sec - m * 60;
    var ss = Std.string(Math.round(s * 10) / 10);
    if (s < 10) ss = '0' + ss;
    if (ss.indexOf('.') < 0) ss += '.0';
    return '$m:$ss';
  }

  function previewKey():String
    return selected < 0 ? '' : '${entries[selected].song}:$variation:$previewDifficulty';

  function togglePreviewMusic():Void
  {
    if (playingPreview) stopPreviewMusic();
    else
      playPreviewMusic();
  }

  function playPreviewMusic():Void
  {
    if (selected < 0 || selected >= entries.length) return;
    var key = previewKey();
    if (inst != null && instKey == key)
    {
      startPreviewMusic();
      return;
    }
    if (instLoading) return;
    var song = SongRegistry.instance.fetchEntry(entries[selected].song);
    if (song == null) return;
    disposeInst();
    instLoading = true;
    setStatus('Loading the music...');
    QOLSongAudio.load(song, previewDifficulty, variation, (loaded, vocals) -> {
      instLoading = false;
      vocals?.destroy();
      if (loaded == null)
      {
        setStatus('This song has no instrumental to play.');
        return;
      }
      inst = loaded;
      instKey = key;
      setStatus('');
      updateTimesLabel();
      if (previewKey() == key) startPreviewMusic();
    });
  }

  function startPreviewMusic():Void
  {
    if (inst == null || selected < 0) return;
    var pd = playData(entries[selected].song, variation);
    var s:Float = pd?.previewStart ?? Constants.DEFAULT_PREVIEW_START_TIME;
    var e:Float = pd?.previewEnd ?? Constants.DEFAULT_PREVIEW_END_TIME;
    if (s >= e || e > 1)
    {
      s = Constants.DEFAULT_PREVIEW_START_TIME;
      e = Constants.DEFAULT_PREVIEW_END_TIME;
    }
    FlxG.sound.music?.pause();
    inst.volume = 0.8;
    inst.play(true, s * inst.length, e * inst.length);
    playingPreview = true;
  }

  function stopPreviewMusic():Void
  {
    playingPreview = false;
    if (inst != null && inst.playing) inst.stop();
  }

  function disposeInst():Void
  {
    playingPreview = false;
    if (inst != null)
    {
      inst.stop();
      inst.destroy();
    }
    inst = null;
    instKey = '';
  }

  //
  // Undo / redo
  //

  function snapshot():String
  {
    var m:Dynamic = {};
    for (k in metas.keys())
      Reflect.setField(m, k, metas.get(k));
    var a:Dynamic = {};
    for (k in albums.keys())
      Reflect.setField(a, k, albums.get(k) == DELETED ? '__deleted__' : albums.get(k));
    return haxe.Json.stringify({fp: fp, metas: m, albums: a});
  }

  function changing():Void
  {
    if (snapshot() != lastSnapshot) committed();
  }

  function committed():Void
  {
    if (applyingUndo) return;
    var now = snapshot();
    if (now == lastSnapshot) return;
    undoStack.push(lastSnapshot);
    if (undoStack.length > MAX_UNDO) undoStack.shift();
    redoStack = [];
    lastSnapshot = now;
    dirty = true;
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
    fp = QOLFreeplay.parse(s.fp);
    for (k in Reflect.fields(s.metas))
      metas.set(k, Reflect.field(s.metas, k));
    for (k in Reflect.fields(s.albums))
    {
      var v:Dynamic = Reflect.field(s.albums, k);
      albums.set(k, v == '__deleted__' ? DELETED : v);
    }
    // Albums made after this point are gone.
    for (k in [for (k in albums.keys()) k])
      if (!Reflect.hasField(s.albums, k)) albums.remove(k);
    if (selectedAlbum != null && album(selectedAlbum) == null) selectedAlbum = null;
    lastSnapshot = snap;
    refreshEntries();
    refreshAlbumList();
    buildForm();
    queueRefresh();
    applyingUndo = false;
    dirty = true;
  }

  //
  // Saving
  //

  override function save():Bool
  {
    var written:Array<String> = [];
    for (key in metas.keys())
    {
      var m = metas.get(key);
      if (m == null) continue;
      var json = haxe.Json.stringify(m);
      if (json == saved.get('m:$key')) continue;
      var parts = key.split(':');
      written.push(ModWorkspace.saveJson(metaPath(parts[0], parts[1]), m, META_ORDER));
      saved.set('m:$key', json);
    }
    for (id in albums.keys())
    {
      var a = albums.get(id);
      if (a == null || a == DELETED) continue;
      var json = haxe.Json.stringify(a);
      if (json == saved.get('a:$id')) continue;
      var out:Dynamic = haxe.Json.parse(json);
      var o:Array<Float> = out.albumTitleOffsets;
      if (o != null && o.length >= 2 && o[0] == 0 && o[1] == 0) Reflect.deleteField(out, 'albumTitleOffsets');
      written.push(ModWorkspace.saveJson('data/ui/freeplay/albums/$id.json', out, ALBUM_ORDER));
      saved.set('a:$id', json);
    }
    var fpJson = haxe.Json.stringify(fp);
    if (fpJson != saved.get('fp'))
    {
      written.push(ModWorkspace.saveJson('data/${QOLFreeplay.PATH}.json', fp));
      saved.set('fp', fpJson);
    }
    if (written.length == 0) notify('Saved', 'Nothing had changed.');
    else if (written.length == 1) notifySaved(written[0]);
    else
      notify('Saved', '${written.length} files: ' + [for (w in written) haxe.io.Path.withoutDirectory(w)].join(', '));
    return true;
  }

  override function afterSaveReload():Void
  {
    stopPreviewMusic();
    ModWorkspace.reloadGameData();
    shownArt = '';
    shownTitle = '';
    refreshEntries();
    refreshAlbumList();
    queueRefresh();
  }

  //
  // Preview
  //

  function queueRefresh():Void
    refreshQueued = true;

  function queueScene():Void
    sceneQueued = true;

  function addScene<T:FlxSprite>(s:T):T
  {
    s.cameras = [camPreview];
    add(s);
    sceneItems.push(s);
    return s;
  }

  /**
   * The parts of Freeplay that don't change with the song: the backing card, the background and the capsules.
   */
  function buildScene():Void
  {
    // Backing card (the pink card the DJ stands on).
    try
    {
      var pink = new FunkinSprite(0, 0).loadGraphic(Paths.image('freeplay/pinkBack'));
      pink.color = 0xFFFFD4E9;
      addScene(pink);
      addScene(new FunkinSprite(84, 440).makeSolidColor(Std.int(pink.width), 75, 0xFFFEDA00));
      addScene(new FunkinSprite(0, 440).makeSolidColor(100, 75, 0xFFFFD400));
      var style = FreeplayStyleRegistry.instance.fetchEntry(styleId);
      var bgKey = style != null ? style.getBgAssetKey() : 'freeplay/freeplayBGweek1-bf';
      var bg = FunkinSprite.create(pink.width * 0.74, 0, bgKey);
      bg.setGraphicSize(0, FlxG.height + 1);
      bg.updateHitbox();
      addScene(bg);
    }
    catch (e:Dynamic)
    {
      setStatus('Preview: $e');
    }
    var title = new FlxText(8, 8, 0, 'FREEPLAY', 48);
    title.font = 'VCR OSD Mono';
    addScene(title);
    ostText = new FlxText(8, 8, FlxG.width - 16, Constants.DEFAULT_OST_NAME, 48);
    ostText.font = 'VCR OSD Mono';
    ostText.alignment = RIGHT;
    addScene(ostText);

    // The difficulty and the album.
    stars = new DifficultyStars(FlxG.width - 330, 209);
    stars.cameras = [camPreview];
    add(stars);
    try
    {
      art = FunkinSprite.createTextureAtlas(FlxG.width - 360, 220, 'freeplay/albumRoll/freeplayAlbum');
      art.cameras = [camPreview];
      art.visible = false;
      add(art);
    }
    catch (e:Dynamic)
    {
      art = null;
    }

    // The capsules (made once and reused: they run timers that mustn't outlive them).
    var style = FreeplayStyleRegistry.instance.fetchEntry(styleId);
    for (i in 0...CAPSULES)
    {
      var item = new SongMenuItem(0, 0);
      item.cameras = [camPreview];
      item.initData(null, style, i);
      item.forcePosition();
      add(item);
      capsules.push(item);
      capsuleEntry.push(-1);
    }
  }

  function clearScene():Void
  {
    for (s in sceneItems)
    {
      remove(s, true);
      s.destroy();
    }
    sceneItems = [];
    for (c in capsules)
    {
      c.visible = false;
      remove(c, true);
    }
    if (stars != null) remove(stars, true);
    if (art != null) remove(art, true);
    if (albumTitle != null) remove(albumTitle, true);
    if (diffSprite != null) remove(diffSprite, true);
  }

  /**
   * A new style: the background and the capsule art change, so the scene is made again (the old capsules are hidden,
   * not destroyed).
   */
  function rebuildScene():Void
  {
    clearScene();
    capsules = [];
    capsuleEntry = [];
    stars = null;
    art = null;
    albumTitle = null;
    diffSprite = null;
    shownArt = '';
    shownTitle = '';
    buildScene();
    queueRefresh();
  }

  /**
   * Show the selected song (and its neighbours) the way Freeplay would.
   */
  function refreshPreview():Void
  {
    refreshQueued = false;
    var visible = [for (i in 0...entries.length) if (!fp.hidden.contains(entries[i].song) || i == selected) i];
    var center = visible.indexOf(selected);
    for (slot in 0...capsules.length)
    {
      var item = capsules[slot];
      var vi = center < 0 ? -1 : center - CAPSULES_ABOVE + slot;
      var entryIndex = vi >= 0 && vi < visible.length ? visible[vi] : -1;
      capsuleEntry[slot] = entryIndex;
      if (entryIndex < 0)
      {
        item.visible = false;
        continue;
      }
      item.visible = true;
      showCapsule(item, entries[entryIndex], slot - CAPSULES_ABOVE, entryIndex == selected);
    }

    // The difficulty above the capsules.
    if (diffSprite != null)
    {
      remove(diffSprite, true);
      diffSprite.destroy();
      diffSprite = null;
    }
    var diffId = Assets.exists(Paths.image('freeplay/freeplay$previewDifficulty')) ? previewDifficulty : 'normal';
    diffSprite = new DifficultySprite(diffId);
    diffSprite.setPosition(90, 80);
    diffSprite.cameras = [camPreview];
    add(diffSprite);

    // The album and the stars.
    var albumId:Null<String> = selectedAlbum;
    var song = selected >= 0 && selected < entries.length ? entries[selected].song : null;
    if (albumId == null && song != null) albumId = playData(song, variation)?.album;
    var a = album(albumId);
    showAlbum(a);
    if (stars != null)
    {
      stars.visible = song != null;
      if (song != null) stars.difficulty = ratingOf(song, variation, previewDifficulty);
    }

    if (previewTitle != null)
    {
      previewTitle.text = selectedAlbum != null ? 'Freeplay preview  ·  album "$selectedAlbum"' : (song == null ? 'Freeplay preview' : 'Freeplay preview  ·  ${songName(song)}  ·  $previewDifficulty');
    }
  }

  function showCapsule(item:SongMenuItem, e:QOLFreeplayExtra, offset:Int, isSelected:Bool):Void
  {
    var id = e.song;
    var useVariation = isSelected ? variation : Constants.DEFAULT_VARIATION;
    var m = meta(id, useVariation) ?? meta(id);
    item.targetPos.set(item.intendedX(offset), item.intendedY(offset));
    item.x = item.targetPos.x;
    item.y = item.targetPos.y;
    item.alpha = fp.hidden.contains(id) ? 0.35 : 1;
    @:privateAccess
    {
      item.songText.text = m?.songName ?? id;
      var opponent:String = m?.playData?.characters?.opponent ?? '';
      if (opponent != '')
      {
        item.pixelIcon.setCharacter(opponent);
        item.pixelIcon.visible = item.pixelIcon.char == opponent;
      }
      else
        item.pixelIcon.visible = false;
      var changes:Array<Dynamic> = m?.timeChanges ?? [];
      item.updateBPM(changes.length > 0 ? Std.int(changes[0].bpm ?? 0) : 0);
      item.updateDifficultyRating(ratingOf(id, useVariation, previewDifficulty));
      item.newText.visible = false;
      var label = weekLabel(e.week);
      item.createWeekTextGraphic(label);
      item.weekText.loadGraphic(FlxG.bitmap.get(label));
      item.weekText.visible = true;
      var level = LevelRegistry.instance.fetchEntry(e.week);
      var offs = level?.getCapsuleTitleOffsets() ?? [0.0, 0.0];
      item.weekText.offset.set(offs[0], offs[1]);
      for (r in [item.ranking, item.blurredRanking, item.fakeRanking, item.fakeBlurredRanking])
        r.visible = false;
      item.favIcon.visible = item.favIconBlurred.visible = item.sparkle.visible = false;
    }
    item.selected = isSelected;
    item.checkClip();
  }

  function showAlbum(a:Dynamic):Void
  {
    if (ostText != null)
    {
      var ost:String = a?.albumOSTName ?? '';
      ostText.text = ost == '' ? Constants.DEFAULT_OST_NAME : ost;
    }
    var artKey:String = a?.albumArtAsset ?? '';
    if (art != null)
    {
      if (a == null || artKey == '' || !Assets.exists(Paths.image(artKey))) art.visible = false;
      else
      {
        art.visible = true;
        if (artKey != shownArt)
        {
          shownArt = artKey;
          try
          {
            art.replaceSymbolGraphic(ART_SYMBOL, Paths.image(artKey));
            art.anim.play('switch', true);
          }
          catch (e:Dynamic) {}
        }
      }
    }
    var titleKey:String = a?.albumTitleAsset ?? '';
    var offs:Array<Float> = a?.albumTitleOffsets;
    if (offs == null || offs.length < 2) offs = [0.0, 0.0];
    var titleId = '$titleKey|${offs.join(',')}';
    if (titleId != shownTitle || (a == null) != (albumTitle == null))
    {
      shownTitle = titleId;
      if (albumTitle != null)
      {
        remove(albumTitle, true);
        albumTitle.destroy();
        albumTitle = null;
      }
      if (a != null && titleKey != '' && Assets.exists(Paths.image(titleKey)))
      {
        var t = new FunkinSprite(FlxG.width - 355, 500);
        if (Assets.exists(Paths.file('images/$titleKey.xml')))
        {
          t.loadSparrow(titleKey);
          t.animation.addByPrefix('idle', 'idle0', 24, true);
          t.animation.addByPrefix('switch', 'switch0', 24, false);
          t.animation.onFinish.add(name -> if (name == 'switch') t.animation.play('idle'));
          t.animation.play('switch');
        }
        else
          t.loadGraphic(Paths.image(titleKey));
        t.x += offs[0];
        t.y += offs[1];
        t.cameras = [camPreview];
        add(t);
        albumTitle = t;
      }
    }
  }

  override public function update(elapsed:Float):Void
  {
    super.update(elapsed);
    if (sceneQueued)
    {
      sceneQueued = false;
      queueRefresh();
    }
    if (refreshQueued) refreshPreview();

    // Loop the music preview like Freeplay does.
    if (playingPreview && inst != null && !inst.playing) startPreviewMusic();

    // Click a capsule to pick it, scroll the wheel to move through the list.
    if (!mouseOverUI && !dialogOpen && mouseInPreview())
    {
      if (FlxG.mouse.wheel != 0) moveSelection(FlxG.mouse.wheel > 0 ? -1 : 1);
      if (FlxG.mouse.justPressed)
      {
        var pm = previewMouse();
        for (slot in 0...capsules.length)
        {
          var item = capsules[slot];
          if (!item.visible || capsuleEntry[slot] < 0 || capsuleEntry[slot] == selected) continue;
          var r = item.capsule.getScreenBounds(null, camPreview);
          var hit = r.containsXY(pm[0], pm[1]);
          r.put();
          if (hit)
          {
            selectSong(capsuleEntry[slot]);
            break;
          }
        }
      }
    }
  }

  override function handleShortcuts():Void
  {
    if (ctrl())
    {
      if (FlxG.keys.justPressed.Z) undo();
      if (FlxG.keys.justPressed.Y) redo();
      return;
    }
    if (FlxG.keys.justPressed.SPACE) togglePreviewMusic();
    if (FlxG.keys.justPressed.UP) moveSelection(-1);
    if (FlxG.keys.justPressed.DOWN) moveSelection(1);
  }

  override public function destroy():Void
  {
    disposeInst();
    if (FlxG.sound.music != null && !FlxG.sound.music.playing) FlxG.sound.music.resume();
    previewDisplay?.destroy();
    super.destroy();
  }
}
#end
