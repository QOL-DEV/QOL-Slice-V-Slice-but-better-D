package funkin.qol.editors;

#if FEATURE_HAXEUI
import flixel.FlxSprite;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.audio.VoicesGroup;
import funkin.data.song.SongRegistry;
import funkin.play.song.Song;
import funkin.play.song.Song.SongDifficulty;
import funkin.qol.editors.modchart.ModchartDoc;
import funkin.qol.editors.modchart.ModchartDoc.ModKeyRef;
import funkin.qol.editors.modchart.ModchartPreview;
import funkin.qol.editors.modchart.ModchartTimeline;
import funkin.qol.runtime.QOLModchart;
import funkin.qol.runtime.QOLModchart.QOLModchartData;
import funkin.qol.runtime.QOLModchart.QOLModchartRuntime;
import funkin.qol.runtime.QOLModchart.QOLModHost;
import funkin.qol.runtime.QOLModchart.QOLModKey;
import funkin.qol.runtime.QOLModchart.QOLModTrack;
import funkin.qol.runtime.QOLPlayHooks;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.ui.QOLTheme;
import funkin.qol.util.QOLJson;
import funkin.qol.util.QOLSongAudio;
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.containers.TabView;
import haxe.ui.containers.VBox;
import haxe.ui.data.ArrayDataSource;

/**
 * The QOL Slice Modchart Editor.
 *
 * Works like an animator: a live gameplay preview on top (the real strumlines with the song's notes, the HUD, the stage
 * and characters), and a timeline with a row for every UI element (strumlines, each arrow, cameras, health bar, icons,
 * score, characters, stage props). Every modchart feature is a track of keyframes; each key picks how it eases in (every
 * ease type, with the Ease Picker). Drag things in the preview to auto-key their position.
 *
 * Saves `data/qol/modcharts/<song>.json` in the active mod; gameplay plays it automatically.
 */
class ModchartEditorState extends QOLEditorState
{
  static final PREVIEW_X:Float = 10;
  static final PREVIEW_Y:Float = 40;
  static final PREVIEW_SCALE:Float = 0.5;
  static final PANEL_X:Float = 666;
  static final TRANSPORT_Y:Float = 408;
  static final TIMELINE_Y:Float = 438;

  public static final SNAPS:Array<Float> = [1, 1 / 2, 1 / 3, 1 / 4, 1 / 6, 1 / 8, 1 / 12, 1 / 16];
  static final SNAP_LABELS:Array<String> = ['1 beat', '1/2 beat', '1/3 beat', '1/4 beat', '1/6 beat', '1/8 beat', '1/12 beat', '1/16 beat'];

  public var doc:ModchartDoc;
  public var preview:ModchartPreview;
  public var timeline:ModchartTimeline;

  var runtime:Null<QOLModchartRuntime> = null;

  public var song:Null<Song> = null;
  public var songId:String = '';
  public var difficulty:String = 'normal';
  public var variation:String = Constants.DEFAULT_VARIATION;

  var diffData:Null<SongDifficulty> = null;
  var savePath:String = '';

  /**
   * Playhead, in beats.
   */
  public var beat:Float = 0;

  public var songPosition:Float = 0;
  public var snapBeats:Float = 0.25;
  public var beatsPerMeasure:Int = 4;
  public var noteBeats:Array<{b:Float, s:Int}> = [];

  var songLength:Float = 60000;
  var playing:Bool = false;
  var playbackRate:Float = 1;
  var musicVolume:Float = 1;
  var showStage:Bool = true;
  var inst:Null<FunkinSound> = null;
  var vocals:Null<VoicesGroup> = null;
  var audioToken:Int = 0;

  // Selection.
  public var selKeys:Array<ModKeyRef> = [];
  public var selTrack:Null<QOLModTrack> = null;
  public var selTarget:Null<String> = null;

  var clipboard:Array<{target:String, prop:String, dt:Float, v:Float, ?e:String}> = [];

  // UI.
  var tabs:TabView;
  var inspectorBox:VBox;
  var inspectorForm:Null<QOLForm> = null;
  var inspectorBefore:String = '';
  var libTargets:ListView;
  var libProps:ListView;
  var libDesc:Label;
  var libTargetIds:Array<String> = [];
  var libPropIds:Array<String> = [];
  var songForm:QOLForm;
  var playButton:Button;
  var timeLabel:Label;
  var outline:Array<FlxSprite> = [];

  var previewDrag:Null<
    {
      target:String,
      hx:Float,
      hy:Float,
      x0:Float,
      y0:Float,
      before:String,
      scale:Float,
      moved:Bool
    }> = null;

  var startSong:Null<String>;

  public function new(?songId:String)
  {
    super();
    editorName = 'Modchart Editor';
    leftPanelWidth = 0;
    rightPanelWidth = 0;
    startSong = songId;
  }

  override function guidePage():String
    return 'modchart';

  //
  // Setup
  //

  override function buildEditor():Void
  {
    camWorld.bgColor = 0xFF121218;
    gridBG.alpha = 0.25;

    preview = new ModchartPreview(this, PREVIEW_X, PREVIEW_Y, PREVIEW_SCALE);
    // Camera order: editor background, preview game, preview HUD, editor UI.
    FlxG.cameras.remove(camUI, false);
    FlxG.cameras.add(preview.camGame, false);
    FlxG.cameras.add(preview.camHUD, false);
    FlxG.cameras.add(camUI, false);

    var frame = QOLTheme.roundRect(Std.int(FlxG.width * PREVIEW_SCALE + 10), Std.int(FlxG.height * PREVIEW_SCALE + 10), 0xFF08080C, 8, 0xFF5A4F80, 2);
    frame.setPosition(PREVIEW_X - 5, PREVIEW_Y - 5);
    frame.cameras = [camWorld];
    frame.scrollFactor.set();
    add(frame);

    for (i in 0...4)
    {
      var s = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
      s.color = QOLTheme.ACCENT_YELLOW;
      s.cameras = [camUI];
      s.scrollFactor.set();
      s.visible = false;
      outline.push(s);
      add(s);
    }

    doc = new ModchartDoc(QOLModchart.empty());
    doc.onChange = onDocChanged;

    timeline = new ModchartTimeline(this, camUI, 0, TIMELINE_Y, FlxG.width, FlxG.height - TIMELINE_Y - QOLEditorState.STATUSBAR_HEIGHT);
    add(timeline);
    timeline.addOverlays();

    buildMenus();
    buildPanel();
    buildTransport();

    loadSong(startSong ?? QOLConfig.getPref('modchartEditor.last', null) ?? defaultSong());
  }

