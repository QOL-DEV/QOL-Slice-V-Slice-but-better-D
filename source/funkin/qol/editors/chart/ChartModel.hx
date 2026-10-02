package funkin.qol.editors.chart;

import funkin.data.song.SongData.SongChartData;
import funkin.data.song.SongData.SongEventData;
import funkin.data.song.SongData.SongMetadata;
import funkin.data.song.SongData.SongNoteData;
import funkin.data.song.SongData.SongTimeChange;
import funkin.data.song.SongRegistry;
import funkin.qol.runtime.QOLPlayHooks.QOLSongData;
import funkin.qol.runtime.QOLPlayHooks.QOLStrumlineData;
import funkin.qol.util.QOLJson;

/**
 * One undoable change to a chart: notes/events added and removed (a move is a remove + add),
 * plus an optional snapshot of the song settings.
 */
typedef ChartCommand =
{
  var name:String;
  var ?addNotes:Array<SongNoteData>;
  var ?removeNotes:Array<SongNoteData>;
  var ?addEvents:Array<SongEventData>;
  var ?removeEvents:Array<SongEventData>;
  var ?settingsBefore:String;
  var ?settingsAfter:String;
}

/**
 * Everything the QOL chart editor edits: V-Slice metadata + chart data (one variation),
 * plus QOL Slice's per-song settings (extra strumlines).
 */
class ChartModel
{
  public var songId:String;
  public var variation:String = Constants.DEFAULT_VARIATION;
  public var metadata:SongMetadata;
  public var chart:SongChartData;
  public var difficulty:String = 'normal';
  public var qolSong:QOLSongData = {version: '1.0.0', strumlines: []};

  public var undoStack:Array<ChartCommand> = [];
  public var redoStack:Array<ChartCommand> = [];

  /**
   * Called after anything changes (so the view can redraw and the editor can mark itself dirty).
   */
  public var onChange:Null<Void->Void> = null;

  public function new(songId:String, metadata:SongMetadata, chart:SongChartData)
  {
    this.songId = songId;
    this.metadata = metadata;
    this.chart = chart;
    var diffs = metadata.playData.difficulties;
    difficulty = diffs.contains('normal') ? 'normal' : (diffs.length > 0 ? diffs[0] : 'normal');
    ensureDifficulty(difficulty);
  }

  /**
   * Load a song (from the active mod, or anything the game knows about).
   */
  public static function load(songId:String, ?variation:String):Null<ChartModel>
  {
    variation = variation ?? Constants.DEFAULT_VARIATION;
    var meta:Null<SongMetadata> = null;
    var chart:Null<SongChartData> = null;
    try
    {
      var version = SongRegistry.instance.fetchEntryMetadataVersion(songId, variation);
      meta = version != null ? SongRegistry.instance.parseEntryMetadataWithMigration(songId, variation, version) : null;
      var chartVersion = SongRegistry.instance.fetchEntryChartVersion(songId, variation);
      chart = chartVersion != null ? SongRegistry.instance.parseEntryChartDataWithMigration(songId, variation, chartVersion) : null;
    }
    catch (e)
    {
      trace('[QOL] Could not load song $songId: $e');
    }
    if (meta == null) return null;
    if (chart == null) chart = emptyChart(meta.playData.difficulties);
    var model = new ChartModel(songId, meta, chart);
    model.variation = variation;
    model.qolSong = funkin.qol.runtime.QOLPlayHooks.loadSongData(songId);
    if (model.qolSong.strumlines == null) model.qolSong.strumlines = [];
    return model;
  }

  public static function emptyChart(difficulties:Array<String>):SongChartData
  {
    var speeds = new Map<String, Float>();
    var notes = new Map<String, Array<SongNoteData>>();
    for (d in difficulties)
    {
      speeds.set(d, 1.0);
      notes.set(d, []);
    }
    var c = new SongChartData(speeds, [], notes);
    return c;
  }

  /**
   * Make a brand new song.
   */
  public static function create(songId:String, name:String, artist:String, bpm:Float, player:String, opponent:String, gf:String, stage:String):ChartModel
  {
    var meta = new SongMetadata(name, artist, 'You');
    meta.timeChanges = [new SongTimeChange(0, bpm)];
    meta.playData.difficulties = ['easy', 'normal', 'hard'];
    meta.playData.characters.player = player;
    meta.playData.characters.opponent = opponent;
    meta.playData.characters.girlfriend = gf;
    meta.playData.stage = stage;
    meta.playData.ratings = ['easy' => 1, 'normal' => 3, 'hard' => 5];
    var chart = emptyChart(meta.playData.difficulties);
    return new ChartModel(songId, meta, chart);
  }

  //
  // Accessors
  //

  public function ensureDifficulty(diff:String):Void
  {
    if (!chart.notes.exists(diff)) chart.notes.set(diff, []);
    if (!chart.scrollSpeed.exists(diff)) chart.scrollSpeed.set(diff, chart.scrollSpeed.get('default') ?? 1.0);
    if (!metadata.playData.difficulties.contains(diff)) metadata.playData.difficulties.push(diff);
  }

  public var notes(get, never):Array<SongNoteData>;

  function get_notes():Array<SongNoteData>
  {
    ensureDifficulty(difficulty);
    return chart.notes.get(difficulty);
  }

  public var events(get, never):Array<SongEventData>;

  function get_events():Array<SongEventData>
  {
    if (chart.events == null) chart.events = [];
    return chart.events;
  }

