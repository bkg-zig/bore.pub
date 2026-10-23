# Live URL

`url.md` is written by `start.sh` on this machine and is **not tracked by git**,
because it contains the current password.

It looks like this:

```markdown
# Live URL

## http://bore.pub:46490

| | |
|---|---|
| User | `bkg` |
| Password | `<random, changes each start>` |

| | |
|---|---|
| Local | `http://localhost:42001` |
| Auth | `1` (user bkg) |
| State | `live` |
| Updated | 2026-10-23T00:52:00Z |
```

Check it with `./status.sh`, `cat url.md`, or look at the Pinokio dashboard's
**Live URLs** section, which lists every tunnel including app ports.
