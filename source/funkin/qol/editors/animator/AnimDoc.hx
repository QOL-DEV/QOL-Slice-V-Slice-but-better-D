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

  var undoStack:Array<AnimSnapshot> = [];
  var redoStack:Array<AnimSnapshot> = [];

  public static inline final MAX_UNDO:Int = 60;

  public function new(project:AnimProject)
  {
    this.project = project;
  }

  public var main(get, never):AnimSymbol;

  inline function get_main():AnimSymbol
    return project.symbols[0];

  // Lookups by id, rebuilt when the lists change (big documents have hundreds of symbols).
  var symIndex:Map<String, AnimSymbol> = new Map();
  var symIndexOf:Null<Array<AnimSymbol>> = null;
  var symIndexLen:Int = -1;
  var bmpIndex:Map<String, AnimBitmapInfo> = new Map();
  var bmpIndexOf:Null<Array<AnimBitmapInfo>> = null;
  var bmpIndexLen:Int = -1;

  public function symbol(id:String):Null<AnimSymbol>
  {
    if (id == null) return null;
    if (symIndexOf != project.symbols || symIndexLen != project.symbols.length) rebuildSymIndex();
    var s = symIndex.get(id);
    if (s != null && s.id == id) return s;
    // Ids can be changed in place; look again.
    rebuildSymIndex();
    return symIndex.get(id);
  }

  function rebuildSymIndex():Void
  {
    symIndex = new Map();
    for (s in project.symbols)
      symIndex.set(s.id, s);
    symIndexOf = project.symbols;
    symIndexLen = project.symbols.length;
  }

  public function bitmapInfo(id:String):Null<AnimBitmapInfo>
  {
    if (id == null) return null;
    if (bmpIndexOf != project.bitmaps || bmpIndexLen != project.bitmaps.length)
    {
      bmpIndex = new Map();
      for (b in project.bitmaps)
        bmpIndex.set(b.id, b);
      bmpIndexOf = project.bitmaps;
      bmpIndexLen = project.bitmaps.length;
    }
    var b = bmpIndex.get(id);
    return b != null && b.id == id ? b : null;
  }

  //
  // Undo
  //

  /**
   * The document as JSON, in pieces: one per layer. Big documents (an imported .fla can be tens of megabytes) would be
   * slow to save whole for every undo step, so pieces that haven't changed since the last snapshot are reused (and
   * shared between undo steps): symbols not being edited are reused as they are, and in the ones being edited only
   * layers whose contents changed are saved again.
   */
  public function snapshot():AnimSnapshot
  {
    var syms:Array<AnimSymbolJson> = [];
    var newSymJson = new haxe.ds.ObjectMap<AnimSymbol, AnimSymbolJson>();
    var newLayerJson = new haxe.ds.ObjectMap<AnimLayer, AnimLayerJson>();
    for (sym in project.symbols)
    {
      var cached = symJson.get(sym);
      var changed = cached == null || allDirty || dirty.exists(sym.id) || cached.id != sym.id || cached.layers.length != sym.layers.length;
      if (!changed)
      {
        for (i in 0...sym.layers.length)
        {
          var lj = layerJson.get(sym.layers[i]);
          if (lj != cached.layers[i])
          {
            changed = true;
            break;
          }
        }
      }
      if (changed)
      {
        var head:Dynamic = {};
        for (f in Reflect.fields(sym))
          if (f != 'layers') Reflect.setField(head, f, Reflect.field(sym, f));
        var layers:Array<AnimLayerJson> = [];
        for (l in sym.layers)
        {
          var lj = layerJson.get(l);
          // Symbols marked changed are checked layer by layer; a layer is saved again only if it changed.
          var fp = AnimLayerJson.fingerprint(l);
          if (lj == null || lj.fp != fp) lj = new AnimLayerJson(haxe.Json.stringify(l), fp);
          layers.push(lj);
        }
        cached = new AnimSymbolJson(sym.id, haxe.Json.stringify(head), layers);
      }
      newSymJson.set(sym, cached);
      for (i in 0...sym.layers.length)
        newLayerJson.set(sym.layers[i], cached.layers[i]);
      syms.push(cached);
    }
    symJson = newSymJson;
    layerJson = newLayerJson;
    var meta:Dynamic = {};
    for (f in Reflect.fields(project))
      if (f != 'symbols') Reflect.setField(meta, f, Reflect.field(project, f));
    // Symbols being edited can change before the next snapshot; nothing else does (see `touch`).
    dirty = new Map();
    allDirty = false;
    if (editingId != null) dirty.set(editingId, true);
    return {
      meta: haxe.Json.stringify(meta),
      syms: syms,
      library: [for (b in project.bitmaps) if (b.library == true) b.id]
    };
  }

  function restore(snap:AnimSnapshot):Void
  {
    // Layers that are the same as now are kept as they are (no need to read them back).
    var current = new haxe.ds.ObjectMap<AnimLayerJson, AnimLayer>();
    for (l => lj in layerJson)
      current.set(lj, l);
    var p:AnimProject = haxe.Json.parse(snap.meta);
    p.symbols = [];
    symJson = new haxe.ds.ObjectMap();
    layerJson = new haxe.ds.ObjectMap();
    for (c in snap.syms)
    {
      var sym:AnimSymbol = haxe.Json.parse(c.head);
      sym.layers = [];
      for (lj in c.layers)
      {
        var l = current.get(lj);
        if (l == null) l = haxe.Json.parse(lj.json);
        else
          current.remove(lj);
        sym.layers.push(l);
        layerJson.set(l, lj);
      }
      symJson.set(sym, c);
      p.symbols.push(sym);
    }
    project = p;
    dirty = new Map();
    allDirty = false;
    if (editingId != null) dirty.set(editingId, true);
  }

  var layerJson = new haxe.ds.ObjectMap<AnimLayer, AnimLayerJson>();
  var symJson = new haxe.ds.ObjectMap<AnimSymbol, AnimSymbolJson>();
  var dirty = new Map<String, Bool>();
  var allDirty:Bool = false;
  var editingId:Null<String> = null;

  /**
   * The symbol the editor is changing (it's saved again for every undo step).
   */
  public function setEditing(id:String):Void
  {
    if (id == editingId) return;
    if (editingId != null) dirty.set(editingId, true);
    dirty.set(id, true);
    editingId = id;
  }

  /**
   * A symbol other than the one being edited changed (rename, library edits...).
   */
  public function touch(id:String):Void
    dirty.set(id, true);

  /**
   * Many symbols changed.
   */
  public function touchAll():Void
    allDirty = true;

  /**
   * Call before making a change (it saves the current state for undo).
   */
  public function checkpoint():Void
  {
    undoStack.push(snapshot());
    if (undoStack.length > MAX_UNDO) undoStack.shift();
    redoStack = [];
    // Unused bitmaps are only cleaned up now and then.
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
    restore(undoStack.pop());
    changed();
    return true;
  }

  public function redo():Bool
  {
    if (redoStack.length == 0) return false;
    undoStack.push(snapshot());
    restore(redoStack.pop());
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
   * Forget canvases and sounds nothing (the project or any undo step) refers to. Library images and sounds stay.
   */
  public function pruneBitmaps():Void
  {
    var used = new Map<String, Bool>();
    var seen = new haxe.ds.ObjectMap<AnimSymbolJson, Bool>();
    for (snap in [snapshot()].concat(undoStack).concat(redoStack))
    {
      for (c in snap.syms)
      {
        if (seen.exists(c)) continue;
        seen.set(c, true);
        for (id in c.ids())
          used.set(id, true);
      }
      for (id in snap.library)
        used.set(id, true);
    }
    for (b in project.bitmaps)
      if (b.library == true) used.set(b.id, true);
    if (project.sounds != null) for (sn in project.sounds)
      used.set(sn.id, true);
    for (id in [for (k in bitmaps.keys()) k])
    {
      if (!used.exists(id))
      {
        bitmaps.get(id)?.dispose();
        bitmaps.remove(id);
      }
    }
    project.bitmaps = [for (b in project.bitmaps) if (bitmaps.exists(b.id)) b];
    for (id in [for (k in sounds.keys()) k])
    {
      if (!used.exists(id))
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

typedef AnimSnapshot =
{
  var meta:String;
  var syms:Array<AnimSymbolJson>;

  /**
   * Library images at the time (kept even when nothing uses them).
   */
  var library:Array<String>;
}

/**
 * One symbol in an undo step: its own fields, and its layers (shared between steps while they don't change).
 */
class AnimSymbolJson
{
  public var id:String;
  public var head:String;
  public var layers:Array<AnimLayerJson>;

  public function new(id:String, head:String, layers:Array<AnimLayerJson>)
  {
    this.id = id;
    this.head = head;
    this.layers = layers;
  }

  /**
   * Bitmap and sound ids it uses.
   */
  public function ids():Array<String>
  {
    var out:Array<String> = [];
    for (l in layers)
      for (id in l.ids())
        out.push(id);
    return out;
  }
}

/**
 * One layer's JSON in an undo step, with a quick fingerprint of its contents (to notice when it changed).
 */
class AnimLayerJson
{
  public var json:String;
  public var fp:Float;

  var idList:Null<Array<String>> = null;

  public function new(json:String, fp:Float)
  {
    this.json = json;
    this.fp = fp;
  }

  public function ids():Array<String>
  {
    if (idList != null) return idList;
    idList = [];
    var re = ~/"((?:bmp|snd)-[0-9a-z]+)"/g;
    var pos = 0;
    while (re.matchSub(json, pos))
    {
      idList.push(re.matched(1));
      var mp = re.matchedPos();
      pos = mp.pos + mp.len;
    }
    return idList;
  }

  /**
   * A number that changes when anything in the layer changes (much quicker than writing it out). Long number lists
   * (shape outlines) are sampled: outlines are replaced, not edited in place.
   */
  public static function fingerprint(v:Dynamic):Float
  {
    counter = 0;
    return hash(v);
  }

  static var counter:Int = 0;

  static inline function weight():Float
  {
    counter++;
    return 1 + ((counter * 40503) & 1023) / 1024;
  }

  static function hash(v:Dynamic):Float
  {
    if (v == null) return 0.37 * weight();
    switch (Type.typeof(v))
    {
      case TInt | TFloat:
        var f:Float = v;
        return (Math.isNaN(f) ? 0.5 : f + 0.11) * weight();
      case TBool:
        return (v ? 0.71 : 0.29) * weight();
      case TClass(String):
        var s:String = v;
        var h = s.length * 1.7;
        var n = s.length;
        if (n <= 24)
        {
          for (i in 0...n)
            h = h * 1.31 + StringTools.fastCodeAt(s, i);
        }
        else
        {
          for (i in 0...12)
            h = h * 1.31 + StringTools.fastCodeAt(s, i) + StringTools.fastCodeAt(s, n - 1 - i);
          h += StringTools.fastCodeAt(s, n >> 1);
        }
        return h * weight();
      case TClass(Array):
        var a:Array<Dynamic> = v;
        var n = a.length;
        var h = n * 3.1 * weight();
        if (n > 24 && Type.typeof(a[0]) != TObject && !Std.isOfType(a[0], Array))
        {
          // A long list of numbers: sample it.
          var step = Std.int(Math.max(1, n / 16));
          var i = 0;
          while (i < n)
          {
            h += hash(a[i]);
            i += step;
          }
          h += hash(a[n - 1]) + hash(a[n - 2]);
          return h;
        }
        for (e in a)
          h += hash(e);
        return h;
      case TObject:
        var h = 0.0;
        for (f in Reflect.fields(v))
        {
          var fv:Dynamic = Reflect.field(v, f);
          if (fv == null) continue;
          h += (f.length + StringTools.fastCodeAt(f, 0) * 0.013) * weight() + hash(fv);
        }
        return h;
      default:
        return 0.0;
    }
  }
}
