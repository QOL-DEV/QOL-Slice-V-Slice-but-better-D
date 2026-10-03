package funkin.qol.editors.animator;

#if FEATURE_HAXEUI
import funkin.qol.editors.animator.AnimData;
import openfl.media.SoundChannel;
import openfl.media.SoundTransform;

/**
 * Plays an Animator timeline's sound layers: in sync while playing, and short snippets while dragging the playhead
 * (like Flash's sound scrubbing).
 */
class AnimAudioPlayer
{
  var ed:AnimatorState;
  var active:Map<AnimLayer, {key:AnimKeyframe, channel:SoundChannel}> = new Map();
  var scrubs:Array<{channel:SoundChannel, until:Float}> = [];
  var lastFrame:Int = -1;
  var wasPlaying:Bool = false;

  /**
   * Play a bit of sound when the playhead moves while stopped.
   */
  public var scrub:Bool = true;

  public function new(ed:AnimatorState)
  {
    this.ed = ed;
    scrub = QOLConfig.getPref('animator.scrubSound', true);
  }

  static function audioLayers(sym:AnimSymbol):Array<AnimLayer>
    return [for (l in sym.layers) if (l.kind == 'audio' && l.visible) l];

  function soundKey(layer:AnimLayer, frame:Int):Null<AnimKeyframe>
  {
    var key = AnimData.keyAt(layer, frame);
    return key != null && key.sound != null ? key : null;
  }

  /**
   * Call every frame.
   */
  public function update(playing:Bool, frame:Int):Void
  {
    var now = haxe.Timer.stamp();
    var i = scrubs.length - 1;
    while (i >= 0)
    {
      if (now >= scrubs[i].until)
      {
        var ch = scrubs[i].channel;
        scrubs.splice(i, 1);
        stopChannel(ch);
      }
      i--;
    }
    if (!playing)
    {
      if (wasPlaying) stopPlayback();
      wasPlaying = false;
      lastFrame = frame;
      return;
    }
    var fps = ed.doc.project.fps;
    // A jump (looping, or the playhead moved) restarts the sounds at the right spot.
    var jumped = !wasPlaying || frame < lastFrame || frame > lastFrame + 2;
    wasPlaying = true;
    var layers = audioLayers(ed.sym);
    for (layer => cur in active)
    {
      if (!layers.contains(layer))
      {
        active.remove(layer);
        stopChannel(cur.channel);
      }
    }
    for (layer in layers)
    {
      var key = soundKey(layer, frame);
      var cur = active.get(layer);
      if (key == null)
      {
        if (cur != null)
        {
          active.remove(layer);
          stopChannel(cur.channel);
        }
        continue;
      }
      if (cur != null && cur.key == key && !jumped) continue;
      active.remove(layer);
      if (cur != null) stopChannel(cur.channel);
      var ch = start(layer, key, frame, fps);
      if (ch != null) active.set(layer, {key: key, channel: ch});
    }
    lastFrame = frame;
  }

  function start(layer:AnimLayer, key:AnimKeyframe, frame:Int, fps:Float):Null<SoundChannel>
  {
    var snd = ed.doc.getSound(key.sound);
    if (snd == null) return null;
    var pos = (key.soundStart ?? 0) + (frame - key.start) / fps;
    if (pos < 0 || pos >= snd.length) return null;
    var s = snd.getSound();
    if (s == null) return null;
    try
    {
      return s.play(pos * 1000, 0, new SoundTransform(layer.volume ?? 1));
    }
    catch (e:Dynamic)
    {
      return null;
    }
  }

  /**
   * A short snippet at a frame (when the playhead is moved by hand).
   */
  public function scrubAt(frame:Int):Void
  {
    if (!scrub) return;
    var fps = ed.doc.project.fps;
    for (layer in audioLayers(ed.sym))
    {
      var key = soundKey(layer, frame);
      if (key == null) continue;
      var ch = start(layer, key, frame, fps);
      if (ch != null) scrubs.push({channel: ch, until: haxe.Timer.stamp() + Math.max(0.06, 1.6 / fps)});
    }
  }

  public function stopPlayback():Void
  {
    var list = [for (cur in active) cur.channel];
    active.clear();
    for (ch in list)
      stopChannel(ch);
  }

  public function stopAll():Void
  {
    stopPlayback();
    var list = scrubs;
    scrubs = [];
    for (s in list)
      stopChannel(s.channel);
  }

  /**
   * Stopping a sound the browser never got to start throws; that's fine.
   */
  static function stopChannel(ch:SoundChannel):Void
  {
    try
    {
      ch.stop();
    }
    catch (e:Dynamic) {}
  }
}
#end
