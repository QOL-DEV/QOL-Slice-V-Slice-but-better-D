package funkin.qol.editors;

#if FEATURE_HAXEUI
import flixel.FlxCamera;
import flixel.FlxSubState;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.audio.VoicesGroup;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.data.event.SongEventRegistry;
import funkin.data.notestyle.NoteStyleRegistry;
import funkin.data.song.SongData.SongEventData;
import funkin.data.song.SongData.SongNoteData;
import funkin.data.song.SongData.SongTimeChange;
import funkin.data.song.SongRegistry;
import funkin.data.stage.StageRegistry;
import funkin.graphics.FunkinCamera;
import funkin.play.notes.notekind.NoteKindManager;
import funkin.play.song.Song;
import funkin.qol.editors.chart.ChartModel;
import funkin.qol.editors.chart.ChartView;
import funkin.qol.editors.chart.EventFieldsForm;
import funkin.qol.runtime.QOLPlayHooks;
import funkin.qol.runtime.QOLPlayHooks.QOLStrumlineData;
import funkin.qol.ui.QOLEditorState;
import funkin.qol.ui.QOLForm;
import funkin.qol.util.QOLFS;
import funkin.ui.transition.LoadingState;
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.containers.TabView;
import haxe.ui.containers.VBox;
import haxe.ui.data.ArrayDataSource;

/**
 * The QOL Slice Chart Editor.
 *
 * Inspired by Codename Engine's chart editor, with V-Slice's look: strumlines side by side with
 * their character icons (opponent, player, and any number of extra strumlines), an events lane,
 * waveforms, every snap from 4ths to 192nds, click to place / right-click to delete, drag to move,
 * box select, copy/paste, undo/redo, hitsounds, metronome, live input and instant playtesting.
 *
 * Charts are saved in V-Slice's format into `mods/<mod>/data/songs/<song>/`.
 */
class QOLChartEditorState extends QOLEditorState
{
  public static final QUANTS:Array<Int> = [4, 8, 12, 16, 20, 24, 32, 48, 64, 96, 192];

  var model:ChartModel;
  var view:ChartView;
  var conductor:Conductor;

  var inst:Null<FunkinSound> = null;
  var vocals:Null<VoicesGroup> = null;
  var playing:Bool = false;
  var songPosition:Float = 0;
  var songLength:Float = 60000;
  var playbackRate:Float = 1;
  var instVolume:Float = 1;
  var playerVolume:Float = 1;
  var opponentVolume:Float = 1;
  var hitsoundsPlayer:Bool = true;
  var hitsoundsOpponent:Bool = true;
  var metronome:Bool = false;
  var liveInput:Bool = false;
  var playtestBotplay:Bool = false;
  var lastAudioTime:Float = 0;
  var lastBeat:Int = -1;

  var quantIndex:Int = 3;
  var placeKind:String = '';
  var placeEventKind:String = 'FocusCamera';

  var dragMode:String = '';
  var dragStartStep:Float = 0;
  var dragStartLane:Int = 0;
  var dragNote:Null<{lane:Int, step:Float}> = null;
  var clipboardNotes:Array<SongNoteData> = [];
  var clipboardEvents:Array<SongEventData> = [];
  var clipboardStep:Float = 0;

  var songForm:QOLForm;
  var strumForm:QOLForm;
  var strumList:ListView;
  var noteForm:QOLForm;
  var eventKindList:ListView;
  var eventForm:QOLForm;
  var eventFormKind:String = '';
  var selectedStrumline:Int = 2;
  var settingsBefore:String = '';


  /**
   * @param songId Song to open (null = the last one, or a new song).
   */
  public function new(?songId:String, ?difficulty:String, ?variation:String, position:Float = 0)
  {
    super();
    editorName = 'Chart Editor';
    leftPanelWidth = 300;
    rightPanelWidth = 300;
    startSong = songId;
    startDifficulty = difficulty;
    startVariation = variation;
    startPosition = position;
  }

  var startSong:Null<String>;
  var startDifficulty:Null<String>;
  var startVariation:Null<String>;
  var startPosition:Float = 0;

  override function guidePage():String
    return 'chart';

  //
  // Setup
  //

  override function buildEditor():Void
  {
    camWorld.bgColor = 0xFF15111F;
    gridBG.alpha = 0.35;
    conductor = new Conductor();

    var id = startSong ?? QOLConfig.getPref('chartEditor.last', null);
    var loaded = id != null ? ChartModel.load(id, startVariation) : null;
    if (loaded != null && startDifficulty != null && loaded.metadata.playData.difficulties.contains(startDifficulty)) loaded.difficulty = startDifficulty;
    model = loaded ?? ChartModel.create('my-song', 'My Song', 'You', 120, 'bf', 'dad', 'gf', 'mainStage');
    model.onChange = onModelChanged;

    view = new ChartView(model, conductor);
    view.cameras = [camWorld];
    layoutView();
    add(view);
    view.addOverlays();

    buildMenus();
    buildLeftPanel();
    buildRightPanel();
    afterLoad();
    if (startPosition > 0) seek(startPosition);
  }

  function layoutView()
  {
    view.x = leftPanelWidth + 10;
    view.y = QOLEditorState.MENUBAR_HEIGHT + 6;
    view.width = FlxG.width - leftPanelWidth - rightPanelWidth - 70;
    view.height = FlxG.height - QOLEditorState.MENUBAR_HEIGHT - QOLEditorState.STATUSBAR_HEIGHT - 10;
    view.forceLayout();
  }

