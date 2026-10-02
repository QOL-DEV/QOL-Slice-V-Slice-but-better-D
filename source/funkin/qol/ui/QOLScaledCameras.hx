package funkin.qol.ui;

import flixel.FlxCamera;

/**
 * Shows full-size 1280x720 cameras shrunk into a box on screen (editor previews), with the view math identical to the
 * real game.
 *
 * A camera that is both moved (x/y) and display-scaled draws its contents offset, so the cameras keep x/y = 0 and their
 * display sprites are placed right after Flixel's camera update instead. Anything that sets a camera's x/y (modchart
 * camera offsets) or shakes it still works: those offsets are folded into the placement for the frame.
 */
class QOLScaledCameras
{
  public var cameras:Array<FlxCamera>;
  public var x:Float;
  public var y:Float;
  public var scale:Float;

  var held:Array<Float> = [];

  public function new(cameras:Array<FlxCamera>, x:Float, y:Float, scale:Float)
  {
    this.cameras = cameras;
    this.x = x;
    this.y = y;
    this.scale = scale;
    for (cam in cameras)
    {
      cam.x = 0;
      cam.y = 0;
    }
    place();
    FlxG.signals.postUpdate.add(place);
    FlxG.signals.postDraw.add(restore);
  }

  /**
   * Position the display sprites (runs after Flixel's camera update every frame).
   */
  public function place():Void
  {
    held.resize(0);
    for (cam in cameras)
    {
      var ox = cam.x;
      var oy = cam.y;
      held.push(ox);
      held.push(oy);
      if (ox != 0) cam.x = 0;
      if (oy != 0) cam.y = 0;
      @:privateAccess var shakeX = cam._fxShakeXOffset;
      @:privateAccess var shakeY = cam._fxShakeYOffset;
      cam.flashSprite.scaleX = cam.flashSprite.scaleY = scale;
      cam.flashSprite.x = x + FlxG.width / 2 * scale + ox + shakeX * scale;
      cam.flashSprite.y = y + FlxG.height / 2 * scale + oy + shakeY * scale;
    }
  }

  /**
   * After drawing, give the cameras their x/y back (whoever set them expects to find them next frame).
   */
  function restore():Void
  {
    var i = 0;
    for (cam in cameras)
    {
      var ox = held[i++] ?? 0;
      var oy = held[i++] ?? 0;
      if (ox != 0) cam.x = ox;
      if (oy != 0) cam.y = oy;
    }
  }

  public function destroy():Void
  {
    FlxG.signals.postUpdate.remove(place);
    FlxG.signals.postDraw.remove(restore);
  }
}