  function defaultSong():String
  {
    if (ModWorkspace.hasMod)
    {
      for (dir in ModWorkspace.list('data/songs'))
        if (SongRegistry.instance.hasEntry(dir)) return dir;
    }
    if (SongRegistry.instance.hasEntry('bopeebo')) return 'bopeebo';
    return SongRegistry.instance.listEntryIds()[0] ?? 'tutorial';
  }

  function buildMenus():Void
  {
    var file = addMenu('File');
    addMenuItem(file, 'Open Song...', 'Ctrl+O', () -> {
      var ids = SongRegistry.instance.listEntryIds();
      ids.sort((a, b) -> a < b ? -1 : 1);
      chooseFromList('Open song', ids, id -> loadSong(id), songId);
    });
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuSeparator(file);
    addMenuItem(file, 'Insert Example Modchart', null, insertExample);
    addMenuItem(file, 'Clear Whole Modchart', null, () -> confirm('Clear modchart', 'Remove every track from this modchart?', () -> {
      doc.checkpoint();
      doc.data.tracks = [];
      clearSelection(false);
      doc.changed();
    }));

    var edit = addMenu('Edit');
    addMenuItem(edit, 'Undo', 'Ctrl+Z', undo);
    addMenuItem(edit, 'Redo', 'Ctrl+Y', redo);
    addMenuSeparator(edit);
    addMenuItem(edit, 'Copy Keys', 'Ctrl+C', copyKeys);
    addMenuItem(edit, 'Paste Keys at Playhead', 'Ctrl+V', pasteKeys);
    addMenuItem(edit, 'Delete Selected Keys', 'Delete', () -> deleteKeys(selKeys.copy()));
    addMenuItem(edit, 'Select All Keys', 'Ctrl+A', selectAllKeys);
    addMenuSeparator(edit);
    addMenuItem(edit, 'Add Key at Playhead', 'K', addKeyOnSelected);

    var play = addMenu('Playback');
    addMenuItem(play, 'Play / Pause', 'Space', togglePlay);
    addMenuItem(play, 'Playtest From Here', 'Enter', () -> playtest(true));
    addMenuItem(play, 'Playtest From Start', 'Shift+Enter', () -> playtest(false));
    addMenuItem(play, 'Go to Start', 'Home', () -> seekBeat(0));

    var view = addMenu('View');
    addMenuCheck(view, 'Show Stage & Characters', showStage, v -> {
      showStage = v;
      rebuildPreview();
    });
    addMenuItem(view, 'Zoom Timeline In', 'Ctrl+Wheel', () -> timeline.pxPerBeat = Math.min(480, timeline.pxPerBeat * 1.25));
    addMenuItem(view, 'Zoom Timeline Out', 'Ctrl+Wheel', () -> timeline.pxPerBeat = Math.max(4, timeline.pxPerBeat / 1.25));
  }

  function buildPanel():Void
  {
    tabs = new TabView();
    tabs.left = PANEL_X;
    tabs.top = QOLEditorState.MENUBAR_HEIGHT + 4;
    tabs.width = FlxG.width - PANEL_X - 8;
    tabs.height = TRANSPORT_Y - QOLEditorState.MENUBAR_HEIGHT - 10;
    root.addComponent(tabs);

    // Inspector.
    var inspPage = new VBox();
    inspPage.text = 'Inspector';
    inspPage.styleString = 'padding: 6px;';
    tabs.addComponent(inspPage);
    var scroll = new haxe.ui.containers.ScrollView();
    scroll.width = tabs.width - 16;
    scroll.height = tabs.height - 44;
    scroll.horizontalScrollPolicy = 'never';
    inspPage.addComponent(scroll);
    inspectorBox = new VBox();
    inspectorBox.width = tabs.width - 40;
    inspectorBox.styleString = 'spacing: 4px;';
    scroll.addComponent(inspectorBox);

    // Library: every target and every modchart feature.
    var libPage = new VBox();
    libPage.text = 'Add Track';
    libPage.styleString = 'padding: 6px; spacing: 6px;';
    tabs.addComponent(libPage);
    var row = new HBox();
    row.styleString = 'spacing: 8px;';
    libPage.addComponent(row);
    var listH = tabs.height - 120;
    var colW = (tabs.width - 40) / 2;
    var left = new VBox();
    left.addComponent(smallLabel('1. Pick what to animate'));
    libTargets = new ListView();
    libTargets.width = colW;
    libTargets.height = listH;
    libTargets.onChange = _ -> {
      if (syncingLibrary) return;
      var i = libTargets.selectedIndex;
      if (i >= 0 && i < libTargetIds.length && libTargetIds[i] != '')
      {
        selectTarget(libTargetIds[i], false);
        refreshLibraryProps();
      }
    };
    left.addComponent(libTargets);
    row.addComponent(left);
    var right = new VBox();
    right.addComponent(smallLabel('2. Pick a modchart feature'));
    libProps = new ListView();
    libProps.width = colW;
    libProps.height = listH;
    libProps.onChange = _ -> refreshLibraryDesc();
    libProps.onDblClick = _ -> addTrackFromLibrary();
    right.addComponent(libProps);
    row.addComponent(right);
    libDesc = new Label();
    libDesc.width = tabs.width - 30;
    libDesc.styleString = 'color: #C9C2E6; font-size: 12px;';
    libPage.addComponent(libDesc);
    var addBtn = new Button();
    addBtn.text = '+ Add Track (adds a key at the playhead)';
    addBtn.onClick = _ -> addTrackFromLibrary();
    libPage.addComponent(addBtn);

    tabs.onChange = _ -> if (tabs.pageIndex == 1) syncLibrary();

    // Song.
    var songPage = new VBox();
    songPage.text = 'Song';
    songPage.styleString = 'padding: 6px;';
    tabs.addComponent(songPage);
    songForm = new QOLForm(130, 240);
    songForm.section('Song');
    songForm.dropdown('Song', () -> {
      var ids = SongRegistry.instance.listEntryIds();
      ids.sort((a, b) -> a < b ? -1 : 1);
      return ids;
    }, () -> songId, v -> if (v != songId) loadSong(v));
    songForm.dropdown('Variation', () -> song?.variations ?? [variation], () -> variation, v -> if (v != variation) loadSong(songId, null, v));
    songForm.dropdown('Difficulty', () -> song?.listDifficulties(variation, null, true, true) ?? [difficulty], () -> difficulty,
      v -> if (v != difficulty) loadSong(songId, v, variation));
    songForm.note('The modchart is shared by every difficulty of the song (a variation can have its own).');
    songForm.section('Preview');
    songForm.check('Show stage & characters', () -> showStage, v -> {
      showStage = v;
      rebuildPreview();
    });
    songForm.slider('Playback speed', () -> playbackRate, v -> {
      playbackRate = Math.round(v * 20) / 20;
      applyVolumes();
    }, 0.25, 2, 0.05);
    songForm.slider('Music volume', () -> musicVolume, v -> {
      musicVolume = v;
      applyVolumes();
    }, 0, 1, 0.05);
    songForm.dropdown('Snap', () -> [for (s in SNAPS) '$s'], () -> '$snapBeats', v -> snapBeats = Std.parseFloat(v), () -> SNAP_LABELS);
    songForm.buttons([
      {text: 'Reload preview', cb: rebuildPreview},
      {text: 'Playtest (Enter)', cb: () -> playtest(true)}
    ]);
    songForm.note('Uses your downscroll setting. Notes are played by the CPU in the preview.');
    songPage.addComponent(songForm);
  }

