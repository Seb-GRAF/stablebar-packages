# Development servers

Shows the number of distinct listening TCP ports owned by your user. **Port range**
defaults to `3000-9999`. The popup lists each port and process and updates every five seconds.
IPv4 and IPv6 sockets from the same process on the same port appear once.

Click an address to open `http://localhost:PORT`. **Stop** sends `SIGTERM` to that process,
after checking that it still owns a listener on that port. This stops the whole process,
including any other ports it serves. It does not force-kill processes or stop their supervisors.

Requires `jq`. The scan uses `lsof` and needs no elevated permissions or network requests.
The range can contain non-HTTP services; opening those in a browser may fail.
