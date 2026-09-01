# Why there is no speedtest.py patch here

The upstream package shipped `usr/local/pkg/speedtest.py.diff`, a patch against
speedtest-cli:

```python
ignore_servers = list(
-   map(int, server_config['ignoreids'].split(','))
+   map(int, (server_config['ignoreids'].split(',') if len(server_config['ignoreids']) else []) )
)
```

It worked around a crash when the server list came back with an empty
`ignoreids`, and it was written against
`/usr/local/lib/python3.7/site-packages/speedtest.py`.

It is not shipped here, for two reasons.

**The bug is fixed upstream.** speedtest-cli 2.1.3, which is what pfSense's own
repository provides, reads:

```python
int(i) for i in server_config['ignoreids'].split(',') if i
```

The trailing `if i` is the same guard, arrived at independently.

**The path no longer exists.** pfSense 2.9 runs Python 3.11, so the patch's
target file is not there to patch.

Shipping it would mean carrying a patch that cannot apply, against a bug that
is not present, into a directory where nothing would ever read it.

Verified on pfSense CE 2.9.0-RELEASE with speedtest-cli 2.1.3 on Python 3.11.15.