  function smallLabel(text:String):Label
  {
    var l = new Label();
    l.text = text;
    l.styleString = 'color: #FF8FB8; font-bold: true;';
    return l;
  }

  function buildTransport():Void
  {
    var bar = new HBox();
    bar.left = PREVIEW_X;
    bar.top = TRANSPORT_Y;
    bar.width = FlxG.width - PREVIEW_X * 2;
    bar.styleString = 'spacing: 6px;';
    root.addComponent(bar);

    bar.addComponent(transportButton('|<', 'Go to start (Home)', () -> seekBeat(0)));
    bar.addComponent(transportButton('<', 'Back one snap (Left)', () -> seekBeat(Math.max(0, snap(beat) - snapBeats))));
    playButton = transportButton('Play', 'Play / pause (Space)', togglePlay);
    playButton.width = 70;
    bar.addComponent(playButton);
    bar.addComponent(transportButton('>', 'Forward one snap (Right)', () -> seekBeat(snap(beat) + snapBeats)));
    timeLabel = new Label();
    timeLabel.width = 330;
    timeLabel.styleString = 'color: #9FE8FF; font-size: 13px; padding-top: 4px;';
    bar.addComponent(timeLabel);
    bar.addComponent(transportButton('Add Key (K)', 'Add a key at the playhead on the selected track', addKeyOnSelected));
    bar.addComponent(transportButton('- Zoom', 'Zoom the timeline out', () -> timeline.pxPerBeat = Math.max(4, timeline.pxPerBeat / 1.25)));
    bar.addComponent(transportButton('+ Zoom', 'Zoom the timeline in', () -> timeline.pxPerBeat = Math.min(480, timeline.pxPerBeat * 1.25)));
    bar.addComponent(transportButton('Playtest', 'Play the song with this modchart (Enter)', () -> playtest(true)));
  }

  function transportButton(text:String, tooltip:String, cb:Void->Void):Button
  {
    var b = new Button();
    b.text = text;
    b.tooltip = tooltip;
    b.onClick = _ -> cb();
    return b;
  }

  //
  // Loading
  //

  function loadSong(id:String, ?diff:String, ?vari:String):Void
  {
    var s = SongRegistry.instance.fetchEntry(id);
    if (s == null)
    {
      alert('Song not found', 'There is no song with the ID "$id".');
      return;
    }
    stopAudio();
    song = s;
    songId = id;
    try
    {
      s.cacheCharts(true);
    }
    catch (e)
    {
      trace('[QOL] cacheCharts failed: $e');
    }
    var vars = s.variations;
    variation = vari ?? (vars.contains(variation) ? variation : (vars[0] ?? Constants.DEFAULT_VARIATION));
    var diffs = s.listDifficulties(variation, null, true, true);
    difficulty = diff ?? (diffs.contains(difficulty) ? difficulty : (diffs.contains('normal') ? 'normal' : (diffs[0] ?? 'normal')));
    diffData = s.getDifficulty(difficulty, variation);
    if (diffData == null)
    {
      alert('Can\'t load chart', 'Song "$id" has no "$difficulty" chart for the "$variation" variation.');
      return;
    }

    Conductor.instance.mapTimeChanges(diffData.timeChanges);
    beatsPerMeasure = diffData.timeChanges[0]?.timeSignatureNum ?? 4;
    noteBeats = [
      for (n in diffData.notes)
        {b: Conductor.instance.getTimeInSteps(n.time) / Constants.STEPS_PER_BEAT, s: n.getStrumlineIndex()}
    ];
    noteBeats.sort((a, b) -> a.b < b.b ? -1 : (a.b > b.b ? 1 : 0));

    doc = new ModchartDoc(loadModchartData());
    doc.onChange = onDocChanged;
    clearSelection(false);

    rebuildPreview();
    seekBeat(0);
    loadAudio();

    QOLConfig.setPref('modchartEditor.last', id);
    songForm.refresh();
    refreshLibraryTargets();
    rebuildInspector();
    dirty = false;
    updateWindowTitle();
    setStatus('Editing the modchart for $id ($difficulty). It saves to ${savePath}.');
  }

