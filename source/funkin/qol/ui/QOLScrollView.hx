package funkin.qol.ui;

#if FEATURE_HAXEUI
import haxe.ui.containers.ScrollView;
import haxe.ui.events.ScrollEvent;

/**
 * A vertical-only scroll view.
 *
 * HaxeUI still keeps a hidden horizontal scrollbar when the contents are a few pixels wider than the view, and
 * focusing something (opening a dropdown or color picker) could scroll it sideways, cutting off the left edge of
 * every label. This one always snaps back.
 */
class QOLScrollView extends ScrollView
{
  public function new()
  {
    super();
    horizontalScrollPolicy = 'never';
    registerEvent(ScrollEvent.CHANGE, function(_) {
      if (horizontalScrollPolicy == 'never' && hscrollPos != 0) hscrollPos = 0;
    });
  }
}
#end
