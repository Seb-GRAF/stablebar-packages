# Fern

A floating olive-black strip, 40 points tall and 6 points from the screen's edges, with widgets
in pill groups, a pale-lime accent and Material-style tonal states. In the light appearance, the
strip turns pale with an olive-green accent.

## Font

Fern is set in [Rubik](https://fonts.google.com/specimen/Rubik). Install it with
`brew install --cask font-rubik` or from Google Fonts. Until it's installed, StableBar uses the
system font.

## Pills

Fern puts your widgets in pills on the raised surface, and your clocks in a lime pill. They need
no `group` of their own, and they leave the pills when you select another theme. This needs
StableBar 0.18 or later.

For System and Disk, choose **Label, value and meter** in the widget's **Content → Display**
settings for a label and percentage on one line, above a progress line. For the Store's Now
playing, choose **Bar look: Player** in its package settings. These choices stay selected under
other themes.

| Pill | Widgets |
| --- | --- |
| `workspaces` | `workspaces` |
| `media` | The Store's Now playing (`now-playing`) |
| `system` | `system` |
| `disk` | `disk`, which turns amber as the disk nears full and red when it's almost full |
| `status` | `audio`, `wifi`, `network`, `bluetooth` and `battery` |
| `clock` | `clock` |
| `meeting` | The widget whose `id` is `meeting`, such as the meetings widget that setup adds |

Widgets in the same pill sit together where the first one is, in the order of your widget list.

To put another widget in a pill, such as one of your scripts, give it the pill's name in `group`.
Other themes don't define these groups, and a widget in an unknown group stops the configuration
from loading. So set that `group` in a profile with `"when": { "theme": "fern" }`, or declare the
group in your configuration with an empty style, such as `"groups": { "status": { "style": {} } }`.

To keep widgets out of a pill, set its `members` in such a profile: your list replaces Fern's.
`"groups": { "status": { "members": [{ "type": "battery" }] } }` keeps only the battery in the
status pill, and `[]` empties it.

The `time` role draws a widget as a lime chip that turns solid while its popup is open. Fern also
styles the `heading`, `key`, `value`, `button` and `meter` roles for popups.

## AeroSpace modes

While AeroSpace is in any mode other than `main`, the strip's border turns amber.

## Sliders

Fern draws plain sliders as pills filled with its accent, pale lime in the dark appearance and
olive in the light one, on the same track as its meters: 40 points tall in popups and hover
tooltips, and as tall as the widget's content inline. Sound's built-in hover slider follows the
same style and changes the volume as you drag. Sliders need a StableBar that knows the `slider`
role; the Store keeps offering Fern 1.3.0 to older versions.

A slider with `"filled": false` keeps macOS's control. A slider with `"filled": true` keeps
its own style; assign it `"role": "slider"` to use Fern's slider style explicitly.
