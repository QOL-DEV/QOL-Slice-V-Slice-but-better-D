package funkin.qol.editors.modchart;

import funkin.qol.runtime.QOLModchart;
import funkin.qol.runtime.QOLModchart.QOLModchartData;
import funkin.qol.runtime.QOLModchart.QOLModchartRuntime;
import funkin.qol.runtime.QOLModchart.QOLModHost;
import funkin.qol.runtime.QOLModchart.QOLModKey;
import funkin.qol.runtime.QOLModchart.QOLModTrack;

/**
 * A key on a track, as selected in the timeline.
 */
typedef ModKeyRef =
{
  var track:QOLModTrack;
  var key:QOLModKey;
}

/**
 * The modchart being edited, with undo/redo (whole-document snapshots; modcharts are small).
 */
class ModchartDoc
{
  public var data:QOLModchartData;

  var undoStack:Array<String> = [];
  var redoStack:Array<String> = [];

  /**
   * Called after anything changes.
   */
  public var onChange:Null<Void->Void> = null;

  public function new(data:QOLModchartData)
  {
    this.data = QOLModchart.normalize(data);
  }

  public function snapshot():String
    return haxe.Json.stringify(data);

  /**
   * Call BEFORE making a change, so it can be undone.
   */
  public function checkpoint():Void
  {
    pushUndo(snapshot());
  }

  /**
   * Push a snapshot taken earlier (e.g. at the start of a drag), if anything changed since.
   */
  public function commitFrom(before:String):Void
  {
    if (before == snapshot()) return;
    pushUndo(before);
  }

  function pushUndo(s:String):Void
  {
    undoStack.push(s);
    if (undoStack.length > 200) undoStack.shift();
    redoStack = [];
  }

  /**
   * Call AFTER a change.
   */
  public function changed():Void
  {
    if (onChange != null) onChange();
  }

  public var canUndo(get, never):Bool;

  function get_canUndo():Bool
    return undoStack.length > 0;

  public function undo():Bool
  {
    var s = undoStack.pop();
    if (s == null) return false;
    redoStack.push(snapshot());
    restore(s);
    return true;
  }

  public function redo():Bool
  {
    var s = redoStack.pop();
    if (s == null) return false;
    undoStack.push(snapshot());
    restore(s);
    return true;
  }

  function restore(s:String):Void
  {
    data = QOLModchart.normalize(haxe.Json.parse(s));
    changed();
  }

  //
  // Tracks
  //

  public function findTrack(target:String, prop:String):Null<QOLModTrack>
  {
    for (t in data.tracks)
      if (t.target == target && t.prop == prop) return t;
    return null;
  }

  public function tracksOf(target:String):Array<QOLModTrack>
  {
    var list = [for (t in data.tracks) if (t.target == target) t];
    // Keep tracks in catalog order so the timeline is stable.
    var kind = QOLModchart.targetKind(target);
    var order = [for (p in QOLModchart.propsFor(kind)) p.id];
    list.sort((a, b) -> order.indexOf(a.prop) - order.indexOf(b.prop));
    return list;
  }

  public function hasTracks(target:String):Bool
  {
    for (t in data.tracks)
      if (t.target == target) return true;
    return false;
  }

  public function addTrack(target:String, prop:String):QOLModTrack
  {
    var existing = findTrack(target, prop);
    if (existing != null) return existing;
    var t:QOLModTrack = {target: target, prop: prop, keys: []};
    data.tracks.push(t);
    return t;
  }

  public function removeTrack(track:QOLModTrack):Void
    data.tracks.remove(track);

  //
  // Keys
  //

  public static inline final SAME_TIME:Float = 0.0005;

  public function keyAt(track:QOLModTrack, beat:Float):Null<QOLModKey>
  {
    for (k in track.keys)
      if (Math.abs(k.t - beat) < SAME_TIME) return k;
    return null;
  }

  /**
   * Set the value at a time: updates the key there, or inserts a new one (keeping its neighbours' eases).
   */
  public function setKey(track:QOLModTrack, beat:Float, value:Float, ?ease:String):QOLModKey
  {
    var k = keyAt(track, beat);
    if (k != null)
    {
      k.v = value;
      if (ease != null) k.e = ease;
      return k;
    }
    k = {t: beat, v: value};
    if (ease != null) k.e = ease;
    track.keys.push(k);
    QOLModchart.sortKeys(track);
    return k;
  }

  public function removeKey(track:QOLModTrack, key:QOLModKey):Void
    track.keys.remove(key);

  public function allKeys():Array<ModKeyRef>
  {
    var out:Array<ModKeyRef> = [];
    for (t in data.tracks)
      for (k in t.keys)
        out.push({track: t, key: k});
    return out;
  }

  /**
   * Last key time across the whole modchart (beats).
   */
  public function lastBeat():Float
  {
    var last = 0.0;
    for (t in data.tracks)
      if (t.keys.length > 0) last = Math.max(last, t.keys[t.keys.length - 1].t);
    return last;
  }
}
