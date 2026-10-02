package funkin.qol.util;

import funkin.audio.FunkinSound;
import funkin.audio.VoicesGroup;
import funkin.play.song.Song;

/**
 * Loads a song's instrumental and vocals for editors.
 *
 * Desktop builds preload every asset, so this is instant there. Web builds load the song's
 * files straight from their URLs (loading the whole `songs` library would download every song).
 */
class QOLSongAudio
{
  /**
   * @param cb Called with the instrumental (null if missing) and the vocals (may be empty).
   */
  public static function load(song:Song, difficulty:String, variation:String, cb:(Null<FunkinSound>, Null<VoicesGroup>) -> Void):Void
  {
    var diff = song.getDifficulty(difficulty, variation);
    #if html5
    if (openfl.utils.Assets.getLibrary('songs') == null)
    {
      loadWeb(song, diff, variation, cb);
      return;
    }
    #end
    var inst:Null<FunkinSound> = null;
    var vocals:Null<VoicesGroup> = null;
    try
    {
      var instPath = diff != null ? diff.getInstPath() : Paths.inst(song.id);
      if (Assets.exists(instPath)) inst = FunkinSound.load(instPath, 1.0, false, false, false, false, null, null, true);
      if (diff != null) vocals = diff.buildVocals();
    }
    catch (e)
    {
      trace('[QOL] Song audio failed: $e');
    }
    cb(inst, vocals);
  }

  #if html5
  static function loadWeb(song:Song, diff:Null<funkin.play.song.Song.SongDifficulty>, variation:String, cb:(Null<FunkinSound>, Null<VoicesGroup>) -> Void):Void
  {
    var varSuffix = (variation == null || variation == Constants.DEFAULT_VARIATION) ? '' : '-$variation';
    function url(path:String):String
      return path.substr(path.indexOf(':') + 1);
    openfl.media.Sound.loadFromFile(url(Paths.inst(song.id, varSuffix))).onComplete(function(snd) {
      var inst = FunkinSound.load(snd, 1.0, false, false, false, false, null, null, true);
      var vocals = new VoicesGroup();
      var chars = diff?.characters;
      if (chars != null)
      {
        for (pair in [{c: chars.player, player: true}, {c: chars.opponent, player: false}])
        {
          var p = pair;
          openfl.media.Sound.loadFromFile(url(Paths.voices(song.id, '-${p.c}$varSuffix'))).onComplete(function(v) {
            var sound = FunkinSound.load(v, 1.0, false, false, false, false, null, null, true);
            if (sound == null) return;
            if (p.player) vocals.addPlayerVoice(sound);
            else
              vocals.addOpponentVoice(sound);
          });
        }
      }
      cb(inst, vocals);
    }).onError(function(_) cb(null, null));
  }
  #end
}