  function buildMenus()
  {
    var file = addMenu('File');
    addMenuItem(file, 'New Song...', 'Ctrl+N', newSongDialog);
    addMenuItem(file, 'Open Song...', 'Ctrl+O', openSongDialog);
    addMenuSeparator(file);
    addMenuItem(file, 'Save', 'Ctrl+S', () -> doSave());
    addMenuSeparator(file);
    addMenuItem(file, 'Import Instrumental (OGG)...', null, () -> importAudio('Inst'));
    addMenuItem(file, 'Import Player Vocals (OGG)...', null, () -> importAudio('Voices-${model.metadata.playData.characters.player}'));
    addMenuItem(file, 'Import Opponent Vocals (OGG)...', null, () -> importAudio('Voices-${model.metadata.playData.characters.opponent}'));

    var edit = addMenu('Edit');
    addMenuItem(edit, 'Undo', 'Ctrl+Z', undo);
    addMenuItem(edit, 'Redo', 'Ctrl+Y', redo);
    addMenuSeparator(edit);
    addMenuItem(edit, 'Copy', 'Ctrl+C', copySelection);
    addMenuItem(edit, 'Cut', 'Ctrl+X', () -> {
      copySelection();
      deleteSelection();
    });
    addMenuItem(edit, 'Paste at Playhead', 'Ctrl+V', paste);
    addMenuItem(edit, 'Delete Selection', 'Delete', deleteSelection);
    addMenuItem(edit, 'Select All Notes', 'Ctrl+A', () -> {
      view.selectedNotes = model.notes.copy();
      view.selectedEvents = [];
      refreshNoteForm();
    });
    addMenuItem(edit, 'Mirror Selection', 'M', mirrorSelection);
    addMenuSeparator(edit);
    addMenuItem(edit, 'Longer Holds', 'E', () -> changeSustains(1));
    addMenuItem(edit, 'Shorter Holds', 'Q', () -> changeSustains(-1));

    var chartMenu = addMenu('Chart');
    addMenuItem(chartMenu, 'Snap Finer', 'Right', () -> setQuant(quantIndex + 1));
    addMenuItem(chartMenu, 'Snap Coarser', 'Left', () -> setQuant(quantIndex - 1));
    addMenuItem(chartMenu, 'Add Strumline', null, addStrumline);
    addMenuItem(chartMenu, 'Copy Opponent Notes to Player', null, () -> copyLane(1, 0));
    addMenuItem(chartMenu, 'Copy Player Notes to Opponent', null, () -> copyLane(0, 1));

    var playMenu = addMenu('Playback');
    addMenuItem(playMenu, 'Play / Pause', 'Space', togglePlay);
    addMenuItem(playMenu, 'Playtest From Here', 'Enter', () -> playtest(true));
    addMenuItem(playMenu, 'Playtest From Start', 'Shift+Enter', () -> playtest(false));
    addMenuCheck(playMenu, 'Playtest with Botplay', playtestBotplay, v -> playtestBotplay = v);
    addMenuSeparator(playMenu);
    addMenuCheck(playMenu, 'Player Hitsounds', hitsoundsPlayer, v -> hitsoundsPlayer = v);
    addMenuCheck(playMenu, 'Opponent Hitsounds', hitsoundsOpponent, v -> hitsoundsOpponent = v);
    addMenuCheck(playMenu, 'Metronome', metronome, v -> metronome = v);
    addMenuCheck(playMenu, 'Live Input (keys 1-8 while playing)', liveInput, v -> liveInput = v);

    var viewMenu = addMenu('View');
    addMenuCheck(viewMenu, 'Waveforms', true, v -> {
      view.showWaveforms = v;
      refreshWaveforms();
    });
    addMenuItem(viewMenu, 'Zoom In', 'Ctrl+Wheel', () -> view.pxPerStep = Math.min(160, view.pxPerStep * 1.2));
    addMenuItem(viewMenu, 'Zoom Out', 'Ctrl+Wheel', () -> view.pxPerStep = Math.max(8, view.pxPerStep / 1.2));
  }

  function buildLeftPanel()
  {
    var tabs = new TabView();
    tabs.width = leftPanelWidth - 26;
    tabs.height = FlxG.height - QOLEditorState.MENUBAR_HEIGHT - QOLEditorState.STATUSBAR_HEIGHT - 26;
    leftPanel.addComponent(tabs);

    // Song tab.
    var songPage = new VBox();
    songPage.text = 'Song';
    songPage.styleString = 'padding: 4px;';
    tabs.addComponent(songPage);
    songForm = new QOLForm(92, 150);
    songForm.onAnyChange = () -> settingsChanged('Song settings');
    songForm.section('Song');
    songForm.textField('Song ID', () -> model.songId, v -> model.songId = ModWorkspace.sanitizeFolderName(v).toLowerCase());
    songForm.textField('Name', () -> model.metadata.songName, v -> model.metadata.songName = v);
    songForm.textField('Artist', () -> model.metadata.artist, v -> model.metadata.artist = v);
    songForm.textField('Charter', () -> model.metadata.charter ?? '', v -> model.metadata.charter = v);
    songForm.dropdown('Difficulty', () -> model.metadata.playData.difficulties, () -> model.difficulty, v -> {
      model.difficulty = v;
      model.ensureDifficulty(v);
      view.selectedNotes = [];
      songForm.refresh();
    });
    songForm.button('+ Add Difficulty', () -> prompt('Add difficulty', 'Difficulty name (easy, normal, hard, erect, nightmare...):', 'erect', d -> {
      d = d.trim().toLowerCase();
      if (d == '') return;
      var before = model.settingsSnapshot();
      model.ensureDifficulty(d);
      model.difficulty = d;
      model.recordSettings('Add difficulty', before);
      songForm.refresh();
    }));
    songForm.number('Scroll speed', () -> model.scrollSpeed, v -> model.scrollSpeed = v, 0.1, 10, 0.1, 2);
    songForm.number('BPM', () -> model.metadata.timeChanges[0]?.bpm ?? 100, v -> {
      model.metadata.timeChanges[0].bpm = v;
      conductor.mapTimeChanges(model.metadata.timeChanges);
    }, 1, 999, 1, 2);
    songForm.number('Beats / measure', () -> model.metadata.timeChanges[0]?.timeSignatureNum ?? 4, v -> {
      model.metadata.timeChanges[0].timeSignatureNum = Std.int(v);
      conductor.mapTimeChanges(model.metadata.timeChanges);
    }, 1, 16, 1, 0);
    songForm.number('Difficulty rating', () -> model.metadata.playData.ratings.get(model.difficulty) ?? 0,
      v -> model.metadata.playData.ratings.set(model.difficulty, Std.int(v)), 0, 99, 1, 0);

    songForm.section('Characters & stage');
    songForm.dropdown('Player', () -> CharacterDataParser.listCharacterIds(), () -> model.metadata.playData.characters.player,
      v -> model.metadata.playData.characters.player = v);
    songForm.dropdown('Opponent', () -> CharacterDataParser.listCharacterIds(), () -> model.metadata.playData.characters.opponent,
      v -> model.metadata.playData.characters.opponent = v);
    songForm.dropdown('Girlfriend', () -> [''].concat(CharacterDataParser.listCharacterIds()), () -> model.metadata.playData.characters.girlfriend,
      v -> model.metadata.playData.characters.girlfriend = v);
    songForm.dropdown('Stage', () -> StageRegistry.instance.listEntryIds(), () -> model.metadata.playData.stage, v -> model.metadata.playData.stage = v);
    songForm.dropdown('Note style', () -> NoteStyleRegistry.instance.listEntryIds(), () -> model.metadata.playData.noteStyle,
      v -> model.metadata.playData.noteStyle = v);

    songForm.section('Audio');
    songForm.slider('Instrumental', () -> instVolume, v -> {
      instVolume = v;
      applyVolumes();
    }, 0, 1, 0.05);
    songForm.slider('Player vocals', () -> playerVolume, v -> {
      playerVolume = v;
      applyVolumes();
    }, 0, 1, 0.05);
    songForm.slider('Opponent vocals', () -> opponentVolume, v -> {
      opponentVolume = v;
      applyVolumes();
    }, 0, 1, 0.05);
    songForm.slider('Playback speed', () -> playbackRate, v -> {
      playbackRate = Math.round(v * 20) / 20;
      applyVolumes();
    }, 0.25, 2, 0.05);
    songForm.buttons([
      {text: 'Import Inst', cb: () -> importAudio('Inst')},
      {text: 'Reload audio', cb: loadAudio}
    ]);
    songPage.addComponent(songForm);

    // Strumlines tab.
    var strumPage = new VBox();
    strumPage.text = 'Strumlines';
    strumPage.styleString = 'padding: 4px; spacing: 5px;';
    tabs.addComponent(strumPage);
    var help = new Label();
    help.width = leftPanelWidth - 50;
    help.text = 'Add extra strumlines for Girlfriend (or anyone). Their notes are played by the CPU and make that character sing.';
    help.styleString = 'color: #C9C2E6; font-size: 11px;';
    strumPage.addComponent(help);
    strumList = new ListView();
    strumList.width = leftPanelWidth - 50;
    strumList.height = 120;
    strumList.onChange = _ -> {
      if (strumList.selectedItem != null)
      {
        selectedStrumline = strumList.selectedItem.index;
        strumForm.refresh();
      }
    };
    strumPage.addComponent(strumList);
    var srow = new HBox();
    srow.addComponent(btn('+ Add Strumline', addStrumline));
    srow.addComponent(btn('Delete', deleteStrumline));
    strumPage.addComponent(srow);
    strumForm = new QOLForm(92, 150);
    strumForm.onAnyChange = () -> {
      settingsChanged('Strumline settings');
      view.forceLayout();
      refreshStrumList();
    };
    strumForm.textField('Name', () -> curStrum()?.name ?? '', v -> if (curStrum() != null) curStrum().name = v);
    strumForm.dropdown('Character', () -> ['gf', 'bf', 'dad'].concat(CharacterDataParser.listCharacterIds()), () -> curStrum()?.character ?? 'gf',
      v -> if (curStrum() != null) curStrum().character = v, () -> ['Girlfriend (gf)', 'Player (bf)', 'Opponent (dad)'].concat(CharacterDataParser.listCharacterIds()));
    strumForm.check('Visible', () -> curStrum()?.visible != false, v -> if (curStrum() != null) curStrum().visible = v);
    strumForm.number('Scale', () -> curStrum()?.scale ?? 0.45, v -> if (curStrum() != null) curStrum().scale = v, 0.1, 2, 0.05, 2);
    strumForm.slider('Alpha', () -> curStrum()?.alpha ?? 1, v -> if (curStrum() != null) curStrum().alpha = v, 0, 1, 0.05);
    strumForm.check('Auto position', () -> curStrum() == null || curStrum().x == null, v -> {
      var s = curStrum();
      if (s == null) return;
      if (v)
      {
        s.x = null;
        s.y = null;
      }
      else
      {
        s.x = (FlxG.width - 320) / 2;
        s.y = 50;
      }
    });
    strumForm.pair('Position', () -> curStrum()?.x ?? 0, v -> if (curStrum() != null) curStrum().x = v, () -> curStrum()?.y ?? 0,
      v -> if (curStrum() != null) curStrum().y = v);
    strumForm.textField('Sing suffix', () -> curStrum()?.singSuffix ?? '', v -> if (curStrum() != null) curStrum().singSuffix = v, 'e.g. alt');
    strumForm.pair('Char. offset', () -> (curStrum()?.charOffset ?? [0, 0])[0], v -> setCharOffset(0, v), () -> (curStrum()?.charOffset ?? [0, 0])[1],
      v -> setCharOffset(1, v));
    strumForm.note('Character offset only applies to characters spawned by this strumline (not bf/gf/dad).');
    strumPage.addComponent(strumForm);

    // Notes tab.
    var notePage = new VBox();
    notePage.text = 'Notes';
    notePage.styleString = 'padding: 4px;';
    tabs.addComponent(notePage);
    noteForm = new QOLForm(92, 150);
    noteForm.section('Placing notes');
    noteForm.dropdown('Note kind', noteKinds, () -> placeKind, v -> placeKind = v, noteKindLabels);
    noteForm.dropdown('Snap', () -> [for (q in QUANTS) '$q'], () -> '${QUANTS[quantIndex]}', v -> setQuant(QUANTS.indexOf(Std.parseInt(v))),
      () -> [for (q in QUANTS) '1/$q']);
    noteForm.section('Selected notes');
    noteForm.custom(new Label(), null);
    noteForm.dropdown('Set kind', noteKinds, () -> commonKind(), v -> setSelectionKind(v), noteKindLabels);
    noteForm.number('Hold length (steps)', () -> commonLength(), v -> setSelectionLength(v), 0, 512, 0.25, 2);
    noteForm.buttons([
      {text: 'Mirror', cb: mirrorSelection},
      {text: 'Delete', cb: deleteSelection}
    ]);
    noteForm.note('Click: place  ·  Drag down while placing: hold note\nRight-click: delete  ·  Drag a note: move it\nShift+drag / right-drag: box select  ·  Ctrl+click: add to selection');
    notePage.addComponent(noteForm);
  }

