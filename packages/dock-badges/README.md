# Dock badges

Shows each running app's icon and Dock badge side by side. Set **App names** to a comma-separated
list, such as `Mail,Slack,Messages,Microsoft Teams`. Click the widget for the total and app list,
then click a popup row to open that app.

Requires StableBar `0.10.0-beta.20261102092627.570` or later and `jq`.
No tokens, network requests or macOS permissions are needed.

Nonnumeric badges such as Slack's dot appear alongside the icons and in the popup, but do not count toward
the total. Apps without a badge show `0`; apps that are not running are omitted.
Counts depend on each app's Dock badge settings and update every ten seconds.
