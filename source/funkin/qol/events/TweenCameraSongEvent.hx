package funkin.qol.events;

import flixel.tweens.FlxTween;
import funkin.data.event.SongEventSchema;
import funkin.data.event.SongEventSchema.SongEventFieldType;
import funkin.data.song.SongData.SongEventData;
import funkin.play.PlayState;
import funkin.play.event.SongEvent;
import funkin.qol.util.QOLEase;

/**
 * QOL SLICE: tween the game or HUD camera's angle or alpha (spins, tilts, fade outs...), with any ease.
 */
class TweenCameraSongEvent extends SongEvent
{
  public function new()
  {
    super('TweenCamera');
  }

  override public function handleEvent(data:SongEventData):Void
  {
    var ps = PlayState.instance;
    if (ps == null) return;
    var cam:flixel.FlxCamera = (data.getString('camera') ?? 'game') == 'hud' ? ps.camHUD : ps.camGame;
    var prop = data.getString('property') ?? 'angle';
    var value = data.getFloat('value') ?? 0;
    var ease = data.getString('ease') ?? 'quadOut';
    var duration = QOLEventUtil.stepsToSeconds(data.getFloat('duration') ?? 4);
    FlxTween.cancelTweensOf(cam, [prop]);
    if (ease == 'INSTANT' || duration <= 0) Reflect.setProperty(cam, prop, value);
    else
    {
      var props:Dynamic = {};
      Reflect.setField(props, prop, value);
      FlxTween.tween(cam, props, duration, {ease: QOLEase.get(ease)});
    }
  }

  override public function getTitle():String
    return 'Tween Camera (angle / alpha)';

  override public function getEventSchema():SongEventSchema
  {
    return new SongEventSchema([
      {
        name: 'camera',
        title: 'Camera',
        defaultValue: 'game',
        type: SongEventFieldType.ENUM,
        keys: ['Game' => 'game', 'HUD' => 'hud']
      },
      {
        name: 'property',
        title: 'Property',
        defaultValue: 'angle',
        type: SongEventFieldType.ENUM,
        keys: ['Angle' => 'angle', 'Alpha (fade)' => 'alpha']
      },
      {
        name: 'value',
        title: 'Value',
        defaultValue: 0.0,
        step: 1,
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
      QOLEventUtil.easeField('quadOut')
    ]);
  }
}
