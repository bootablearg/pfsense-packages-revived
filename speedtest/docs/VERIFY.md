# Verification checklist — speedtest

What was actually run, on a real pfSense box, and what is still open.

## Environment

| | |
|---|---|
| Product | pfSense CE 2.9.0-RELEASE |
| ABI | `FreeBSD:16:amd64` |
| PHP | 8.5.7 |
| speedtest-cli | 2.1.3 on Python 3.11.15, from pfSense's own repository |

## Done

### 1. The original code against PHP 8.5

```sh
php -l diag_speedtest.php     # -> No syntax errors
php -l speedtest.priv.inc     # -> No syntax errors
```

### 2. Install, registration and removal

The package builds, installs and registers:

```
pfSense-pkg-SpeedTest          1.1.0
menu: SpeedTest                Diagnostics
```

`diag_speedtest.php` returns 200 where a missing file returns 404.

### 3. A real measurement

```sh
/usr/local/bin/speedtest-cli --json
```

returned a complete result — download, upload, ping, the chosen server and the
client's ISP — with `"share": null`, confirming nothing was published. The JSON
matches the shape the results panel reads.

### 4. The obsolete patch

Upstream shipped `speedtest.py.diff`. It is not carried here; the reasoning,
with the evidence, is in [NO-PATCH.md](NO-PATCH.md).

## Changed, and why

- **`--share` is now opt-in.** It was unconditional, and the results panel
  rendered nothing but the image Ookla returns, so a speed test could not be
  run without publishing it. The measurement is parsed and displayed locally;
  sharing is a checkbox that defaults to off.
- **The shared URL is validated and escaped** instead of being interpolated
  into an `<img src>` straight from a remote service's response.
- **Form variables are initialised**, which silences a set of
  undefined-variable warnings on every page load under PHP 8.

## Open

### A. The GUI under load

The page renders, but the results panel has only been exercised with one
successful measurement. A failed test, a timeout, or a machine with several
WANs have not been tried.

### B. Source address selection

The selector is populated from `get_possible_traffic_source_addresses()`, but
the test has only ever been run with the default route. Whether `--source`
actually pins the measurement to a chosen WAN is untested.

### C. pfSense Plus

Untested.
