# Amazon `q` Sandbox Bootstrap

A simple script for launching Amazon `q` in a sandboxed environment on Linux.

It assumes you already have AWS credentials and, if needed, Amazon `q` login state under your normal user account.

## Installation

**Note:** `install-q.sh` can create any sandbox username you choose with `-u <q-user>`. The examples below use `<q-user>` for the sandbox account and `<q-home>` for that user's home directory.

Download the repo.

```
- README.md         This file
- install-q.sh      Run this first to create the sandbox user
- start-q.sh        Template startup script for the sandbox user
- AmazonQ.md        Bootstrap instructions automatically read by `q`
```

### Installation Script

Run `install-q.sh`, specifying a username, e.g.

```
sudo ./install-q.sh -u <q-user>
```

The installation script will do the following:

1. Create the specified sandbox user and home directory `<q-home>`.
2. Copy your AWS configuration plus either static credentials or SSO cache to `<q-home>`.
3. Copy your local Amazon `q` state to `<q-home>` if it exists.
4. Copy `start-q.sh`, `AmazonQ.md`, and `README.md` to `<q-home>`.
5. Set the sandbox user's primary group to your primary group, then make directories under `<q-home>` mode `770` and regular files mode `660` so both accounts can update them.
6. Make `start-q.sh` read/execute-only so it is less likely to be edited accidentally.

## Running `start-q.sh`

The installed `start-q.sh` does the following:

1. Checks whether the sandbox user is already logged in to Amazon `q`
2. Runs `q login` only if needed
3. Starts `q` as the sandbox user
4. Starts in the sandbox user's home directory by default
5. Accepts `-d <dir>` to start `q` in a specific directory instead

Examples:

```
start-q.sh
start-q.sh -d .
start-q.sh -d /path/to/project
```

## Amazon `q` Startup Behavior

When Amazon `q` starts in a directory, it automatically reads these files if they are present:

```
AmazonQ.md
AGENTS.md
README.md
```

It can also read Markdown rule files under:

```
.amazonq/rules/**/*.md
```

In this repo, `AmazonQ.md` is the main bootstrap file for local instructions. `AGENTS.md` is optional if you want to add more agent-specific guidance in a local copy.

Note that `q` will not be able to write to directories it is started in unless they are writable by the sandbox user or its primary group.

The sandbox user must also be able to traverse the full path to that directory.

By default, the installer makes the sandbox user's primary group match your primary group. To create a directory that both you and the sandbox user can modify while preserving personal ownership:

```
mkdir <dir>
chmod 770 <dir>
sudo chgrp <your-primary-group> <dir>
```
