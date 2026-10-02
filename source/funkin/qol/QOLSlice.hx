package funkin.qol;

import flixel.FlxState;

/**
 * QOL Slice: a V-Slice based Friday Night Funkin' engine with a full Mod Menu and editors for everything.
 */
class QOLSlice
{
  public static final ENGINE_NAME:String = 'QOL Slice';
  public static final VERSION:String = '1.0.0';
  public static final WINDOW_TITLE:String = 'Friday Night Funkin\': QOL Slice';

  /**
   * The V-Slice version this build is based on, without a leading "v" (e.g. `0.8.6`).
   * This is what mods should use as their `api_version`.
   */
  public static var GAME_VERSION(get, never):String;

  static function get_GAME_VERSION():String
  {
    var v:Null<String> = null;
    try
    {
      v = lime.app.Application.current.meta.get('version');
    }
    catch (e) {}
    return v ?? '0.8.6';
  }

  /**
   * e.g. "QOL Slice v1.0.0 (V-Slice v0.8.6)"
   */
  public static var versionString(get, never):String;

  static function get_versionString():String
    return '$ENGINE_NAME v$VERSION (V-Slice v$GAME_VERSION)';

  /**
   * Whether the Mod Menu can be opened right now (it can be locked for finished mods).
   */
  public static var modMenuAvailable(get, never):Bool;

  static function get_modMenuAvailable():Bool
  {
    #if (FEATURE_HAXEUI && !QOL_LOCK_MOD_MENU)
    return QOLConfig.modMenuEnabled;
    #else
    return false;
    #end
  }

  /**
   * Open the Mod Menu (if it isn't locked).
   */
  public static function openModMenu():Bool
  {
    if (!modMenuAvailable) return false;
    #if FEATURE_HAXEUI
    FlxG.switchState(() -> new funkin.qol.menu.QOLModMenuState());
    return true;
    #else
    return false;
    #end
  }

  /**
   * Called once at startup.
   */
  public static function init():Void
  {
    QOLConfig.reload();
    funkin.qol.runtime.QOLRuntime.init();
    funkin.qol.util.QOLPerformance.init();
    trace('[QOL] $versionString initialized. Mod Menu ${modMenuAvailable ? 'enabled' : 'locked'}.');
  }

  /**
   * Developer helper: lets the web test build jump straight to a tool with `?qol=<tool>` in the URL.
   * Returns true if it switched state.
   */
  /**
   * Open the QOL Chart Editor on a song (used by the chart key in-game).
   */
  public static function openChartEditor(songId:String, ?difficulty:String, ?variation:String, position:Float = 0):Void
  {
    #if FEATURE_HAXEUI
    FlxG.switchState(() -> new funkin.qol.editors.QOLChartEditorState(songId, difficulty, variation, position));
    #end
  }

  public static function devBoot():Bool
  {
    #if (html5 && FEATURE_HAXEUI)
    try
    {
      var search:String = js.Browser.location.search;
      var r = ~/[?&]qol=([A-Za-z0-9_\-]+)/;
      if (!r.match(search)) return false;
      var tool = r.matched(1);
      // Dev: `&fit=1` makes the game fill the browser window like a resized/maximized desktop window (tests layouts and
      // previews at window scales other than 1280x720).
      if (~/[?&]fit=1/.match(search))
      {
        var backend:Dynamic = @:privateAccess lime.app.Application.current.window.__backend;
        backend.resizeElement = true;
        backend.cacheElementWidth = -1;
        js.Browser.window.dispatchEvent(new js.html.Event('resize'));
      }
      var modR = ~/[?&]mod=([A-Za-z0-9_\-]+)/;
      if (modR.match(search))
      {
        var mod = modR.matched(1);
        if (!ModWorkspace.listMods().map(m -> m.folder).contains(mod)) ModWorkspace.createMod(mod, mod);
        ModWorkspace.current = mod;
        QOLConfig.seenWelcome = true;
      }
      var songR = ~/[?&]song=([A-Za-z0-9_\-]+)/;
      if (songR.match(search)) QOLConfig.setPref('chartEditor.last', songR.matched(1));
      if (tool == 'play' && songR.match(search))
      {
        // Dev route: play a song normally (baseline for comparing editor playtests).
        var song = funkin.data.song.SongRegistry.instance.fetchEntry(songR.matched(1));
        openfl.utils.Assets.loadLibrary('shared').onComplete(_ -> {
          funkin.ui.transition.LoadingState.loadPlayState({targetSong: song, targetDifficulty: 'normal'}, true);
        });
        return true;
      }
      // Web builds load the shared library on demand; editors need it (characters, stages...).
      openfl.utils.Assets.loadLibrary('shared').onComplete(function(_) {
        var target = funkin.qol.menu.QOLTools.createTool(tool);
        if (target != null) FlxG.switchState(() -> target);
      }).onError(function(e) {
        var target = funkin.qol.menu.QOLTools.createTool(tool);
        if (target != null) FlxG.switchState(() -> target);
      });
      return true;
    }
    catch (e)
    {
      trace('[QOL] devBoot failed: $e');
    }
    #end
    return false;
  }
}