  function buildRightPanel()
  {
    var title = new Label();
    title.text = 'Events';
    title.styleString = 'font-bold: true; font-size: 15px; color: #FF8FB8;';
    rightPanel.addComponent(title);
    var hint = new Label();
    hint.width = rightPanelWidth - 30;
    hint.text = 'Pick an event, then click the events lane (left of the strumlines) to place it.';
    hint.styleString = 'color: #C9C2E6; font-size: 11px;';
    rightPanel.addComponent(hint);

    eventKindList = new ListView();
    eventKindList.width = rightPanelWidth - 30;
    eventKindList.height = 190;
    var ds = new ArrayDataSource<Dynamic>();
    var kinds = SongEventRegistry.listEventIds();
    kinds.sort((a, b) -> eventTitle(a).toLowerCase() < eventTitle(b).toLowerCase() ? -1 : 1);
    for (k in kinds)
      ds.add({text: eventTitle(k), kind: k});
    eventKindList.dataSource = ds;
    eventKindList.onChange = _ -> {
      if (eventKindList.selectedItem != null) placeEventKind = eventKindList.selectedItem.kind;
    };
    for (i in 0...kinds.length)
      if (kinds[i] == placeEventKind) eventKindList.selectedIndex = i;
    rightPanel.addComponent(eventKindList);

    eventForm = new QOLForm(100, 160);
    rightPanel.addComponent(eventForm);
    rebuildEventForm();
  }

  function btn(text:String, cb:Void->Void):Button
  {
    var b = new Button();
    b.text = text;
    b.onClick = _ -> cb();
    return b;
  }

  static function eventTitle(kind:String):String
    return SongEventRegistry.getEvent(kind)?.getTitle() ?? kind;

  function noteKinds():Array<String>
  {
    var kinds = [''];
    try
    {
      for (k in NoteKindManager.listNoteKinds())
        if (k != null && k != '' && !kinds.contains(k)) kinds.push(k);
    }
    catch (e) {}
    for (n in model.notes)
      if (n.kind != null && n.kind != '' && !kinds.contains(n.kind)) kinds.push(n.kind);
    return kinds;
  }

  function noteKindLabels():Array<String>
    return [for (k in noteKinds()) k == '' ? '(normal)' : k];

  //
  // Loading & audio
  //

  function afterLoad()
  {
    conductor.mapTimeChanges(model.metadata.timeChanges);
    model.sortNotes();
    model.sortEvents();
    songPosition = 0;
    view.selectedNotes = [];
    view.selectedEvents = [];
    view.forceLayout();
    QOLConfig.setPref('chartEditor.last', model.songId);
    settingsBefore = model.settingsSnapshot();
    loadAudio();
    songForm.refresh();
    refreshStrumList();
    strumForm.refresh();
    refreshNoteForm();
    rebuildEventForm();
    dirty = false;
  }

