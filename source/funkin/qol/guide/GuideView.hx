package funkin.qol.guide;

#if FEATURE_HAXEUI
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.containers.Box;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ListView;
import haxe.ui.containers.ScrollView;
import haxe.ui.containers.VBox;
import haxe.ui.data.ArrayDataSource;

/**
 * Two-pane guide viewer: a searchable list of topics, and the selected page.
 *
 * Page markup (see `GuideContent`):
 * - `# Heading` and `## Subheading`
 * - `- bullet`
 * - `> tip` (shown in a highlighted box)
 * - lines starting with four spaces are shown as code
 * - blank lines separate paragraphs
 */
class GuideView extends HBox
{
  var list:ListView;
  var search:TextField;
  var scroll:ScrollView;
  var content:VBox;
  var contentWidth:Float;
  var shownIds:Array<String> = [];

  public function new(startPage:String, width:Float, height:Float)
  {
    super();
    this.width = width;
    this.height = height;
    styleString = 'spacing: 10px;';

    var left = new VBox();
    left.width = 240;
    left.height = height;
    left.styleString = 'spacing: 6px;';
    addComponent(left);

    search = new TextField();
    search.placeholder = 'Search the guide...';
    search.percentWidth = 100;
    search.onChange = _ -> fillList();
    left.addComponent(search);

    list = new ListView();
    list.percentWidth = 100;
    list.height = height - 40;
    list.onChange = function(_) {
      if (list.selectedItem != null) showPage(list.selectedItem.id);
    };
    left.addComponent(list);

    scroll = new funkin.qol.ui.QOLScrollView();
    scroll.width = width - 250;
    scroll.height = height;
    scroll.horizontalScrollPolicy = 'never';
    scroll.styleString = 'background-color: #1E1F22; border: 1px solid #3A3F47; padding: 14px;';
    addComponent(scroll);
    contentWidth = width - 250 - 50;

    content = new VBox();
    content.width = contentWidth;
    content.styleString = 'spacing: 6px;';
    scroll.addComponent(content);

    fillList();
    showPage(startPage);
  }

  function fillList()
  {
    var filter = (search.text ?? '').toLowerCase();
    var ds = new ArrayDataSource<Dynamic>();
    shownIds = [];
    for (page in GuideContent.PAGES)
    {
      if (filter != '' && page.title.toLowerCase().indexOf(filter) == -1 && page.body.toLowerCase().indexOf(filter) == -1) continue;
      ds.add({text: page.title, id: page.id});
      shownIds.push(page.id);
    }
    list.dataSource = ds;
  }

  public function showPage(id:String)
  {
    var page = GuideContent.get(id) ?? GuideContent.PAGES[0];
    var idx = shownIds.indexOf(page.id);
    if (idx != -1 && list.selectedIndex != idx) list.selectedIndex = idx;

    content.removeAllComponents();
    var title = new Label();
    title.text = page.title;
    title.width = contentWidth;
    title.styleString = 'font-size: 24px; font-bold: true; color: #5CC8FF;';
    content.addComponent(title);

    var paragraph:Array<String> = [];
    function flush()
    {
      if (paragraph.length == 0) return;
      addText(paragraph.join(' '), '');
      paragraph = [];
    }

    var code:Array<String> = [];
    function flushCode()
    {
      if (code.length == 0) return;
      var l = new Label();
      l.text = code.join('\n');
      l.width = contentWidth;
      l.styleString = 'color: #C3E88D; background-color: #15161A; padding: 8px; border: 1px solid #3A3F47;';
      content.addComponent(l);
      code = [];
    }

    for (rawLine in page.body.split('\n'))
    {
      if (rawLine.startsWith('    '))
      {
        flush();
        code.push(rawLine.substr(4));
        continue;
      }
      flushCode();
      var line = rawLine.trim();
      if (line == '')
      {
        flush();
        continue;
      }
      if (line.startsWith('## '))
      {
        flush();
        addText(line.substr(3), 'font-size: 16px; font-bold: true; color: #FFD24A; padding-top: 6px;');
      }
      else if (line.startsWith('# '))
      {
        flush();
        addText(line.substr(2), 'font-size: 19px; font-bold: true; color: #FF8FB8; padding-top: 10px;');
      }
      else if (line.startsWith('- '))
      {
        flush();
        addText('  •  ' + line.substr(2), '');
      }
      else if (line.startsWith('> '))
      {
        flush();
        var box = new Box();
        box.width = contentWidth;
        box.styleString = 'background-color: #22324A; border: 1px solid #3D6FA8; padding: 8px; border-radius: 4px;';
        var l = new Label();
        l.text = 'TIP: ' + line.substr(2);
        l.width = contentWidth - 20;
        box.addComponent(l);
        content.addComponent(box);
      }
      else
      {
        paragraph.push(line);
      }
    }
    flush();
    flushCode();
    scroll.vscrollPos = 0;
  }

  function addText(text:String, style:String)
  {
    var l = new Label();
    l.text = text;
    l.width = contentWidth;
    if (style != '') l.styleString = style;
    content.addComponent(l);
  }
}
#end