  function loadModchartData():QOLModchartData
  {
    var specific = 'data/qol/modcharts/${QOLModchart.fileId(songId, variation)}.json';
    var shared = 'data/qol/modcharts/$songId.json';
    savePath = specific;
    if (ModWorkspace.hasMod)
    {
      for (rel in [specific, shared])
      {
        if (!ModWorkspace.exists(rel)) continue;
        var parsed:Null<QOLModchartData> = QOLJson.tryParse(ModWorkspace.getText(rel));
        if (parsed != null)
        {
          savePath = rel;
          return QOLModchart.normalize(parsed);
        }
      }
    }
    var data = QOLModchart.load(songId, variation);
    return data ?? QOLModchart.empty(songId);
  }

  function rebuildPreview():Void
  {
    if (song == null || diffData == null) return;
    runtime?.destroy();
    runtime = null;
    preview.build(song, diffData, showStage, QOLPlayHooks.loadSongData(songId).strumlines ?? [], () -> timeline.rebuildRows());
    runtime = new QOLModchartRuntime(doc.data, preview.host);
    timeline.rebuildRows();
    refreshLibraryTargets();
  }

  function loadAudio():Void
  {
    stopAudio();
    if (song == null) return;
    var token = ++audioToken;
    QOLSongAudio.load(song, difficulty, variation, (i, v) -> {
      if (token != audioToken || destroyed)
      {
        i?.destroy();
        v?.destroy();
        return;
      }
      inst = i;
      vocals = v;
      songLength = inst != null && inst.length > 0 ? inst.length : Math.max(60000, Conductor.instance.getStepTimeInMs((noteBeats.length > 0 ? noteBeats[noteBeats.length - 1].b : 0) * 4) + 8000);
      applyVolumes();
    });
  }

  var destroyed:Bool = false;

  function stopAudio():Void
  {
    playing = false;
    if (playButton != null) playButton.text = 'Play';
    if (inst != null)
    {
      inst.stop();
      inst.destroy();
      inst = null;
    }
    if (vocals != null)
    {
      vocals.stop();
      vocals.destroy();
      vocals = null;
    }
  }

  function applyVolumes():Void
  {
    if (inst != null)
    {
      inst.volume = musicVolume;
      inst.pitch = playbackRate;
    }
    if (vocals != null)
    {
      vocals.volume = musicVolume;
      vocals.pitch = playbackRate;
    }
  }

  //
  // Saving
  //

  override function save():Bool
  {
    var path = ModWorkspace.saveJson(savePath, doc.data, ['version', 'song', 'tracks', 'target', 'prop', 'muted', 'keys', 't', 'v', 'e']);
    notifySaved(path);
    return true;
  }

  //
  // Document changes
  //

  function onDocChanged():Void
  {
    runtime?.setData(doc.data);
    // Drop selections that no longer exist (after undo, deleting a track...).
    selKeys = [for (s in selKeys) if (doc.data.tracks.contains(s.track) && s.track.keys.contains(s.key)) s];
    if (selTrack != null && !doc.data.tracks.contains(selTrack)) selTrack = null;
    timeline.rebuildRows();
    dirty = true;
    updateWindowTitle();
    rebuildInspector();
  }

  /**
   * Live update while dragging (no undo step yet).
   */
  public function liveEdit():Void
  {
    runtime?.setData(doc.data);
    dirty = true;
    inspectorForm?.refresh();
  }

  /**
   * Finish an edit made directly on the data.
   */
  public function afterEdit():Void
    doc.changed();

  function undo():Void
  {
    if (doc.undo())
    {
      clearSelection(false);
      setStatus('Undone.');
    }
  }

  function redo():Void
  {
    if (doc.redo())
    {
      clearSelection(false);
      setStatus('Redone.');
    }
  }

  //
  // Selection (used by the timeline)
  //

  public function isKeySelected(key:QOLModKey):Bool
  {
    for (s in selKeys)
      if (s.key == key) return true;
    return false;
  }

  public function selectKeys(keys:Array<ModKeyRef>, add:Bool):Void
  {
    if (!add) selKeys = [];
    for (k in keys)
      if (!isKeySelected(k.key)) selKeys.push(k);
    if (keys.length > 0)
    {
      selTrack = keys[keys.length - 1].track;
      selTarget = selTrack.target;
    }
    rebuildInspector();
  }

  public function toggleKey(k:ModKeyRef):Void
  {
    for (s in selKeys)
    {
      if (s.key == k.key)
      {
        selKeys.remove(s);
        rebuildInspector();
        return;
      }
    }
    selectKeys([k], true);
  }

  public function clearSelection(rebuild:Bool = true):Void
  {
    selKeys = [];
    selTrack = null;
    selTarget = null;
    if (rebuild) rebuildInspector();
  }

  public function selectTrack(track:QOLModTrack):Void
  {
    selKeys = [];
    selTrack = track;
    selTarget = track.target;
    rebuildInspector();
  }

  public function selectTarget(target:String, reveal:Bool = true):Void
  {
    selKeys = [];
    selTrack = null;
    selTarget = target;
    if (reveal) timeline.reveal(target);
    rebuildInspector();
    if (tabs != null && tabs.pageIndex == 1 && reveal) syncLibrary();
  }

  //
  // Editing
  //

  public function snap(b:Float):Float
    return Math.round(b / snapBeats) * snapBeats;

  public function seekBeat(b:Float):Void
  {
    beat = Math.max(0, b);
    songPosition = Conductor.instance.getStepTimeInMs(beat * Constants.STEPS_PER_BEAT);
    if (inst != null) inst.time = songPosition;
    if (vocals != null) vocals.time = songPosition;
    inspectorForm?.refresh();
  }

  public function deleteKeys(keys:Array<ModKeyRef>):Void
  {
    if (keys.length == 0) return;
    doc.checkpoint();
    for (k in keys)
      doc.removeKey(k.track, k.key);
    selKeys = [];
    afterEdit();
    setStatus('Deleted ${keys.length} key${keys.length == 1 ? '' : 's'}.');
  }

  public function addKeyAt(track:QOLModTrack, b:Float):Void
  {
    doc.checkpoint();
    var value = QOLModchart.sample(track, b, QOLModchart.neutralOf(track.target, track.prop));
    var key = doc.setKey(track, b, value);
    selKeys = [{track: track, key: key}];
    selTrack = track;
    selTarget = track.target;
    afterEdit();
  }

