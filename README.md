# Amazon `q` Sandbox Bootstrap

A simple script for launching Amazon `q` in a sandboxed environment on Linux.

It assumes you already have AWS credentials and, if needed, Amazon `q` login state under your normal user account.

## Installation

**Note:** All commands shown assume you create the local username **q**. If you choose a different username, modify the command accordingly.

Download the repo. The important files are:

```
- README.md         This file
- start-q.sh        Launches Amazon `q` as user **q**
- AmazonQ.md        Bootstrap instructions automatically read by `q`
```

### Create User **q**

```
sudo useradd -m -s /bin/bash q
```

### Copy AWS credentials

Basic credentials:

```
sudo -u q mkdir -p ~q/.aws
sudo cp ~/.aws/config ~q/.aws/config
sudo cp ~/.aws/credentials ~q/.aws/credentials
sudo chown -R q:q ~q/.aws
sudo chmod 700 ~q/.aws
sudo chmod 600 ~q/.aws/config ~q/.aws/credentials
```

If you use AWS SSO / Identity Center, also copy the SSO cache:

```
sudo mkdir -p ~q/.aws/sso
sudo cp -r ~/.aws/sso/cache ~q/.aws/sso/
sudo chown -R q:q ~q/.aws
```

If you want to reuse your existing Amazon `q` login instead of logging in again as user **q**, also copy Amazon `q`'s local state:

```
sudo mkdir -p ~q/.local/share
sudo cp -r ~/.local/share/amazon-q ~q/.local/share/
sudo chown -R q:q ~q/.local
```

### Copy Repo Files

Place a copy of `start-q.sh` and `AmazonQ.md` in the directory where you want `q` to start.

`start-q.sh` launches `q` from the directory where the script resides, not from the caller's current working directory.

## Running `start-q.sh`

Running `start-q.sh` does the following:

1. Checks whether user **q** is already logged in to Amazon `q`
2. Runs `q login` only if needed
3. Starts `q` as user **q**
4. Uses the directory containing `start-q.sh` as the starting directory

This lets you place separate copies of the script in different directories, each with its own local instructions.

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

In this repo, `AmazonQ.md` is the main bootstrap file for local instructions. `AGENTS.md` is available if you want to add more agent-specific guidance.

Note that `q` will not be able to write to directories it is started in unless they are owned by **q**.

User **q** must also be able to traverse the full path to that directory.

To create a directory that gives `q` read/write permissions while preserving personal ownership:

```
mkdir <dir>
chmod 775 <dir>
sudo chgrp q <dir>
```
