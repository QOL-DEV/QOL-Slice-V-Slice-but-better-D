package funkin.qol.editors.animator;

import funkin.qol.editors.animator.AnimData;
import openfl.display.BitmapData;

/**
 * An open Animator document: the project data, its bitmaps, and undo/redo.
 *
 * Bitmaps are copy-on-write: before a bitmap is painted on, `editableBitmap` gives the keyframe a fresh copy, so undo
 * snapshots (plain JSON) can keep pointing at the old pixels.
 */
class AnimDoc
{
  public var project:AnimProject;
  public var bitmaps:Map<String, BitmapData> = new Map<String, BitmapData>();
  public var sounds:Map<String, AnimSound> = new Map<String, AnimSound>();

  /**
   * Called after any change (with `structural` = layers/frames changed, not just element properties).
   */
  public var onChange:Null<Void->Void> = null;

  var undoStack:Array<String> = [];
  var redoStack:Array<String> = [];

  public static inline final MAX_UNDO:Int = 60;

  public function new(project:AnimProject)
  {
    this.project = project;
  }

  public var main(get, never):AnimSymbol;

  inline function get_main():AnimSymbol
    return project.symbols[0];

  public function symbol(id:String):Null<AnimSymbol>
  {
    for (s in project.symbols)
      if (s.id == id) return s;
    return null;
  }

  public function bitmapInfo(id:String):Null<AnimBitmapInfo>
  {
    for (b in project.bitmaps)
      if (b.id == id) return b;
    return null;
  }

  //
  // Undo
  //

  public function snapshot():String
    return haxe.Json.stringify(project);

  /**
   * Call before making a change (it saves the current state for undo).
   */
  public function checkpoint():Void
  {
    undoStack.push(snapshot());
    if (undoStack.length > MAX_UNDO) undoStack.shift();
    redoStack = [];
    // Scanning every undo step is slow on big documents, so unused bitmaps are only cleaned up now and then.
    if (++checkpointsSincePrune >= 12)
    {
      checkpointsSincePrune = 0;
      pruneBitmaps();
    }
  }

  var checkpointsSincePrune:Int = 0;

  /**
   * Forget the last checkpoint (when nothing ended up changing).
   */
  public function dropCheckpoint():Void
  {
    undoStack.pop();
  }

  public function changed():Void
  {
    if (onChange != null) onChange();
  }

  public var canUndo(get, never):Bool;

  inline function get_canUndo():Bool
    return undoStack.length > 0;

  public var canRedo(get, never):Bool;

  inline function get_canRedo():Bool
    return redoStack.length > 0;

  public function undo():Bool
  {
    if (undoStack.length == 0) return false;
    redoStack.push(snapshot());
    project = haxe.Json.parse(undoStack.pop());
    changed();
    return true;
  }

  public function redo():Bool
  {
    if (redoStack.length == 0) return false;
    undoStack.push(snapshot());
    project = haxe.Json.parse(redoStack.pop());
    changed();
    return true;
  }

  public function clearHistory():Void
  {
    undoStack = [];
    redoStack = [];
  }

  //
  // Bitmaps
  //

  public function addBitmap(bmp:BitmapData, name:String, library:Bool):String
  {
    var id = AnimData.makeId('bmp');
    bitmaps.set(id, bmp);
    project.bitmaps.push({
      id: id,
      name: name,
      width: bmp.width,
      height: bmp.height,
      library: library
    });
    return id;
  }

  //
  // Sounds
  //

  public function addSound(name:String, rate:Int, channels:Int, pcm:haxe.io.Bytes):AnimSound
  {
    var id = AnimData.makeId('snd');
    var snd = new AnimSound(id, name, rate, channels, pcm);
    sounds.set(id, snd);
    if (project.sounds == null) project.sounds = [];
    project.sounds.push({
      id: id,
      name: name,
      rate: rate,
      channels: snd.channels,
      length: snd.length
    });
    return snd;
  }

  public function getSound(id:Null<String>):Null<AnimSound>
    return id == null ? null : sounds.get(id);

  /**
   * Swap a bitmap's pixels (e.g. a canvas that grew), keeping its id.
   */
  public function replaceBitmap(id:String, bmp:BitmapData):Void
  {
    bitmaps.set(id, bmp);
    var info = bitmapInfo(id);
    if (info != null)
    {
      info.width = bmp.width;
      info.height = bmp.height;
    }
  }

  /**
   * A blank canvas the size of the stage (for bitmap layer keyframes).
   */
  public function newCanvas():String
  {
    return addBitmap(new BitmapData(project.width, project.height, true, 0), 'canvas', false);
  }

  public function getBitmap(id:Null<String>):Null<BitmapData>
    return id == null ? null : bitmaps.get(id);

  /**
   * Give a bitmap-layer keyframe its own copy of its canvas (call before painting, after `checkpoint()`).
   */
  public function editableBitmap(key:AnimKeyframe):BitmapData
  {
    var old = getBitmap(key.bitmap);
    var copy = old != null ? old.clone() : new BitmapData(project.width, project.height, true, 0);
    key.bitmap = addBitmap(copy, 'canvas', false);
    return copy;
  }

  /**
   * Forget bitmaps nothing (the project or any undo step) refers to.
   */
  public function pruneBitmaps():Void
  {
    var used = new Map<String, Bool>();
    var texts = [snapshot()].concat(undoStack).concat(redoStack);
    var re = ~/"(bmp-[0-9a-z]+)"/g;
    for (t in texts)
    {
      var pos = 0;
      while (re.matchSub(t, pos))
      {
        used.set(re.matched(1), true);
        var mp = re.matchedPos();
        pos = mp.pos + mp.len;
      }
    }
    for (id in [for (k in bitmaps.keys()) k])
    {
      if (!used.exists(id))
      {
        bitmaps.get(id)?.dispose();
        bitmaps.remove(id);
      }
    }
    project.bitmaps = [for (b in project.bitmaps) if (bitmaps.exists(b.id)) b];

    // Sounds nothing uses any more.
    var usedSounds = new Map<String, Bool>();
    var sre = ~/"(snd-[0-9a-z]+)"/g;
    for (t in texts)
    {
      var pos = 0;
      while (sre.matchSub(t, pos))
      {
        usedSounds.set(sre.matched(1), true);
        var mp = sre.matchedPos();
        pos = mp.pos + mp.len;
      }
    }
    for (id in [for (k in sounds.keys()) k])
    {
      if (!usedSounds.exists(id))
      {
        sounds.get(id)?.dispose();
        sounds.remove(id);
      }
    }
    if (project.sounds != null) project.sounds = [for (s in project.sounds) if (sounds.exists(s.id)) s];
  }

  /**
   * Bitmap infos that undo steps still need (so `project.bitmaps` can be rebuilt after an undo).
   */
  public function ensureBitmapInfos():Void
  {
    var known = new Map<String, Bool>();
    for (b in project.bitmaps)
      known.set(b.id, true);
    var knownSounds = new Map<String, Bool>();
    if (project.sounds == null) project.sounds = [];
    for (s in project.sounds)
      knownSounds.set(s.id, true);
    for (id => snd in sounds)
    {
      if (!knownSounds.exists(id)) project.sounds.push({
        id: id,
        name: snd.name,
        rate: snd.rate,
        channels: snd.channels,
        length: snd.length
      });
    }
    for (id => bmp in bitmaps)
    {
      if (!known.exists(id) && bmp != null) project.bitmaps.push({
        id: id,
        name: 'canvas',
        width: bmp.width,
        height: bmp.height,
        library: false
      });
    }
  }
}