  public var scrollSpeed(get, set):Float;

  function get_scrollSpeed():Float
    return chart.scrollSpeed.get(difficulty) ?? 1.0;

  function set_scrollSpeed(v:Float):Float
  {
    chart.scrollSpeed.set(difficulty, v);
    return v;
  }

  public function sortNotes():Void
  {
    notes.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : a.data - b.data));
  }

  public function sortEvents():Void
  {
    events.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
  }

  /**
   * Number of strumlines shown: at least 2, plus every configured extra one, plus any that has notes.
   */
  public function strumlineCount():Int
  {
    var count = 2;
    for (sl in qolSong.strumlines)
      count = Std.int(Math.max(count, sl.index + 1));
    for (n in notes)
      count = Std.int(Math.max(count, n.getStrumlineIndex() + 1));
    return count;
  }

  public function extraStrumline(index:Int):Null<QOLStrumlineData>
  {
    for (sl in qolSong.strumlines)
      if (sl.index == index) return sl;
    return null;
  }

  /**
   * Index of the first note at or after `time` (binary search; notes must be sorted).
   */
  public function firstNoteIndexAt(time:Float):Int
  {
    var list = notes;
    var lo = 0;
    var hi = list.length;
    while (lo < hi)
    {
      var mid = (lo + hi) >> 1;
      if (list[mid].time < time) lo = mid + 1;
      else
        hi = mid;
    }
    return lo;
  }

  //
  // Commands (undo / redo)
  //

  public function settingsSnapshot():String
  {
    return haxe.Json.stringify({
      meta: metadata.serialize(false),
      speeds: [for (k => v in chart.scrollSpeed) {k: k, v: v}],
      qol: qolSong
    });
  }

  function restoreSettings(snapshot:String):Void
  {
    var parsed:Dynamic = haxe.Json.parse(snapshot);
    var restored = SongRegistry.instance.parseEntryMetadataRaw(parsed.meta, 'undo', variation);
    if (restored != null) metadata = restored;
    var speeds:Array<Dynamic> = parsed.speeds;
    for (s in speeds)
      chart.scrollSpeed.set(s.k, s.v);
    qolSong = parsed.qol;
  }

  /**
   * Apply a change and remember it for undo.
   */
  public function apply(cmd:ChartCommand):Void
  {
    run(cmd, false);
    undoStack.push(cmd);
    if (undoStack.length > 300) undoStack.shift();
    redoStack = [];
    if (onChange != null) onChange();
  }

  /**
   * Record a settings change that already happened (`before` was taken with `settingsSnapshot()`).
   */
  public function recordSettings(name:String, before:String):Void
  {
    var after = settingsSnapshot();
    if (after == before) return;
    undoStack.push({name: name, settingsBefore: before, settingsAfter: after});
    redoStack = [];
    if (onChange != null) onChange();
  }

  public function undo():Null<String>
  {
    var cmd = undoStack.pop();
    if (cmd == null) return null;
    run(cmd, true);
    redoStack.push(cmd);
    if (onChange != null) onChange();
    return cmd.name;
  }

  public function redo():Null<String>
  {
    var cmd = redoStack.pop();
    if (cmd == null) return null;
    run(cmd, false);
    undoStack.push(cmd);
    if (onChange != null) onChange();
    return cmd.name;
  }

  function run(cmd:ChartCommand, reverse:Bool):Void
  {
    var add = reverse ? cmd.removeNotes : cmd.addNotes;
    var rem = reverse ? cmd.addNotes : cmd.removeNotes;
    var addE = reverse ? cmd.removeEvents : cmd.addEvents;
    var remE = reverse ? cmd.addEvents : cmd.removeEvents;
    var list = notes;
    if (rem != null) for (n in rem)
      list.remove(n);
    if (add != null) for (n in add)
      list.push(n);
    if (add != null && add.length > 0) sortNotes();
    var elist = events;
    if (remE != null) for (e in remE)
      elist.remove(e);
    if (addE != null) for (e in addE)
      elist.push(e);
    if (addE != null && addE.length > 0) sortEvents();
    var settings = reverse ? cmd.settingsBefore : cmd.settingsAfter;
    if (settings != null) restoreSettings(settings);
  }

  //
  // Saving
  //

  function suffix():String
    return (variation == null || variation == Constants.DEFAULT_VARIATION) ? '' : '-$variation';

  /**
   * Write the metadata, chart and QOL song settings into the active mod. Returns the chart path.
   */
  public function save():String
  {
    sortNotes();
    sortEvents();
    // Keep every difficulty in the metadata in sync with the chart.
    for (d in chart.notes.keys())
      if (!metadata.playData.difficulties.contains(d)) metadata.playData.difficulties.push(d);
    var base = 'data/songs/$songId/$songId';
    ModWorkspace.saveText('$base-metadata${suffix()}.json', metadata.serialize());
    var chartPath = ModWorkspace.saveText('$base-chart${suffix()}.json', chart.serialize());
    var cleaned:QOLSongData = {version: '1.0.0', strumlines: qolSong.strumlines};
    if (cleaned.strumlines.length > 0) ModWorkspace.saveJson('data/qol/songs/$songId.json', cleaned, ['version', 'strumlines', 'index', 'name']);
    return chartPath;
  }

  public function cloneSong():QOLSongData
    return QOLJson.clone(qolSong);
}
