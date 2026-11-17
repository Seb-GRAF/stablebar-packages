// Prints the widget's JSON: whether Tailscale is connected and, while it is, the popup's exit nodes,
// devices, settings and accounts.
const app = Application.currentApplication()
app.includeStandardAdditions = true
// The shell running a click expands $PACKAGE_DIR, as it does here.
const ts = '"$PACKAGE_DIR/scripts/tailscale.sh"'

// A command's output, or nothing when it fails, as status does while Tailscale isn't running and
// exit-node list does without exit nodes. A CLI that differs from the daemon warns on stderr.
function tailscale(args) {
  try {
    return app.doShellScript(`${ts} ${args} 2> /dev/null`, { alteringLineEndings: false })
  } catch (error) {
    return ''
  }
}

function ipv4(ips) {
  return ips.find((ip) => ip.includes('.'))
}

function checkSymbol(checked) {
  return checked ? 'checkmark.circle.fill' : 'circle'
}

function run() {
  const status = JSON.parse(tailscale('status --json') || '{}')
  let look
  // BackendState is Running, Starting, Stopped, NeedsLogin or NeedsMachineAuth; missing when
  // Tailscale isn't running.
  switch (status.BackendState) {
    case 'Running':
      look = { icon: 'circle.grid.3x3.fill', state: 'active', label: 'Connected', action: 'Disconnect', toggle: `${ts} down` }
      break
    case 'Starting':
      look = { icon: 'circle.grid.3x3', state: '', label: 'Connecting…', action: 'Disconnect', toggle: `${ts} down` }
      break
    case 'NeedsLogin':
    case 'NeedsMachineAuth':
      look = { icon: 'circle.grid.3x3', state: 'warning', label: 'Log in to Tailscale', action: 'Open', toggle: 'open -a Tailscale' }
      break
    case undefined:
      look = { icon: 'circle.grid.3x3', state: 'muted', label: 'Not running', action: 'Open', toggle: 'open -a Tailscale' }
      break
    default:
      look = { icon: 'circle.grid.3x3', state: 'muted', label: 'Disconnected', action: 'Connect', toggle: `${ts} up` }
  }
  const fields = { symbol: look.icon, status: look.label, action: look.action, toggle: look.toggle }
  const lists = {}
  let tooltip = status.BackendState ? look.label : 'Tailscale is not running'

  if (status.BackendState === 'Running') {
    fields.ip = ipv4(status.TailscaleIPs)
    tooltip = `Connected · ${fields.ip}`

    // exit-node list prints a row per exit node: its IP, DNS name, country, city and a status
    // that starts with "selected" for the one in use. Its headings and hints don't start with an IP.
    const nodes = []
    for (const line of tailscale('exit-node list').split('\n')) {
      const [address, host, , , state] = line.trim().split(/ {2,}/)
      if (/^\d/.test(address)) nodes.push({ name: host.split('.')[0], address, selected: state.startsWith('selected') })
    }
    const current = nodes.find((node) => node.selected)
    if (nodes.length) {
      fields.exitNode = current ? current.name : 'None'
      lists.exitNodes = [{ name: 'None', symbol: checkSymbol(!current), select: `${ts} set --exit-node=` }].concat(
        nodes.map((node) => ({ name: node.name, symbol: checkSymbol(node.selected), select: `${ts} set --exit-node=${node.address}` }))
      )
    }

    // Mullvad's exit nodes are peers too, hundreds of them, which Tailscale's own status leaves out.
    lists.devices = Object.values(status.Peer || {})
      .filter((peer) => !peer.DNSName.endsWith('.mullvad.ts.net.'))
      .map((peer) => {
        const ip = ipv4(peer.TailscaleIPs)
        return { name: peer.DNSName.split('.')[0], ip, symbol: peer.Online ? 'circle.fill' : 'circle', copy: `printf %s ${ip} | pbcopy` }
      })
      .sort((a, b) => a.name.localeCompare(b.name))
    if (lists.devices.length) fields.devices = String(lists.devices.length)

    // No stable command reads these preferences; debug prefs prints them as JSON.
    const prefs = tailscale('debug prefs')
    if (prefs) {
      const { CorpDNS, RouteAll, ShieldsUp, ExitNodeAllowLANAccess } = JSON.parse(prefs)
      fields.dns = String(CorpDNS)
      fields.routes = String(RouteAll)
      fields.incoming = String(!ShieldsUp)
      if (current) fields.lanAccess = String(ExitNodeAllowLANAccess)
    }

    // switch --list prints a heading, then each account's ID, tailnet and name, with a * after
    // the current one.
    const accounts = tailscale('switch --list').split('\n').slice(1).filter(Boolean).map((line) => {
      const [id, tailnet, name] = line.split(/ {2,}/)
      return { id, tailnet, name: name.replace(/\*$/, ''), current: name.endsWith('*') }
    })
    if (accounts.length > 1) {
      fields.account = accounts.find((account) => account.current).name
      lists.accounts = accounts.map((account) => ({
        name: account.name,
        tailnet: account.tailnet,
        symbol: checkSymbol(account.current),
        switch: `${ts} switch ${account.id}`,
      }))
    }
  }

  return JSON.stringify({ text: '', icon: look.icon, state: look.state, tooltip, fields, lists })
}
