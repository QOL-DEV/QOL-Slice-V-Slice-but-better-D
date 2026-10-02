package funkin.qol.util;

import flixel.FlxG;
import flixel.FlxState;
import flixel.graphics.FlxGraphic;

/**
 * Engine-wide memory and speed helpers.
 *
 * - GPU textures: during gameplay, once an image (character, stage, notes...) has been uploaded to the graphics card,
 *   the copy kept in normal memory is freed. Big spritesheets are only needed on the GPU to be drawn, so this roughly
 *   halves what they cost. Editors keep their copies (some tools read pixels).
 * - Memory cleanup: when you leave an editor or the Mod Menu, images nothing uses any more are dropped from the asset
 *   cache and the garbage collector gives the memory back.
 */
class QOLPerformance
{
  static var initialized:Bool = false;
  static var sweepTimer:Float = 0;
  static var leavingHeavyState:Bool = false;

  /**
   * How many texture copies have been freed (shown in Engine Settings).
   */
  public static var freedTextures(default, null):Int = 0;

  public static var freedBytes(default, null):Float = 0;

  public static function init():Void
  {
    if (initialized) return;
    initialized = true;
    FlxG.signals.preStateSwitch.add(onPreStateSwitch);
    FlxG.signals.postStateSwitch.add(onPostStateSwitch);
    FlxG.signals.postUpdate.add(onPostUpdate);
  }

  /**
   * Editors and the Mod Menu load lots of characters and stages for their previews.
   */
  static function isHeavyState(state:Null<FlxState>):Bool
  {
    if (state == null) return false;
    #if FEATURE_HAXEUI
    if (Std.isOfType(state, funkin.qol.ui.QOLEditorState)) return true;
    #end
    return Std.isOfType(state, funkin.qol.menu.QOLModMenuState);
  }

  static function onPreStateSwitch():Void
  {
    leavingHeavyState = isHeavyState(FlxG.state);
  }

  static function onPostStateSwitch():Void
  {
    sweepTimer = 0.5;
    if (leavingHeavyState && QOLConfig.cleanMemory) cleanUp();
    leavingHeavyState = false;
  }

  static function onPostUpdate():Void
  {
    sweepTimer -= FlxG.elapsed;
    if (sweepTimer > 0) return;
    sweepTimer = 1.5;
    if (QOLConfig.gpuTextures && inGameplay()) offloadTextures();
  }

  static function inGameplay():Bool
  {
    var play = funkin.play.PlayState.instance;
    // Playtests from the editors are left alone (the editor comes back right after).
    return play != null && play.exists && !play.isChartingMode;
  }

  /**
   * Free the normal-memory copy of every gameplay image that is already on the graphics card.
   * @return How many were freed.
   */
  public static function offloadTextures():Int
  {
    var context = FlxG.stage?.context3D;
    if (context == null) return 0; // Software rendering needs the copies.
    var count = 0;
    @:privateAccess
    var cache:Map<String, FlxGraphic> = FlxG.bitmap._cache;
    if (cache == null) return 0;
    for (key => graphic in cache)
    {
      if (graphic == null || graphic.bitmap == null) continue;
      var bitmap = graphic.bitmap;
      if (!bitmap.readable || bitmap.image == null) continue;
      if (!offloadable(key)) continue;
      var bytes = bitmap.width * bitmap.height * 4.0;
      try
      {
        bitmap.getTexture(context); // Make sure it's uploaded first.
        bitmap.disposeImage();
        bitmap.getTexture(context); // Drops the copy now that the image isn't readable.
        // Anything that loads this image again gets a fresh, readable copy from disk.
        if (openfl.utils.Assets.cache.hasBitmapData(key)) openfl.utils.Assets.cache.removeBitmapData(key);
        count++;
        freedBytes += bytes;
      }
      catch (e)
      {
        trace('[QOL] Could not move $key to the GPU: $e');
      }
    }
    freedTextures += count;
    if (count > 0) trace('[QOL] Moved $count images to the GPU (${Math.round(freedBytes / 1048576)} MB of RAM saved so far).');
    return count;
  }

  static function isImageAsset(key:String):Bool
  {
    if (key == null) return false;
    return key.indexOf('images/') >= 0 && (StringTools.endsWith(key, '.png') || StringTools.endsWith(key, '.jpg'));
  }

  /**
   * Menu images stay readable (a few menus copy pixels out of them); the big savings are characters, stages and notes.
   */
  static final KEEP_READABLE:Array<String> = [
    '/ui/', 'freeplay', 'mainmenu', 'storymenu', 'charSelect', 'titleEnter', 'stageBuild', 'menu', 'stickers', 'results'
  ];

  static function offloadable(key:String):Bool
  {
    if (!isImageAsset(key)) return false;
    for (part in KEEP_READABLE)
      if (key.indexOf(part) >= 0) return false;
    return true;
  }

  /**
   * Drop cached images nothing is using, then run a full garbage collection.
   */
  public static function cleanUp():Void
  {
    var cache = Std.downcast(openfl.utils.Assets.cache, openfl.utils.AssetCache);
    if (cache != null)
    {
      @:privateAccess
      var bitmaps = cache.bitmapData;
      if (bitmaps != null)
      {
        for (key in [for (k in bitmaps.keys()) k])
        {
          if (!isImageAsset(key)) continue;
          var graphic = FlxG.bitmap.get(key);
          if (graphic == null || graphic.bitmap == null) cache.removeBitmapData(key);
        }
      }
    }
    #if cpp
    funkin.util.MemoryUtil.collect(true);
    funkin.util.MemoryUtil.compact();
    #end
  }
}