  function addKeyOnSelected():Void
  {
    if (selTrack != null) addKeyAt(selTrack, snap(beat));
    else
      setStatus('Select a track first (click its name in the timeline), or add one from the Add Track tab.');
  }

  /**
   * Add a track for a target (with a first key at the playhead) and select it.
   */
  public function addTrack(target:String, prop:String):Void
  {
    var existing = doc.findTrack(target, prop);
    if (existing != null)
    {
      timeline.reveal(target);
      selectTrack(existing);
      return;
    }
    doc.checkpoint();
    var track = doc.addTrack(target, prop);
    var key = doc.setKey(track, snap(beat), QOLModchart.neutralOf(target, prop));
    timeline.reveal(target);
    selKeys = [{track: track, key: key}];
    selTrack = track;
    selTarget = target;
    afterEdit();
    timeline.reveal(target);
    var name = QOLModchart.getProp(prop, QOLModchart.targetKind(target))?.name ?? prop;
    setStatus('Added "$name" to ${QOLModchart.targetName(target)}. Set the value of its key in the Inspector, then add more keys (K).');
  }

  /**
   * Set a value at the playhead (updates the key there or adds one).
   */
  public function autoKey(target:String, prop:String, value:Float, live:Bool = false):Void
  {
    var track = doc.findTrack(target, prop) ?? doc.addTrack(target, prop);
    var key = doc.setKey(track, snap(beat), value);
    if (!live)
    {
      selKeys = [{track: track, key: key}];
      selTrack = track;
      selTarget = target;
    }
  }

  public function addPropertyMenu(target:String):Void
  {
    var kind = QOLModchart.targetKind(target);
    var props = QOLModchart.propsFor(kind);
    var labels = [for (p in props) '${p.group} · ${p.name}${doc.findTrack(target, p.id) != null ? '  (already added)' : ''}'];
    chooseFromList('Animate ${QOLModchart.targetName(target)}', labels, label -> {
      var i = labels.indexOf(label);
      if (i >= 0) addTrack(target, props[i].id);
    });
  }

  public function trackMenu(track:QOLModTrack):Void
  {
    var options = [
      'Add key at playhead',
      track.muted == true ? 'Unmute track' : 'Mute track',
      'Select all keys',
      'Delete track'
    ];
    chooseFromList(QOLModchart.targetName(track.target) + ' · ' + track.prop, options, choice -> {
      switch (options.indexOf(choice))
      {
        case 0: addKeyAt(track, snap(beat));
        case 1:
          doc.checkpoint();
          track.muted = track.muted == true ? null : true;
          afterEdit();
        case 2: selectKeys([for (k in track.keys) {track: track, key: k}], false);
        case 3: deleteTrack(track);
        default:
      }
    });
  }

  function deleteTrack(track:QOLModTrack):Void
  {
    doc.checkpoint();
    doc.removeTrack(track);
    if (selTrack == track) selTrack = null;
    afterEdit();
  }

  function selectAllKeys():Void
  {
    var tracks = selTrack != null ? [selTrack] : doc.data.tracks;
    selectKeys([for (t in tracks) for (k in t.keys) {track: t, key: k}], false);
  }

  function copyKeys():Void
  {
    if (selKeys.length == 0) return;
    var first = 1e9;
    for (s in selKeys)
      first = Math.min(first, s.key.t);
    clipboard = [
      for (s in selKeys)
        {
          target: s.track.target,
          prop: s.track.prop,
          dt: s.key.t - first,
          v: s.key.v,
          e: s.key.e
        }
    ];
    setStatus('Copied ${clipboard.length} key${clipboard.length == 1 ? '' : 's'}.');
  }

  function pasteKeys():Void
  {
    if (clipboard.length == 0) return;
    doc.checkpoint();
    var at = snap(beat);
    var pasted:Array<ModKeyRef> = [];
    for (c in clipboard)
    {
      var track = doc.findTrack(c.target, c.prop) ?? doc.addTrack(c.target, c.prop);
      pasted.push({track: track, key: doc.setKey(track, at + c.dt, c.v, c.e)});
    }
    selKeys = pasted;
    afterEdit();
    setStatus('Pasted ${pasted.length} key${pasted.length == 1 ? '' : 's'} at beat ${ModchartTimeline.formatValue(at)}.');
  }

  /**
   * A short demo routine (works on any song) to learn from: drunk, tornado, reverse, a field spin, confusion,
   * a tilting HUD, a camera zoom punch and a health bar fly-in.
   */
  function insertExample():Void
  {
    doc.checkpoint();
    function k(t:Float, v:Float, ?e:String):QOLModKey
    {
      var key:QOLModKey = {t: t, v: v};
      if (e != null) key.e = e;
      return key;
    }
    function track(target:String, prop:String, keys:Array<QOLModKey>):Void
    {
      var t = doc.findTrack(target, prop);
      if (t != null) doc.removeTrack(t);
      doc.data.tracks.push({target: target, prop: prop, keys: keys});
    }
    track('strum:0', 'drunk', [k(0, 0), k(4, 1, 'sineInOut'), k(12, 1), k(16, 0, 'sineInOut')]);
    track('strum:1', 'tornado', [k(4, 0), k(8, 1, 'quadOut'), k(16, 0, 'quadIn')]);
    track('strum:0:1', 'confusion', [k(8, 0), k(12, 360)]);
    track('strum:0', 'reverse', [k(16, 0), k(20, 1, 'quadInOut'), k(28, 1), k(32, 0, 'backOut')]);
    track('strum:1', 'rotate', [k(20, 0), k(24, 360, 'expoInOut')]);
    track('camHUD', 'angle', [k(24, 0), k(26, 5, 'sineInOut'), k(28, -5, 'sineInOut'), k(30, 0, 'sineInOut')]);
    track('camGame', 'zoom', [k(28, 0), k(29, 0.15, 'expoOut'), k(32, 0, 'quadIn')]);
    track('healthBar', 'y', [k(32, 120), k(34, 0, 'backOut')]);
    for (t in doc.data.tracks)
      QOLModchart.sortKeys(t);
    for (target in ['strum:0', 'strum:1', 'strum:0:1', 'camHUD', 'camGame', 'healthBar'])
      timeline.reveal(target);
    afterEdit();
    setStatus('Inserted an example modchart (beats 0-34). Press Space to watch it, then tweak or delete tracks.');
  }

