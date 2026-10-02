package funkin.qol.guide;

typedef GuidePage =
{
  var id:String;
  var title:String;
  var body:String;
}

/**
 * The text of the built-in guide.
 */
class GuideContent
{
  public static final PAGES:Array<GuidePage> = [
    {
      id: 'welcome',
      title: 'Welcome to QOL Slice',
      body: '
QOL Slice is a Friday Night Funkin\' engine built on V-Slice, with editors for almost everything.

# Opening the Mod Menu
Press 7 (or ~) on the main menu.
'
    }
  ];

  public static function get(id:String):Null<GuidePage>
  {
    for (page in PAGES)
      if (page.id == id) return page;
    return null;
  }
}
