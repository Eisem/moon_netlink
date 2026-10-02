# MoonNetlink

MoonNetlink is a typed RTNetlink SDK and declarative Linux network state
toolkit for MoonBit.

The repository is currently in its feasibility-probe phase. The first target
is a native MoonBit program that opens an `AF_NETLINK` socket, sends
`RTM_GETLINK`, decodes the multipart response in MoonBit, and finds the Linux
loopback interface without invoking the `ip` command.

See [TODO.md](./TODO.md) for the project goals, architecture, safety model,
scope, milestones, and acceptance criteria.

## Current probe

On Linux with MoonBit and a C compiler:

```sh
moon run --target native examples/inspect_links
```

Expected output contains a line for the loopback interface named `lo`.

## Platform

MoonNetlink currently targets Linux on MoonBit's native backend. It does not
modify network state in the feasibility probe.

## License

MIT
