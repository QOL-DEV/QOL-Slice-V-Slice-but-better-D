package funkin.qol.runtime;

import funkin.data.song.SongRegistry;
import funkin.data.story.level.LevelRegistry;
import funkin.qol.util.QOLJson;
import openfl.utils.Assets;

typedef QOLFreeplayExtra =
{
  /**
   * The song's ID.
   */
  var song:String;

  /**
   * The week it's listed with (its capsule label, and where in the list it goes).
   */
  var week:String;
}

typedef QOLFreeplayData =
{
  /**
   * Songs left out of Freeplay.
   */
  var hidden:Array<String>;

  /**
   * Songs added to Freeplay that aren't in any week.
   */
  var extra:Array<QOLFreeplayExtra>;
}

/**
 * Freeplay changes set in the Freeplay Editor (`data/qol/freeplay.json`): hiding songs, and listing songs that aren't
 * in a story mode week.
 */
class QOLFreeplay
{
  public static inline final PATH:String = 'qol/freeplay';

  public static function parse(raw:Dynamic):QOLFreeplayData
  {
    var out:QOLFreeplayData = {hidden: [], extra: []};
    if (raw == null) return out;
    if (Std.isOfType(raw.hidden, Array)) for (id in (raw.hidden : Array<Dynamic>))
      if (Std.isOfType(id, String)) out.hidden.push(id);
    if (Std.isOfType(raw.extra, Array)) for (e in (raw.extra : Array<Dynamic>))
    {
      if (e == null || !Std.isOfType(e.song, String)) continue;
      out.extra.push({song: e.song, week: Std.isOfType(e.week, String) ? e.week : ''});
    }
    return out;
  }

  public static function load():QOLFreeplayData
  {
    try
    {
      var path = Paths.json(PATH);
      if (Assets.exists(path)) return parse(QOLJson.tryParse(Assets.getText(path)));
    }
    catch (e:Dynamic) {}
    return parse(null);
  }

  /**
   * The Freeplay list: every week's songs in story order, then the extra songs after their week's songs, minus the
   * hidden ones. Each entry is `{song, week}`.
   */
  public static function listEntries(data:QOLFreeplayData, ?includeHidden:Bool = false):Array<QOLFreeplayExtra>
  {
    var out:Array<QOLFreeplayExtra> = [];
    var levels = LevelRegistry.instance.listSortedLevelIds();
    for (levelId in levels)
    {
      var level = LevelRegistry.instance.fetchEntry(levelId);
      if (level == null) continue;
      for (songId in level.getSongs())
        out.push({song: songId, week: levelId});
    }
    for (e in data.extra)
    {
      if (Lambda.exists(out, x -> x.song == e.song)) continue;
      var week = levels.contains(e.week) ? e.week : (levels.length > 0 ? levels[0] : null);
      if (week == null) continue;
      var at = -1;
      for (i in 0...out.length)
        if (out[i].week == week) at = i;
      var entry = {song: e.song, week: week};
      if (at < 0) out.push(entry);
      else
        out.insert(at + 1, entry);
    }
    if (!includeHidden) out = out.filter(x -> !data.hidden.contains(x.song));
    return out;
  }

  /**
   * Apply the changes to Freeplay's song list (called by FreeplayState after it lists the weeks' songs).
   */
  public static function apply(songs:Array<Null<funkin.ui.freeplay.FreeplayState.FreeplaySongData>>, state:funkin.ui.freeplay.FreeplayState):Void
  {
    var data = load();
    if (data.hidden.length == 0 && data.extra.length == 0) return;
    var i = songs.length - 1;
    while (i >= 0)
    {
      var s = songs[i];
      if (s != null && data.hidden.contains(@:privateAccess s.songId)) songs.splice(i, 1);
      i--;
    }
    var levels = LevelRegistry.instance.listSortedLevelIds();
    for (e in data.extra)
    {
      if (data.hidden.contains(e.song)) continue;
      if (Lambda.exists(songs, s -> s != null && @:privateAccess s.songId == e.song)) continue;
      if (SongRegistry.instance.fetchEntry(e.song) == null) continue;
      var weekId = levels.contains(e.week) ? e.week : (levels.length > 0 ? levels[0] : null);
      var level = weekId == null ? null : LevelRegistry.instance.fetchEntry(weekId);
      if (level == null) continue;
      var item = new funkin.ui.freeplay.FreeplayState.FreeplaySongData(e.song, level, state);
      var at = -1;
      for (j in 0...songs.length)
        if (songs[j] != null && songs[j].levelId == weekId) at = j;
      if (at < 0) songs.push(item);
      else
        songs.insert(at + 1, item);
    }
  }
}
