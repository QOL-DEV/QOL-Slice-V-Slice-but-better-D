package funkin.qol.events;

import funkin.data.event.SongEventSchema;
import funkin.data.event.SongEventSchema.SongEventFieldType;
import funkin.data.song.SongData.SongEventData;
import funkin.play.PlayState;
import funkin.play.event.SongEvent;
import funkin.qol.runtime.QOLStageEvents;

/**
 * QOL SLICE: plays a stage event made in the Background Editor (move props, play animations, flash...).
 */
class StageEventSongEvent extends SongEvent
{
  public function new()
  {
    super('StageEvent');
  }

  override public function handleEvent(data:SongEventData):Void
  {
    var ps = PlayState.instance;
    if (ps == null || ps.isMinimalMode) return;
    var key = data.getString('event');
    if (key == null || key == '') return;
    ps.qol?.runStageEvent(key);
  }

  override public function getTitle():String
    return 'Stage Event';

  override public function getEventSchema():SongEventSchema
  {
    var keys = new Map<String, Dynamic>();
    for (e in QOLStageEvents.listAll())
      keys.set(e.label, e.key);
    if (Lambda.count(keys) == 0) keys.set('(make stage events in the Background Editor)', '');
    return new SongEventSchema([
      {
        name: 'event',
        title: 'Stage event',
        defaultValue: '',
        type: SongEventFieldType.ENUM,
        keys: keys
      }
    ]);
  }
}
