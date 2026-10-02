package funkin.qol.events;

import flixel.util.FlxColor;
import funkin.data.event.SongEventSchema;
import funkin.data.event.SongEventSchema.SongEventFieldType;
import funkin.data.song.SongData.SongEventData;
import funkin.play.PlayState;
import funkin.play.event.SongEvent;

/**
 * QOL SLICE: flash the screen a color.
 */
class CameraFlashSongEvent extends SongEvent
{
  public function new()
  {
    super('CameraFlash');
  }

  override public function handleEvent(data:SongEventData):Void
  {
    var ps = PlayState.instance;
    if (ps == null) return;
    var color = FlxColor.fromString(data.getString('color') ?? '#FFFFFF') ?? FlxColor.WHITE;
    color.alphaFloat = (data.getFloat('alpha') ?? 1.0).clamp(0, 1);
    var duration = QOLEventUtil.stepsToSeconds(data.getFloat('duration') ?? 4);
    switch (data.getString('camera') ?? 'game')
    {
      case 'hud':
        ps.camHUD.flash(color, duration, null, true);
      case 'both':
        ps.camGame.flash(color, duration, null, true);
        ps.camHUD.flash(color, duration, null, true);
      default:
        ps.camGame.flash(color, duration, null, true);
    }
  }

  override public function getTitle():String
    return 'Camera Flash';

  override public function getEventSchema():SongEventSchema
  {
    return new SongEventSchema([
      {
        name: 'color',
        title: 'Color',
        defaultValue: '#FFFFFF',
        type: SongEventFieldType.STRING
      },
      {
        name: 'alpha',
        title: 'Strength',
        defaultValue: 1.0,
        min: 0,
        max: 1,
        step: 0.05,
        type: SongEventFieldType.FLOAT
      },
      {
        name: 'duration',
        title: 'Fade time',
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
