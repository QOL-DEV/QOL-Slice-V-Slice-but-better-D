package funkin.qol.events;

import funkin.data.event.SongEventSchema;
import funkin.data.event.SongEventSchema.SongEventFieldType;
import funkin.data.song.SongData.SongEventData;
import funkin.play.PlayState;
import funkin.play.event.SongEvent;

/**
 * QOL SLICE: shake the screen.
 */
class CameraShakeSongEvent extends SongEvent
{
  public function new()
  {
    super('CameraShake');
  }

  override public function handleEvent(data:SongEventData):Void
  {
    var ps = PlayState.instance;
    if (ps == null) return;
    var intensity = data.getFloat('intensity') ?? 0.01;
    var duration = QOLEventUtil.stepsToSeconds(data.getFloat('duration') ?? 4);
    switch (data.getString('camera') ?? 'game')
    {
      case 'hud':
        ps.camHUD.shake(intensity, duration);
      case 'both':
        ps.camGame.shake(intensity, duration);
        ps.camHUD.shake(intensity, duration);
      default:
        ps.camGame.shake(intensity, duration);
    }
  }

  override public function getTitle():String
    return 'Camera Shake';

  override public function getEventSchema():SongEventSchema
  {
    return new SongEventSchema([
      {
        name: 'intensity',
        title: 'Intensity',
        defaultValue: 0.01,
        min: 0,
        max: 0.5,
        step: 0.005,
        type: SongEventFieldType.FLOAT
      },
      {
        name: 'duration',
        title: 'Duration',
        defaultValue: 4.0,
        min: 0,
        step: 0.5,
        type: SongEventFieldType.FLOAT,
        units: 'steps'
      },
      {
        name: 'camera',
        title: 'Camera',
        defaultValue: 'game',
        type: SongEventFieldType.ENUM,
        keys: ['Game' => 'game', 'HUD' => 'hud', 'Both' => 'both']
      }
    ]);
  }
}
