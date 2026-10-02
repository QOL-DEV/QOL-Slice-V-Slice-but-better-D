package funkin.qol.events;

import funkin.data.event.SongEventSchema;
import funkin.data.event.SongEventSchema.SongEventFieldType;
import funkin.data.song.SongData.SongEventData;
import funkin.data.stage.StageRegistry;
import funkin.play.PlayState;
import funkin.play.event.SongEvent;

/**
 * QOL SLICE: switch to a different stage in the middle of a song.
 * Stages used by this event are built before the song starts, so the swap is instant.
 */
class ChangeStageSongEvent extends SongEvent
{
  public function new()
  {
    super('ChangeStage', {processOldEvents: true});
  }

  override public function handleEvent(data:SongEventData):Void
  {
    if (PlayState.instance == null || PlayState.instance.isMinimalMode) return;
    var stage = data.getString('stage');
    if (stage == null || stage == '') return;
    var flash = data.getBool('flash') ?? false;
    PlayState.instance.qol?.changeStage(stage);
    if (flash) PlayState.instance.camGame.flash(flixel.util.FlxColor.WHITE, 0.5, null, true);
  }

  override public function getTitle():String
    return 'Change Stage';

  override public function getEventSchema():SongEventSchema
  {
    var keys = new Map<String, Dynamic>();
    for (id in StageRegistry.instance.listEntryIds())
      keys.set(id, id);
    return new SongEventSchema([
      {
        name: 'stage',
        title: 'Stage',
        defaultValue: 'mainStage',
        type: SongEventFieldType.ENUM,
        keys: keys
      },
      {
        name: 'flash',
        title: 'Flash white',
        defaultValue: false,
        type: SongEventFieldType.BOOL
      }
    ]);
  }
}