  function jumpToKey(dir:Int):Void
  {
    var tracks = selTrack != null ? [selTrack] : doc.data.tracks;
    var best:Null<Float> = null;
    for (t in tracks)
      for (k in t.keys)
      {
        if (dir > 0 && k.t > beat + 0.0001 && (best == null || k.t < best)) best = k.t;
        if (dir < 0 && k.t < beat - 0.0001 && (best == null || k.t > best)) best = k.t;
      }
    if (best != null)
    {
      seekBeat(best);
      timeline.follow(best);
    }
  }

  //
  // Inspector & library
  //

  function rebuildInspector():Void
  {
    if (inspectorBox == null) return;
    inspectorBox.removeAllComponents();
    inspectorForm = new QOLForm(130, 250);
    var form = inspectorForm;
    inspectorBefore = doc.snapshot();
    form.onAnyChange = () -> {
      for (s in selKeys)
        QOLModchart.sortKeys(s.track);
      doc.commitFrom(inspectorBefore);
      inspectorBefore = doc.snapshot();
      runtime?.setData(doc.data);
      timeline.rebuildRows();
      dirty = true;
      updateWindowTitle();
    };

    if (selKeys.length == 1)
    {
      var ref = selKeys[0];
      var prop = QOLModchart.getProp(ref.track.prop, QOLModchart.targetKind(ref.track.target));
      form.section('Keyframe');
      form.note('${QOLModchart.targetName(ref.track.target)} · ${prop?.name ?? ref.track.prop}');
      form.number('Time (beats)', () -> ref.key.t, v -> ref.key.t = Math.max(0, v), 0, 99999, snapBeats, 3);
      form.number('Value', () -> ref.key.v, v -> ref.key.v = v, prop?.min ?? -99999, prop?.max ?? 99999, prop?.step ?? 0.05, 3);
      form.ease('Ease in', () -> ref.key.e ?? 'linear', v -> ref.key.e = v == 'linear' ? null : v, true);
      form.note('The ease is how the value travels from the previous key to this one. Instant = jump at this key.');
      form.buttons([
        {text: 'Go to key', cb: () -> seekBeat(ref.key.t)},
        {text: 'Delete key', cb: () -> deleteKeys([ref])}
      ]);
      if (prop != null) form.note(prop.desc);
    }
    else if (selKeys.length > 1)
    {
      form.section('${selKeys.length} keys selected');
      form.number('Value (all)', () -> selKeys[0]?.key.v ?? 0, v -> for (s in selKeys)
        s.key.v = v, -99999, 99999, 0.05, 3);
      form.ease('Ease in (all)', () -> selKeys[0]?.key.e ?? 'linear', v -> for (s in selKeys)
        s.key.e = v == 'linear' ? null : v, true);
      form.buttons([
        {text: 'Copy (Ctrl+C)', cb: copyKeys},
        {text: 'Delete', cb: () -> deleteKeys(selKeys.copy())}
      ]);
      form.note('Drag any selected key in the timeline to move them all. Hold Alt to move without snapping.');
    }
    else if (selTrack != null)
    {
      var track = selTrack;
      var prop = QOLModchart.getProp(track.prop, QOLModchart.targetKind(track.target));
      form.section('Track');
      form.note('${QOLModchart.targetName(track.target)} · ${prop?.name ?? track.prop}');
      if (prop != null) form.note(prop.desc);
      form.number('Value at playhead', () -> QOLModchart.sample(track, beat, prop?.neutral ?? 0), v -> {
        doc.setKey(track, snap(beat), v);
      }, prop?.min ?? -99999, prop?.max ?? 99999, prop?.step ?? 0.05, 3);
      form.note('Changing the value adds a key at the playhead (or updates the key that is there).');
      form.check('Muted', () -> track.muted == true, v -> track.muted = v ? true : null);
      form.buttons([
        {text: 'Add key (K)', cb: () -> addKeyAt(track, snap(beat))},
        {text: 'Delete track', cb: () -> deleteTrack(track)}
      ]);
      form.note('${track.keys.length} key${track.keys.length == 1 ? '' : 's'}.');
    }
    else if (selTarget != null)
    {
      var target = selTarget;
      var kind = QOLModchart.targetKind(target);
      form.section(QOLModchart.targetName(target));
      var props = QOLModchart.propsFor(kind);
      var pick = props[0]?.id ?? 'x';
      form.dropdown('Animate', () -> [for (p in props) p.id], () -> pick, v -> pick = v, () -> [for (p in props) '${p.group} · ${p.name}']);
      form.button('+ Add track', () -> addTrack(target, pick));
      var tracks = doc.tracksOf(target);
      if (tracks.length > 0)
      {
        form.section('Tracks');
        for (t in tracks)
          form.note('• ${QOLModchart.getProp(t.prop, kind)?.name ?? t.prop}: ${t.keys.length} key${t.keys.length == 1 ? '' : 's'}');
      }
      if (kind == 'strum' || kind == 'lane' || kind == 'object')
        form.note('Tip: drag it in the preview to key its X/Y at the playhead. Ctrl+drag an arrow to move just that arrow.');
    }
    else
    {
      form.section('Modchart Editor');
      form.note('1. Click something in the preview (a strumline, an arrow with Ctrl, the health bar, a character) or a row in the timeline.');
      form.note('2. Add a track: the + next to its name, or the Add Track tab (every modchart feature is there).');
      form.note('3. Move the playhead, then press K (or change the value) to add keys. Pick an ease for each key.');
      form.note('Space plays, Enter playtests, Ctrl+S saves into your mod. Keys: drag to move, right-click to delete, double-click a track to add one.');
    }
    inspectorBox.addComponent(form);
  }

