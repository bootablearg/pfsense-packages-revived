# wpad — automatic proxy discovery for pfSense

Serves `wpad.dat` and `proxy.pac` from the firewall, so browsers find the proxy
by themselves instead of being configured one machine at a time.

Revived from [Marcello Coutinho's wpad package](https://github.com/marcelloc/Unofficial-pfSense-packages),
ported to pfSense CE 2.9 / PHP 8.5. Apache-2.0; see [LICENSE](LICENSE).

## Why this matters

A proxy nobody reaches is not a proxy. Squid, e2guardian and the reporting
packages in this repository are only useful once traffic actually goes through
them, and getting it there means either touching every browser or publishing a
PAC file. This publishes it.

Chained with [samba-ad](../samba-ad/), the end result is a workstation that
joins the network, discovers the proxy, authenticates with Kerberos and browses
through the filter — with nobody having configured or typed anything.

## What it installs

No binary from any repository: it runs a second, small nginx, which pfSense
already ships. The package is six config files, one GUI page and a privilege
definition.

```sh
./install.sh check      # reports what it would do; changes nothing
./install.sh install
./install.sh remove
```

It appears under **System → Package Manager** and the trash icon removes it.

## Configuring it

**Services → WPAD.** Pick the interface and port to listen on, and supply the
PAC content. The package can serve either a static file or a PHP script (if the
content starts with `<?php` it is executed, and `.pac`, `.dat` and `.da` are
mapped to the PHP handler as well).

Then point clients at it, either way round:

- **DHCP option 252** — `http://<firewall>/wpad.dat`, under the DHCP server's
  advanced options.
- **DNS** — a `wpad` A record pointing at the firewall. Note that browsers have
  become progressively more suspicious of DNS-based WPAD; DHCP is the more
  reliable of the two.

## Caveats

- It listens on a port of its own. Port 80 on the firewall may already be taken
  by the redirect to the web GUI — check before choosing it.
- WPAD is a trust-on-first-use mechanism by design: anything that can answer
  DHCP or DNS on that network can point browsers at a proxy of its choosing.
  That is a property of WPAD, not of this package, but it is worth knowing
  before deploying it on a network you do not control.

## Status

Installs, registers and its GUI page loads on CE 2.9.0-RELEASE. **It has not
yet served a PAC file to a real client** — see [docs/VERIFY.md](docs/VERIFY.md)
for exactly what was and was not tested.