  function buildSong():Null<Song>
  {
    try
    {
      return Song.buildRaw(model.songId, [model.metadata], model.variation, [model.variation => model.chart], false, false);
    }
    catch (e)
    {
      trace('[QOL] buildRaw failed: $e');
      return null;
    }
  }

  function stopAudio()
  {
    playing = false;
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

  function loadAudio()
  {
    stopAudio();
    FlxG.sound.music?.stop();
    var song = buildSong();
    var diff = song?.getDifficulty(model.difficulty, model.variation);
    #if html5
    // Web builds don't preload the songs library: load this song's files straight from their URLs.
    if (openfl.utils.Assets.getLibrary('songs') == null)
    {
      loadWebAudio();
      return;
    }
    #end
    try
    {
      var instPath = diff != null ? diff.getInstPath() : Paths.inst(model.songId);
      if (Assets.exists(instPath)) inst = FunkinSound.load(instPath, 1.0, false, false, false, false, null, null, true);
      if (diff != null) vocals = diff.buildVocals();
    }
    catch (e)
    {
      trace('[QOL] Audio failed: $e');
    }
    finishAudio();
  }

  function finishAudio()
  {
    songLength = inst != null && inst.length > 0 ? inst.length : Math.max(60000, lastObjectTime() + 8000);
    applyVolumes();
    refreshWaveforms();
    setStatus(inst == null ? 'No instrumental found for "${model.songId}". Use File > Import Instrumental.' : 'Loaded ${model.songId}.');
  }

  #if html5
  function loadWebAudio()
  {
    var varSuffix = (model.variation == null || model.variation == Constants.DEFAULT_VARIATION) ? '' : '-${model.variation}';
    function url(path:String):String
      return path.substr(path.indexOf(':') + 1);
    var token = ++webAudioToken;
    setStatus('Loading audio...');
    openfl.media.Sound.loadFromFile(url(Paths.inst(model.songId, varSuffix))).onComplete(function(snd) {
      if (destroyed || token != webAudioToken) return;
      inst = FunkinSound.load(snd, 1.0, false, false, false, false, null, null, true);
      vocals = new VoicesGroup();
      var chars = model.metadata.playData.characters;
      var group = vocals;
      for (pair in [{c: chars.player, player: true}, {c: chars.opponent, player: false}])
      {
        var p = pair;
        openfl.media.Sound.loadFromFile(url(Paths.voices(model.songId, '-${p.c}$varSuffix'))).onComplete(function(v) {
          if (destroyed || token != webAudioToken || vocals != group) return;
          var sound = FunkinSound.load(v, 1.0, false, false, false, false, null, null, true);
          if (sound == null) return;
          if (p.player) group.addPlayerVoice(sound);
          else
            group.addOpponentVoice(sound);
          applyVolumes();
        });
      }
      finishAudio();
    }).onError(function(_) {
      if (destroyed || token != webAudioToken) return;
      finishAudio();
    });
  }

  var webAudioToken:Int = 0;
  #end

  var destroyed:Bool = false;

  function refreshWaveforms()
  {
    try
    {
      view.setWaveforms(inst?.waveformData, vocals?.getPlayerVoiceWaveform(), vocals?.getOpponentVoiceWaveform());
    }
    catch (e)
    {
      trace('[QOL] Waveform failed: $e');
    }
  }

  function lastObjectTime():Float
  {
    var t = 0.0;
    var n = model.notes;
    if (n.length > 0) t = n[n.length - 1].time + n[n.length - 1].length;
    var e = model.events;
    if (e.length > 0) t = Math.max(t, e[e.length - 1].time);
    return t;
  }

  function applyVolumes()
  {
    if (inst != null)
    {
      inst.volume = instVolume;
      inst.pitch = playbackRate;
    }
    if (vocals != null)
    {
      vocals.playerVolume = playerVolume;
      vocals.opponentVolume = opponentVolume;
      vocals.pitch = playbackRate;
    }
  }

  function togglePlay()
  {
    playing = !playing;
    if (playing)
    {
      if (songPosition >= songLength - 10) songPosition = 0;
      lastAudioTime = songPosition;
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

  function seek(ms:Float)
  {
    songPosition = Math.max(0, Math.min(songLength, ms));
    if (playing)
    {
      if (inst != null) inst.time = songPosition;
      if (vocals != null) vocals.time = songPosition;
    }
    lastAudioTime = songPosition;
  }

  function importAudio(fileName:String)
  {
    #if sys
    funkin.util.FileUtil.browseForFile('Choose an OGG file', [funkin.util.FileUtil.FILE_FILTER_OGG], file -> {
      ModWorkspace.saveBytes('songs/${model.songId}/$fileName.ogg', file.bytes);
      notify('Imported', 'songs/${model.songId}/$fileName.ogg');
      ModWorkspace.reloadGameData();
      loadAudio();
    });
    #else
    alert('Not available', 'Importing files needs the desktop version of the game.');
    #end
  }

  //
  // Song dialogs
  //

  function openSongDialog()
  {
    var ids = SongRegistry.instance.listEntryIds();
    for (dir in ModWorkspace.list('data/songs'))
      if (!ids.contains(dir)) ids.push(dir);
    ids.sort((a, b) -> a < b ? -1 : 1);
    chooseFromList('Open song', ids, id -> {
      var m = ChartModel.load(id);
      if (m == null)
      {
        alert('Could not open', 'Couldn\'t load the chart for "$id".');
        return;
      }
      model = m;
      model.onChange = onModelChanged;
      view.model = m;
      afterLoad();
    }, model.songId);
  }

  function newSongDialog()
  {
    prompt('New song', 'Song name:', 'My Song', name -> {
      name = name.trim();
      if (name == '') return;
      var id = ModWorkspace.sanitizeFolderName(name).toLowerCase();
      prompt('New song', 'BPM of "$name":', '120', bpmText -> {
        var bpm = Std.parseFloat(bpmText);
        if (Math.isNaN(bpm) || bpm <= 0) bpm = 120;
        model = ChartModel.create(id, name, 'You', bpm, 'bf', 'dad', 'gf', 'mainStage');
        model.onChange = onModelChanged;
        view.model = model;
        afterLoad();
        dirty = true;
        notify('New song', 'Import an instrumental from the File menu, then start charting!');
      });
    });
  }

  //
  // Model changes
  //

  function onModelChanged()
  {
    dirty = true;
    refreshNoteForm();
  }

  function settingsChanged(name:String)
  {
    model.recordSettings(name, settingsBefore);
    settingsBefore = model.settingsSnapshot();
    conductor.mapTimeChanges(model.metadata.timeChanges);
    view.forceLayout();
    dirty = true;
  }

  function undo()
  {
    var name = model.undo();
    if (name == null) return;
    afterUndoRedo('Undo: $name');
  }

  function redo()
  {
    var name = model.redo();
    if (name == null) return;
    afterUndoRedo('Redo: $name');
  }

  function afterUndoRedo(msg:String)
  {
    view.selectedNotes = view.selectedNotes.filter(n -> model.notes.indexOf(n) != -1);
    view.selectedEvents = view.selectedEvents.filter(e -> model.events.indexOf(e) != -1);
    conductor.mapTimeChanges(model.metadata.timeChanges);
    settingsBefore = model.settingsSnapshot();
    songForm.refresh();
    refreshStrumList();
    strumForm.refresh();
    view.forceLayout();
    rebuildEventForm();
    setStatus(msg);
    FunkinSound.playOnce(Paths.sound('chartingSounds/undo'), 0.5);
  }

  //
  // Strumlines
  //

  function curStrum():Null<QOLStrumlineData>
    return model.extraStrumline(selectedStrumline);

  function setCharOffset(i:Int, v:Float)
  {
    var s = curStrum();
    if (s == null) return;
    if (s.charOffset == null) s.charOffset = [0, 0];
    s.charOffset[i] = v;
  }

  function refreshStrumList()
  {
    var ds = new ArrayDataSource<Dynamic>();
    ds.add({text: 'Player  ·  ${model.metadata.playData.characters.player}', index: 0});
    ds.add({text: 'Opponent  ·  ${model.metadata.playData.characters.opponent}', index: 1});
    for (i in 2...model.strumlineCount())
    {
      var s = model.extraStrumline(i);
      ds.add({text: '${s?.name ?? 'Strumline ${i + 1}'}  ·  ${s?.character ?? 'gf'}', index: i});
    }
    strumList.dataSource = ds;
    strumList.selectedIndex = selectedStrumline;
    strumForm.disabled = selectedStrumline < 2;
  }

  function addStrumline()
  {
    var before = model.settingsSnapshot();
    var index = model.strumlineCount();
    model.qolSong.strumlines.push({
      index: index,
      name: index == 2 ? 'Girlfriend' : 'Strumline ${index + 1}',
      character: index == 2 ? 'gf' : 'dad',
      visible: true,
      scale: 0.45,
      alpha: 1
    });
    selectedStrumline = index;
    model.recordSettings('Add strumline', before);
    settingsBefore = model.settingsSnapshot();
    view.forceLayout();
    refreshStrumList();
    strumForm.refresh();
  }

  function deleteStrumline()
  {
    if (selectedStrumline < 2) return;
    var index = selectedStrumline;
    var notes = model.notes.filter(n -> n.getStrumlineIndex() == index);
    confirm('Delete strumline', 'Delete strumline ${index + 1}' + (notes.length > 0 ? ' and its ${notes.length} notes?' : '?'), () -> {
      var before = model.settingsSnapshot();
      var s = model.extraStrumline(index);
      if (s != null) model.qolSong.strumlines.remove(s);
      // Shift later strumlines down so indices stay continuous.
      var moved:Array<SongNoteData> = [];
      var removed:Array<SongNoteData> = notes.copy();
      for (n in model.notes)
      {
        if (n.getStrumlineIndex() > index)
        {
          removed.push(n);
          moved.push(new SongNoteData(n.time, n.data - 4, n.length, n.kind));
        }
      }
      for (sl in model.qolSong.strumlines)
        if (sl.index > index) sl.index--;
      var after = model.settingsSnapshot();
      model.apply({
        name: 'Delete strumline',
        removeNotes: removed,
        addNotes: moved,
        settingsBefore: before,
        settingsAfter: after
      });
      settingsBefore = after;
      selectedStrumline = 1;
      view.selectedNotes = [];
      view.forceLayout();
      refreshStrumList();
      strumForm.refresh();
    });
  }

  function copyLane(from:Int, to:Int)
  {
    var add:Array<SongNoteData> = [];
    for (n in model.notes)
      if (n.getStrumlineIndex() == from) add.push(new SongNoteData(n.time, to * 4 + n.getDirection(), n.length, n.kind));
    var remove = model.notes.filter(n -> n.getStrumlineIndex() == to);
    model.apply({name: 'Copy strumline notes', addNotes: add, removeNotes: remove});
  }

  //
  // Notes
  //

  function setQuant(index:Int)
  {
    quantIndex = Std.int(Math.max(0, Math.min(QUANTS.length - 1, index)));
    view.snapSteps = 16 / QUANTS[quantIndex];
    noteForm?.refresh();
  }

  function refreshNoteForm()
  {
    if (noteForm == null) return;
    noteForm.refresh();
  }

  function commonKind():String
  {
    var sel = view.selectedNotes;
    if (sel.length == 0) return placeKind;
    var k = sel[0].kind ?? '';
    for (n in sel)
      if ((n.kind ?? '') != k) return '';
    return k;
  }

  function commonLength():Float
  {
    var sel = view.selectedNotes;
    if (sel.length == 0) return 0;
    return Math.round((view.stepAt(sel[0].time + sel[0].length) - view.stepAt(sel[0].time)) * 100) / 100;
  }

  function replaceSelection(name:String, transform:SongNoteData->SongNoteData)
  {
    if (view.selectedNotes.length == 0) return;
    var removed = view.selectedNotes.copy();
    var added = [for (n in removed) transform(n)];
    model.apply({name: name, removeNotes: removed, addNotes: added});
    view.selectedNotes = added;
  }

  function setSelectionKind(kind:String)
  {
    if (view.selectedNotes.length == 0)
    {
      placeKind = kind;
      return;
    }
    replaceSelection('Change note kind', n -> new SongNoteData(n.time, n.data, n.length, kind));
  }

  function setSelectionLength(steps:Float)
  {
    replaceSelection('Change hold length', n -> {
      var end = view.msAt(view.stepAt(n.time) + steps);
      return new SongNoteData(n.time, n.data, Math.max(0, end - n.time), n.kind);
    });
  }

  function changeSustains(dir:Int)
  {
    replaceSelection('Change hold length', n -> {
      var len = view.stepAt(n.time + n.length) - view.stepAt(n.time);
      len = Math.max(0, len + dir * view.snapSteps);
      var end = view.msAt(view.stepAt(n.time) + len);
      return new SongNoteData(n.time, n.data, Math.max(0, end - n.time), n.kind);
    });
  }

  function mirrorSelection()
  {
    replaceSelection('Mirror', n -> new SongNoteData(n.time, n.getStrumlineIndex() * 4 + (3 - n.getDirection()), n.length, n.kind));
  }

  function deleteSelection()
  {
    if (view.selectedNotes.length == 0 && view.selectedEvents.length == 0) return;
    model.apply({name: 'Delete', removeNotes: view.selectedNotes.copy(), removeEvents: view.selectedEvents.copy()});
    view.selectedNotes = [];
    view.selectedEvents = [];
    rebuildEventForm();
    FunkinSound.playOnce(Paths.sound('chartingSounds/noteErase'), 0.6);
  }

  function copySelection()
  {
    if (view.selectedNotes.length == 0 && view.selectedEvents.length == 0) return;
    var first = Math.POSITIVE_INFINITY;
    for (n in view.selectedNotes)
      first = Math.min(first, n.time);
    for (e in view.selectedEvents)
      first = Math.min(first, e.time);
    clipboardStep = view.stepAt(first);
    clipboardNotes = [for (n in view.selectedNotes) new SongNoteData(n.time, n.data, n.length, n.kind)];
    clipboardEvents = [for (e in view.selectedEvents) new SongEventData(e.time, e.eventKind, funkin.qol.util.QOLJson.clone(e.value))];
    setStatus('Copied ${clipboardNotes.length} notes and ${clipboardEvents.length} events.');
  }

  function paste()
  {
    if (clipboardNotes.length == 0 && clipboardEvents.length == 0) return;
    var target = Math.round(view.stepAt(songPosition) / view.snapSteps) * view.snapSteps;
    var shift = target - clipboardStep;
    function moveTime(t:Float):Float
      return view.msAt(view.stepAt(t) + shift);
    var notes = [
      for (n in clipboardNotes)
      {
        var start = moveTime(n.time);
        new SongNoteData(start, n.data, Math.max(0, moveTime(n.time + n.length) - start), n.kind);
      }
    ];
    var events = [
      for (e in clipboardEvents)
        new SongEventData(moveTime(e.time), e.eventKind, funkin.qol.util.QOLJson.clone(e.value))
    ];
    model.apply({name: 'Paste', addNotes: notes, addEvents: events});
    view.selectedNotes = notes;
    view.selectedEvents = events;
  }

  function placeNote(lane:Int, step:Float, lengthSteps:Float)
  {
    var time = view.msAt(step);
    // Replace a note already in the same spot.
    var existing = model.notes.filter(n -> n.data == lane && Math.abs(n.time - time) < 1);
    var length = lengthSteps > 0 ? view.msAt(step + lengthSteps) - time : 0;
    var note = new SongNoteData(time, lane, length, placeKind);
    model.apply({name: 'Place note', addNotes: [note], removeNotes: existing});
    view.selectedNotes = [note];
    FunkinSound.playOnce(Paths.sound('chartingSounds/noteLay'), 0.5);
  }

  //
  // Events
  //

  function placeEvent(step:Float)
  {
    var schema = SongEventRegistry.getEventSchema(placeEventKind);
    var value:Dynamic = {};
    if (schema != null)
    {
      for (name in schema.listAllFieldNames())
      {
        var def = schema.getDefaultFieldValue(name);
        if (def != null) Reflect.setField(value, name, def);
      }
    }
    var e = new SongEventData(view.msAt(step), placeEventKind, value);
    model.apply({name: 'Place event', addEvents: [e]});
    view.selectedEvents = [e];
    view.selectedNotes = [];
    rebuildEventForm();
  }

  function selectedEvent():Null<SongEventData>
    return view.selectedEvents.length == 1 ? view.selectedEvents[0] : null;

  var eventBefore:String = '';

  function rebuildEventForm()
  {
    if (eventForm == null) return;
    eventForm.clearForm();
    var e = selectedEvent();
    if (e == null)
    {
      eventFormKind = '';
      eventForm.note(view.selectedEvents.length > 1 ? '${view.selectedEvents.length} events selected.' : 'Select an event to edit it.');
      return;
    }
    eventFormKind = e.eventKind;
    eventForm.section(eventTitle(e.eventKind));
    eventForm.number('Time (step)', () -> {
      var ev = selectedEvent();
      return ev == null ? 0 : Math.round(view.stepAt(ev.time) * 100) / 100;
    }, v -> {
      var ev = selectedEvent();
      if (ev == null) return;
      var moved = new SongEventData(view.msAt(v), ev.eventKind, ev.value);
      model.apply({name: 'Move event', removeEvents: [ev], addEvents: [moved]});
      view.selectedEvents = [moved];
    }, 0, 99999, 0.25, 2);
    eventBefore = haxe.Json.stringify(e.value);
    EventFieldsForm.build(eventForm, e.eventKind, selectedEvent, () -> {
      // Field edits are recorded as an undoable replace of the event.
      var ev = selectedEvent();
      if (ev == null) return;
      var now = haxe.Json.stringify(ev.value);
      if (now == eventBefore) return;
      var oldValue:Dynamic = haxe.Json.parse(eventBefore);
      var oldEvent = new SongEventData(ev.time, ev.eventKind, oldValue);
      // Swap in place: the edited object stays, undo restores the old copy.
      model.events.remove(ev);
      model.events.push(oldEvent);
      model.apply({name: 'Edit event', removeEvents: [oldEvent], addEvents: [ev]});
      eventBefore = now;
    });
  }

  //
  // Playtesting
  //

  function playtest(fromHere:Bool)
  {
    var song = buildSong();
    if (song == null)
    {
      alert('Can\'t playtest', 'This chart couldn\'t be turned into a song. Check the song settings.');
      return;
    }
    if (inst == null)
    {
      alert('No instrumental', 'Import an instrumental first (File > Import Instrumental), then playtest again.');
      return;
    }
    var start = fromHere ? songPosition : 0;
    playing = false;
    QOLPlayHooks.pendingSongData = model.cloneSong();

    // The PlayState uses our chart and audio as they are now (unsaved edits included).
    inst?.pause();
    vocals?.pause();
    var useOwnAudio = inst != null;
    if (useOwnAudio) FlxG.sound.music = inst;
    else
      FlxG.sound.music?.stop();

    // Stage assets live in level libraries (week1...); point the asset system at the right one.
    funkin.play.PlayStatePlaylist.reset();
    var stageData = StageRegistry.instance.fetchEntry(model.metadata.playData.stage);
    @:privateAccess var dir = stageData?._data?.directory ?? 'shared';
    funkin.play.PlayStatePlaylist.campaignId = dir;
    Paths.setCurrentLevel(dir);

    openPlaytest({
      targetSong: song,
      targetDifficulty: model.difficulty,
      targetVariation: model.variation,
      practiceMode: true,
      botPlayMode: playtestBotplay,
      playtestResults: false,
      minimalMode: false,
      startTimestamp: start,
      playbackRate: playbackRate,
      overrideMusic: useOwnAudio
    }, function(ps) {
      ps.instrumentalVolume = instVolume;
      ps.playerVocalsVolume = playerVolume;
      ps.opponentVocalsVolume = opponentVolume;
      if (useOwnAudio) ps.vocals = vocals;
    }, () -> {
      // The PlayState only paused our audio; rebuild it fresh (the song settings may have changed too).
      if (FlxG.sound.music == inst) FlxG.sound.music = null;
      loadAudio();
    });
  }

  //
  // Saving
  //

  override function save():Bool
  {
    if (model.songId.trim() == '')
    {
      alert('No song ID', 'Give the song an ID first.');
      return false;
    }
    var path = model.save();
    QOLConfig.setPref('chartEditor.last', model.songId);
    notifySaved(path);
    return true;
  }

  override function afterSaveReload():Void
  {
    // Reloading would replace the song registry entries we're not using; just make the game see the files.
    ModWorkspace.reloadGameData();
  }

  override public function exitEditor():Void
  {
    if (view.selectedNotes.length > 0 || view.selectedEvents.length > 0)
    {
      view.selectedNotes = [];
      view.selectedEvents = [];
      rebuildEventForm();
      return;
    }
    stopAudio();
    super.exitEditor();
  }

  //
  // Update & input
  //

  override public function update(elapsed:Float):Void
  {
    // Skip updates while a playtest is starting or running (our cameras are detached).
    if (playtestPending) return;
    super.update(elapsed);
    if (subState != null) return;

    if (playing)
    {
      var audioTime = inst != null && inst.playing ? inst.time : songPosition + elapsed * 1000 * playbackRate;
      songPosition = audioTime;
      if (songPosition >= songLength)
      {
        songPosition = songLength;
        togglePlay();
      }
      playHitsounds(lastAudioTime, songPosition);
      lastAudioTime = songPosition;
    }

    conductor.update(songPosition, false);
    view.songPosition = songPosition;

    if (selectedEvent()?.eventKind != eventFormKind || (selectedEvent() == null && eventFormKind != '')) rebuildEventForm();

    handleMouse();
    view.refresh();
    updateStatus();
  }

  function playHitsounds(from:Float, to:Float)
  {
    if (to <= from) return;
    if (hitsoundsPlayer || hitsoundsOpponent)
    {
      var notes = model.notes;
      var i = model.firstNoteIndexAt(from);
      var playedPlayer = false;
      var playedOpp = false;
      while (i < notes.length && notes[i].time <= to)
      {
        var n = notes[i];
        if (n.time > from)
        {
          if (n.getStrumlineIndex() == 0 && hitsoundsPlayer && !playedPlayer)
          {
            FunkinSound.playOnce(Paths.sound('chartingSounds/hitNotePlayer'), 0.6);
            playedPlayer = true;
          }
          else if (n.getStrumlineIndex() != 0 && hitsoundsOpponent && !playedOpp)
          {
            FunkinSound.playOnce(Paths.sound('chartingSounds/hitNoteOpponent'), 0.5);
            playedOpp = true;
          }
        }
        i++;
      }
    }
    if (metronome)
    {
      var beat = Std.int(view.stepAt(to) / 4);
      if (beat != lastBeat && beat >= 0)
      {
        lastBeat = beat;
        var measure = conductor.timeSignatureNumerator;
        FunkinSound.playOnce(Paths.sound(beat % measure == 0 ? 'chartingSounds/metronome1' : 'chartingSounds/metronome2'), 0.5);
      }
    }
  }

  function handleMouse()
  {
    var mx = FlxG.mouse.viewX;
    var my = FlxG.mouse.viewY;
    var overUI = mouseOverUI || dialogOpen;
    var inChart = !overUI && view.inChart(mx, my);
    var lane = view.laneAt(mx);

    // Scrolling & zoom.
    if (!overUI && FlxG.mouse.wheel != 0)
    {
      if (ctrl()) view.pxPerStep = Math.max(8, Math.min(160, view.pxPerStep * (FlxG.mouse.wheel > 0 ? 1.15 : 1 / 1.15)));
      else
      {
        var steps = (FlxG.keys.pressed.SHIFT ? 16 : 4) * (FlxG.mouse.wheel > 0 ? -1 : 1);
        var snapped = Math.round(view.stepAt(songPosition) / view.snapSteps) * view.snapSteps;
        seek(view.msAt(Math.max(0, snapped + steps * Math.max(view.snapSteps, 0.25))));
      }
    }

    // Clicking a strumline header selects it in the Strumlines tab.
    if (!overUI && FlxG.mouse.justPressed)
    {
      var header = view.headerAt(mx, my);
      if (header >= 0)
      {
        selectedStrumline = header;
        refreshStrumList();
        strumForm.refresh();
      }
    }

    view.ghostLane = -2;
    if (dragMode == '')
    {
      if (inChart && lane >= 0 && view.noteAt(mx, my) == null)
      {
        view.ghostLane = lane;
        view.ghostTime = view.msAt(Math.max(0, view.snappedStepAt(my)));
        view.ghostLength = 0;
      }

      if (inChart && FlxG.mouse.justPressed)
      {
        var step = Math.max(0, view.snappedStepAt(my));
        if (lane == -1)
        {
          var ev = view.eventAt(mx, my);
          if (ev != null)
          {
            if (ctrl())
            {
              if (view.selectedEvents.indexOf(ev) != -1) view.selectedEvents.remove(ev);
              else
                view.selectedEvents.push(ev);
            }
            else if (view.selectedEvents.indexOf(ev) == -1)
            {
              view.selectedEvents = [ev];
              view.selectedNotes = [];
            }
            rebuildEventForm();
            dragMode = 'move';
            dragStartStep = step;
            dragStartLane = -1;
          }
          else if (FlxG.keys.pressed.SHIFT) startBox(mx, my);
          else
            placeEvent(step);
        }
        else if (lane >= 0)
        {
          var note = view.noteAt(mx, my);
          if (note != null)
          {
            if (ctrl())
            {
              if (view.selectedNotes.indexOf(note) != -1) view.selectedNotes.remove(note);
              else
                view.selectedNotes.push(note);
            }
            else if (view.selectedNotes.indexOf(note) == -1)
            {
              view.selectedNotes = [note];
              view.selectedEvents = [];
              rebuildEventForm();
            }
            dragMode = 'move';
            dragStartStep = step;
            dragStartLane = lane;
          }
          else if (FlxG.keys.pressed.SHIFT) startBox(mx, my);
          else
          {
            dragMode = 'place';
            dragNote = {lane: lane, step: step};
          }
        }
      }
      else if (inChart && FlxG.mouse.justPressedRight)
      {
        var note = lane >= 0 ? view.noteAt(mx, my) : null;
        var ev = lane == -1 ? view.eventAt(mx, my) : null;
        if (note != null)
        {
          var targets = view.selectedNotes.indexOf(note) != -1 ? view.selectedNotes.copy() : [note];
          model.apply({name: 'Delete notes', removeNotes: targets});
          for (t in targets)
            view.selectedNotes.remove(t);
          FunkinSound.playOnce(Paths.sound('chartingSounds/noteErase'), 0.6);
        }
        else if (ev != null)
        {
          model.apply({name: 'Delete event', removeEvents: [ev]});
          view.selectedEvents.remove(ev);
          rebuildEventForm();
        }
        else
          startBox(mx, my, true);
      }
      return;
    }

    switch (dragMode)
    {
      case 'place':
        var length = Math.max(0, view.snappedStepAt(my) - dragNote.step);
        view.ghostLane = dragNote.lane;
        view.ghostTime = view.msAt(dragNote.step);
        view.ghostLength = view.msAt(dragNote.step + length) - view.ghostTime;
        if (!FlxG.mouse.pressed)
        {
          placeNote(dragNote.lane, dragNote.step, length);
          dragMode = '';
          dragNote = null;
        }
      case 'move':
        var offset = view.snappedStepAt(my) - dragStartStep;
        view.dragStepOffset = offset;
        view.dragLaneOffset = (dragStartLane >= 0 && lane >= 0) ? lane - dragStartLane : 0;
        if (!FlxG.mouse.pressed) finishMove();
      case 'box':
        view.boxSelect[2] = mx;
        view.boxSelect[3] = my;
        var released = boxRight ? !FlxG.mouse.pressedRight : !FlxG.mouse.pressed;
        if (released) finishBox();
    }
  }

  var boxRight:Bool = false;

  function startBox(mx:Float, my:Float, right:Bool = false)
  {
    dragMode = 'box';
    boxRight = right;
    view.boxSelect = [mx, my, mx, my];
  }

  function finishBox()
  {
    var b = view.boxSelect;
    view.boxSelect = null;
    dragMode = '';
    var x0 = Math.min(b[0], b[2]);
    var x1 = Math.max(b[0], b[2]);
    var t0 = view.timeAt(Math.min(b[1], b[3]));
    var t1 = view.timeAt(Math.max(b[1], b[3]));
    var add = ctrl();
    if (!add)
    {
      view.selectedNotes = [];
      view.selectedEvents = [];
    }
    for (n in model.notes)
    {
      if (n.time < t0 || n.time > t1) continue;
      var nx = view.laneX(n.data) + view.laneWidth / 2;
      if (nx >= x0 && nx <= x1 && view.selectedNotes.indexOf(n) == -1) view.selectedNotes.push(n);
    }
    if (x0 <= view.x + view.eventLaneWidth)
    {
      for (e in model.events)
        if (e.time >= t0 && e.time <= t1 && view.selectedEvents.indexOf(e) == -1) view.selectedEvents.push(e);
    }
    rebuildEventForm();
    refreshNoteForm();
  }

  function finishMove()
  {
    var dStep = view.dragStepOffset;
    var dLane = view.dragLaneOffset;
    view.dragStepOffset = 0;
    view.dragLaneOffset = 0;
    dragMode = '';
    if (dStep == 0 && dLane == 0) return;
    var maxLane = model.strumlineCount() * 4 - 1;
    var removed = view.selectedNotes.copy();
    var added:Array<SongNoteData> = [];
    for (n in removed)
    {
      var start = view.msAt(Math.max(0, view.stepAt(n.time) + dStep));
      var end = view.msAt(Math.max(0, view.stepAt(n.time + n.length) + dStep));
      var lane = n.data + dLane;
      if (lane < 0 || lane > maxLane) lane = n.data;
      added.push(new SongNoteData(start, lane, Math.max(0, end - start), n.kind));
    }
    var removedE = view.selectedEvents.copy();
    var addedE = [
      for (e in removedE)
        new SongEventData(view.msAt(Math.max(0, view.stepAt(e.time) + dStep)), e.eventKind, e.value)
    ];
    model.apply({
      name: 'Move',
      removeNotes: removed,
      addNotes: added,
      removeEvents: removedE,
      addEvents: addedE
    });
    view.selectedNotes = added;
    view.selectedEvents = addedE;
    rebuildEventForm();
  }

  var holdTimer:Float = 0;

  override function handleShortcuts():Void
  {
    if (subState != null) return;
    if (ctrl())
    {
      if (FlxG.keys.justPressed.Z) undo();
      if (FlxG.keys.justPressed.Y) redo();
      if (FlxG.keys.justPressed.C) copySelection();
      if (FlxG.keys.justPressed.X)
      {
        copySelection();
        deleteSelection();
      }
      if (FlxG.keys.justPressed.V) paste();
      if (FlxG.keys.justPressed.A)
      {
        view.selectedNotes = model.notes.copy();
        refreshNoteForm();
      }
      if (FlxG.keys.justPressed.N) newSongDialog();
      if (FlxG.keys.justPressed.O) openSongDialog();
      return;
    }

    if (FlxG.keys.justPressed.SPACE) togglePlay();
    if (FlxG.keys.justPressed.ENTER) playtest(!FlxG.keys.pressed.SHIFT);
    if (FlxG.keys.justPressed.DELETE || FlxG.keys.justPressed.BACKSPACE) deleteSelection();
    if (FlxG.keys.justPressed.LEFT) setQuant(quantIndex - 1);
    if (FlxG.keys.justPressed.RIGHT) setQuant(quantIndex + 1);
    if (FlxG.keys.justPressed.Q) changeSustains(-1);
    if (FlxG.keys.justPressed.E) changeSustains(1);
    if (FlxG.keys.justPressed.M) mirrorSelection();
    if (FlxG.keys.justPressed.HOME) seek(0);
    if (FlxG.keys.justPressed.END) seek(songLength);

    // Step through the song (with key repeat).
    var dir = 0;
    if (FlxG.keys.pressed.UP || FlxG.keys.pressed.W) dir = -1;
    if (FlxG.keys.pressed.DOWN || FlxG.keys.pressed.S) dir = 1;
    var measure = FlxG.keys.justPressed.PAGEUP ? -1 : (FlxG.keys.justPressed.PAGEDOWN ? 1 : 0);
    if (measure != 0) seek(view.msAt(Math.max(0, (Math.floor(view.stepAt(songPosition) / 16) + measure) * 16)));
    if (dir != 0)
    {
      var justPressed = FlxG.keys.justPressed.UP || FlxG.keys.justPressed.W || FlxG.keys.justPressed.DOWN || FlxG.keys.justPressed.S;
      holdTimer = justPressed ? -0.3 : holdTimer + FlxG.elapsed;
      if (justPressed || holdTimer > 0.06)
      {
        if (holdTimer > 0.06) holdTimer = 0;
        var snapped = Math.round(view.stepAt(songPosition) / view.snapSteps) * view.snapSteps;
        seek(view.msAt(Math.max(0, snapped + dir * view.snapSteps)));
      }
    }

    // Live input: 1-4 = opponent, 5-8 = player, at the playhead.
    if (liveInput && playing)
    {
      var keys = [
        FlxG.keys.justPressed.ONE, FlxG.keys.justPressed.TWO, FlxG.keys.justPressed.THREE, FlxG.keys.justPressed.FOUR, FlxG.keys.justPressed.FIVE,
        FlxG.keys.justPressed.SIX, FlxG.keys.justPressed.SEVEN, FlxG.keys.justPressed.EIGHT
      ];
      for (i in 0...8)
        if (keys[i])
        {
          var lane = i < 4 ? 4 + i : i - 4;
          var step = Math.round(view.stepAt(songPosition) / view.snapSteps) * view.snapSteps;
          placeNote(lane, step, 0);
        }
    }
  }

  function updateStatus()
  {
    var step = view.stepAt(songPosition);
    var beat = step / 4;
    var measure = Math.floor(beat / conductor.timeSignatureNumerator) + 1;
    var sel = view.selectedNotes.length + view.selectedEvents.length;
    var text = '${model.songId} [${model.difficulty}]  ·  measure $measure  beat ${Math.floor(beat * 100) / 100}  step ${Math.floor(step)}'
      + '  ·  ${conductor.bpm} BPM  ·  snap 1/${QUANTS[quantIndex]}  ·  ${model.notes.length} notes'
      + (sel > 0 ? '  ·  $sel selected' : '') + (playbackRate != 1 ? '  ·  ${playbackRate}x' : '');
    if (statusLabel.text != text) setStatus(text);
  }

  override public function destroy():Void
  {
    destroyed = true;
    stopAudio();
    super.destroy();
  }
}
#end