  function refreshLibraryTargets():Void
  {
    if (libTargets == null) return;
    var ds = new ArrayDataSource<Dynamic>();
    libTargetIds = [];
    for (group in preview.targetGroups())
    {
      if (group.targets.length == 0) continue;
      ds.add({text: '— ${group.name} —'});
      libTargetIds.push('');
      for (t in group.targets)
      {
        ds.add({text: QOLModchart.targetName(t)});
        libTargetIds.push(t);
        if (QOLModchart.targetKind(t) == 'strum') for (i in 0...4)
        {
          ds.add({text: '      ${QOLModchart.LANE_NAMES[i]} arrow'});
          libTargetIds.push('$t:$i');
        }
      }
    }
    libTargets.dataSource = ds;
    refreshLibraryProps();
  }

  var syncingLibrary:Bool = false;

  /**
   * Point the Add Track lists at the current selection.
   */
  function syncLibrary():Void
  {
    if (libTargets == null) return;
    var index = selTarget != null ? libTargetIds.indexOf(selTarget) : -1;
    syncingLibrary = true;
    if (libTargets.selectedIndex != index) libTargets.selectedIndex = index;
    syncingLibrary = false;
    refreshLibraryProps();
  }

  function refreshLibraryProps():Void
  {
    if (libProps == null) return;
    var kind = QOLModchart.targetKind(selTarget ?? 'strum:0');
    var ds = new ArrayDataSource<Dynamic>();
    libPropIds = [];
    var lastGroup = '';
    for (p in QOLModchart.propsFor(kind))
    {
      if (p.group != lastGroup)
      {
        ds.add({text: '— ${p.group} —'});
        libPropIds.push('');
        lastGroup = p.group;
      }
      ds.add({text: '${p.name}${selTarget != null && doc.findTrack(selTarget, p.id) != null ? '  ✓' : ''}'});
      libPropIds.push(p.id);
    }
    libProps.dataSource = ds;
    refreshLibraryDesc();
  }

  function refreshLibraryDesc():Void
  {
    if (libDesc == null) return;
    var target = selTarget;
    var i = libProps.selectedIndex;
    var id = i >= 0 && i < libPropIds.length ? libPropIds[i] : '';
    var prop = id != '' ? QOLModchart.getProp(id, QOLModchart.targetKind(target ?? 'strum:0')) : null;
    libDesc.text = (target == null ? 'Pick a target on the left first. ' : 'Target: ${QOLModchart.targetName(target)}. ')
      + (prop != null ? '${prop.name}: ${prop.desc}' : 'Pick a feature to see what it does. Double-click to add it.');
  }

  function addTrackFromLibrary():Void
  {
    var i = libProps.selectedIndex;
    var id = i >= 0 && i < libPropIds.length ? libPropIds[i] : '';
    if (selTarget == null || id == '')
    {
      setStatus('Pick a target and a feature first.');
      return;
    }
    addTrack(selTarget, id);
    tabs.pageIndex = 0;
  }

  //
  // Playback
  //

  function togglePlay():Void
  {
    playing = !playing;
    playButton.text = playing ? 'Pause' : 'Play';
    if (playing)
    {
      if (songPosition >= songLength - 10) seekBeat(0);
      if (inst != null)
      {
        inst.play(true, songPosition);
        inst.pitch = playbackRate;
      }
      if (vocals != null)
      {
        vocals.play(true, songPosition);
        vocals.pitch = playbackRate;
      }
    }
    else
    {
      inst?.pause();
      vocals?.pause();
    }
  }

  function playtest(fromHere:Bool):Void
  {
    if (song == null) return;
    var start = fromHere ? songPosition : 0;
    stopAudio();
    QOLPlayHooks.pendingModchart = QOLModchart.normalize(haxe.Json.parse(doc.snapshot()));
    runtime?.destroy();
    runtime = null;
    // Stages are shared objects (cached by the registry): hand ours back so the PlayState can use it.
    preview.clear();
    openPlaytest({
      targetSong: song,
      targetDifficulty: difficulty,
      targetVariation: variation,
      practiceMode: true,
      botPlayMode: false,
      playtestResults: false,
      minimalMode: false,
      startTimestamp: start,
      playbackRate: playbackRate,
      overrideMusic: false
    }, null, () -> {
      QOLPlayHooks.pendingModchart = null;
      if (diffData != null) Conductor.instance.mapTimeChanges(diffData.timeChanges);
      rebuildPreview();
      seekBeat(beat);
      loadAudio();
    });
  }

  //
  // Update
  //

  override public function update(elapsed:Float):Void
  {
    if (playtestPending) return;

    // Undo last frame's modchart changes so everything updates from clean values.
    runtime?.preUpdate();
    preview.place();

    super.update(elapsed);
    if (subState != null || playtestPending) return;

    if (playing)
    {
      songPosition = inst != null && inst.playing ? inst.time : songPosition + elapsed * 1000 * playbackRate;
      if (songPosition >= songLength)
      {
        songPosition = songLength;
        togglePlay();
      }
      beat = Conductor.instance.getTimeInSteps(songPosition) / Constants.STEPS_PER_BEAT;
      if (!timeline.dragging) timeline.follow(beat);
    }

    Conductor.instance.update(songPosition, false);
    preview.update(songPosition);
    runtime?.update(beat);

    if (!dialogOpen)
    {
      var usedByTimeline = timeline.handleMouse();
      if (!usedByTimeline) handlePreviewMouse();
    }
    timeline.refresh();
    updateOutline();
    updateTimeLabel();
  }

