# Dock badges

Adds the numeric Dock badges of running apps. Set **App names** to a comma-separated list,
such as `Mail,Slack,Messages,Microsoft Teams`. Click a popup row to open that app.

Requires `jq`. No tokens, network requests or macOS permissions are needed.

The popup preserves nonnumeric badges such as Slack's dot, but they do not count toward
the total. Apps without a badge show `0`; apps that are not running are omitted.
Counts depend on each app's Dock badge settings and update every ten seconds.
