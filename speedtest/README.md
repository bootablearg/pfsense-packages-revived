# speedtest — bandwidth test from the firewall

Measures download, upload and latency from the firewall itself, choosing which
source address to test from.

Revived from [Marcello Coutinho's speedtest package](https://github.com/marcelloc/Unofficial-pfSense-packages),
ported to pfSense CE 2.9 / PHP 8.5. Apache-2.0 and BSD-2-Clause; see
[LICENSE](LICENSE).

## Why measure from here

A result taken on a workstation cannot separate "the WAN link is slow" from
"the path between this desk and the firewall is slow". Measuring at the border
answers the first question directly, and the source-address selector lets you
test through a specific WAN on a multi-homed box.

## What it installs

`speedtest-cli`, which comes from **pfSense's own package repository** — not a
third-party one. Roughly 100 KiB to download.

```sh
./install.sh check      # reports what it would do; changes nothing
./install.sh install
./install.sh remove
```

Then: **Diagnostics → SpeedTest**.

## The result stays here

The original passed `--share` on every run and displayed the result as nothing
but the image Ookla hands back. That meant a speed test could not be run
without publishing it: `speedtest-cli --share` uploads the measurement to
Ookla, who host it at a public URL along with the ISP and approximate location
derived from your public address, and the administrator's browser then fetched
that image from speedtest.net.

Here the numbers are read out of the JSON and shown locally, and **Publish
result** is a checkbox that defaults to off. Tick it and you get the public
link as well, validated and escaped rather than dropped straight into an
`<img src>`.

## Caveats

- The measurement itself contacts speedtest.net's server list and a nearby test
  server. That is unavoidable for this kind of test, and it is the only traffic
  the page generates when sharing is off.
- A speed test saturates the link for its duration. Do not run it on a busy
  production firewall and expect the number to mean much, or the users to be
  pleased.

## Status

**Verified on CE 2.9.0-RELEASE**: a real measurement runs, the JSON parses and
the results panel renders it. See [docs/VERIFY.md](docs/VERIFY.md).