  function handlePreviewMouse():Void
  {
    var mx = FlxG.mouse.viewX;
    var my = FlxG.mouse.viewY;
    if (previewDrag != null)
    {
      var d = previewDrag;
      var p = preview.screenToHud(mx, my);
      var dx = (p.x - d.hx) / d.scale;
      var dy = (p.y - d.hy) / d.scale;
      p.put();
      if (Math.abs(dx) > 1 || Math.abs(dy) > 1) d.moved = true;
      if (d.moved)
      {
        var nx = Math.round(d.x0 + dx);
        var ny = Math.round(d.y0 + dy);
        if (FlxG.keys.pressed.SHIFT)
        {
          // Lock to one axis.
          if (Math.abs(dx) > Math.abs(dy)) ny = Math.round(d.y0);
          else
            nx = Math.round(d.x0);
        }
        autoKey(d.target, 'x', nx, true);
        autoKey(d.target, 'y', ny, true);
        liveEdit();
      }
      if (!FlxG.mouse.pressed)
      {
        if (d.moved)
        {
          doc.commitFrom(d.before);
          var xt = doc.findTrack(d.target, 'x');
          var yt = doc.findTrack(d.target, 'y');
          selKeys = [];
          for (t in [xt, yt])
          {
            if (t == null) continue;
            var k = doc.keyAt(t, snap(beat));
            if (k != null) selKeys.push({track: t, key: k});
          }
          afterEdit();
          timeline.reveal(d.target);
        }
        previewDrag = null;
      }
      return;
    }

    if (!preview.inside(mx, my) || mouseOverUI) return;
    if (FlxG.mouse.wheel != 0) return;
    if (FlxG.mouse.justPressed)
    {
      var p = preview.screenToHud(mx, my);
      var target = preview.hitTest(p.x, p.y, ctrl());
      if (target == null)
      {
        p.put();
        clearSelection();
        return;
      }
      selectTarget(target);
      var world = target.startsWith('char:') || target.startsWith('prop:');
      var xt = doc.findTrack(target, 'x');
      var yt = doc.findTrack(target, 'y');
      previewDrag = {
        target: target,
        hx: p.x,
        hy: p.y,
        x0: xt != null ? QOLModchart.sample(xt, beat, 0) : 0,
        y0: yt != null ? QOLModchart.sample(yt, beat, 0) : 0,
        before: doc.snapshot(),
        scale: world ? preview.gameZoom : 1,
        moved: false
      };
      p.put();
    }
  }

  function updateOutline():Void
  {
    var b = selTarget != null ? preview.boundsOf(selTarget) : null;
    if (b == null)
    {
      for (s in outline)
        s.visible = false;
      return;
    }
    var p1 = preview.hudToScreen(b.x, b.y);
    var p2 = preview.hudToScreen(b.right, b.bottom);
    b.put();
    var x1 = Math.max(PREVIEW_X, p1.x - 2);
    var y1 = Math.max(PREVIEW_Y, p1.y - 2);
    var x2 = Math.min(PREVIEW_X + FlxG.width * PREVIEW_SCALE, p2.x + 2);
    var y2 = Math.min(PREVIEW_Y + FlxG.height * PREVIEW_SCALE, p2.y + 2);
    p1.put();
    p2.put();
    if (x2 <= x1 || y2 <= y1)
    {
      for (s in outline)
        s.visible = false;
      return;
    }
    setLine(outline[0], x1, y1, x2 - x1, 2);
    setLine(outline[1], x1, y2 - 2, x2 - x1, 2);
    setLine(outline[2], x1, y1, 2, y2 - y1);
    setLine(outline[3], x2 - 2, y1, 2, y2 - y1);
  }

  static function setLine(s:FlxSprite, x:Float, y:Float, w:Float, h:Float):Void
  {
    s.visible = true;
    s.setPosition(x, y);
    s.scale.set(Math.max(1, w), Math.max(1, h));
    s.updateHitbox();
  }

  function updateTimeLabel():Void
  {
    var secs = songPosition / 1000;
    var mins = Math.floor(secs / 60);
    var rest = secs - mins * 60;
    var measure = Math.floor(beat / beatsPerMeasure) + 1;
    var text = '$mins:${StringTools.lpad('${Math.floor(rest)}', '0', 2)}.${StringTools.lpad('${Math.floor((rest * 100) % 100)}', '0', 2)}'
      + '   Beat ${ModchartTimeline.formatValue(beat)}   Measure $measure   Snap ${SNAP_LABELS[SNAPS.indexOf(snapBeats)] ?? ''}';
    if (timeLabel.text != text) timeLabel.text = text;
  }

  override function handleShortcuts():Void
  {
    if (FlxG.keys.justPressed.SPACE) togglePlay();
    if (FlxG.keys.justPressed.ENTER) playtest(!FlxG.keys.pressed.SHIFT);
    if (ctrl())
    {
      if (FlxG.keys.justPressed.Z) undo();
      if (FlxG.keys.justPressed.Y) redo();
      if (FlxG.keys.justPressed.C) copyKeys();
      if (FlxG.keys.justPressed.V) pasteKeys();
      if (FlxG.keys.justPressed.A) selectAllKeys();
      if (FlxG.keys.justPressed.O) chooseFromList('Open song', [for (id in SongRegistry.instance.listEntryIds()) id], id -> loadSong(id), songId);
      return;
    }
    if (FlxG.keys.justPressed.K) addKeyOnSelected();
    if (FlxG.keys.justPressed.DELETE || FlxG.keys.justPressed.BACKSPACE) deleteKeys(selKeys.copy());
    if (FlxG.keys.justPressed.HOME) seekBeat(0);
    if (FlxG.keys.justPressed.LEFT) seekBeat(Math.max(0, snap(beat) - (FlxG.keys.pressed.SHIFT ? beatsPerMeasure : snapBeats)));
    if (FlxG.keys.justPressed.RIGHT) seekBeat(snap(beat) + (FlxG.keys.pressed.SHIFT ? beatsPerMeasure : snapBeats));
    if (FlxG.keys.justPressed.LBRACKET) jumpToKey(-1);
    if (FlxG.keys.justPressed.RBRACKET) jumpToKey(1);
    if (FlxG.keys.justPressed.M && selTrack != null)
    {
      doc.checkpoint();
      selTrack.muted = selTrack.muted == true ? null : true;
      afterEdit();
    }
  }

  override public function exitEditor():Void
  {
    if (selKeys.length > 0 || selTrack != null || selTarget != null)
    {
      clearSelection();
      return;
    }
    super.exitEditor();
  }

  override public function destroy():Void
  {
    destroyed = true;
    stopAudio();
    runtime?.destroy();
    preview?.destroy();
    super.destroy();
  }
}
#end
