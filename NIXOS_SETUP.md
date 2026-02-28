# NixOS Dev Environment Setup

Getting the full `obsidian-publish` dev environment running on NixOS - Rust, Node, Bun, SQLite, and Rust Rover configured correctly.

---

## Why NixOS needs a different approach

On a standard Linux distro, you install Rust via `rustup`, Node via `nvm`, and libraries like OpenSSL land in `/usr/lib`. Tools like Rust Rover find everything automatically because paths are predictable.

NixOS doesn't work that way. There is no `/usr/lib`. Every package lives in `/nix/store/some-hash-package-version/`. Nothing is global. This is what makes NixOS reproducible - but it also means your editor, your Rust build scripts, and your IDE all need to be told explicitly where things are.

The solution is a `flake.nix` that defines the entire dev environment, and `direnv` to activate it automatically when you enter the project folder.

---

## Prerequisites

Before starting, make sure these are enabled on your NixOS system. Add them to your `configuration.nix` if not already present:

```nix
# /etc/nixos/configuration.nix
programs.direnv.enable = true;

# nix flakes must be enabled
nix.settings.experimental-features = ["nix-command" "flakes"];
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

---

## Quick start

```bash
git clone git@github.com:yourname/obsidian-publish.git
cd obsidian-publish
direnv allow       # activates the dev shell automatically
cargo --version    # should print cargo version - environment is live
```

---

## Project file structure

Two files at the project root control the entire environment:

```
obsidian-publish/
├── flake.nix           ← defines what tools are available
├── flake.lock          ← pins exact versions (commit this to git)
├── rust-toolchain.toml ← pins the Rust version for cargo + flake
└── .envrc              ← tells direnv to activate the flake
```

---

## Setting up from scratch

### Step 1 - Initialize the repo

```bash
mkdir obsidian-publish
cd obsidian-publish
git init
```

### Step 2 - Add the vault as a git submodule

Your Obsidian vault is a separate repo. Add it as a submodule so the project tracks it without merging the two histories:

```bash
git submodule add git@github.com:yourname/your-vault.git vault
```

> **Warning:** Do NOT create the `vault/` folder manually before running this command. If the folder already exists, git will refuse to add the submodule. If you already created it, delete it first with `rm -rf vault/` then run the command above.

### Step 3 - Create the flake files

Create `flake.nix` at the project root. See [flake.nix reference](#flake-reference) below for the full file.

Create `rust-toolchain.toml` at the project root:

```toml
[toolchain]
channel = "stable"
components = ["rustc", "cargo", "rust-src", "rust-analyzer", "clippy", "rustfmt"]
```

> **Warning:** Nix uses a strict TOML parser. Values must be quoted strings. The array must be on one line. Comments inside the file can cause parse errors in some Nix versions - keep this file minimal.

### Step 4 - Create the .envrc for direnv

```bash
echo "use flake" > .envrc
direnv allow
```

After `direnv allow`, every time you `cd` into the project the dev shell activates automatically. Your terminal prompt will change and all tools become available.

### Step 5 - Stage everything with git

> **Warning:** Nix flakes only see files that git knows about. Untracked files are invisible to Nix - even if they exist on disk. Always run `git add` after creating new files, before running `nix develop`.

```bash
git add .
```

### Step 6 - Create the Rust projects

Now that the dev shell is active, create the Rust binaries:

```bash
cargo new indexer
cargo new webhook
```

> **Warning:** If you run `cargo new` before `git init`, cargo creates its own `.git` inside the folder. This confuses git - it thinks `indexer/` is an unregistered submodule. Fix it by deleting the nested `.git`: `rm -rf indexer/.git webhook/.git`, then `git add .` again.

### Step 7 - Verify everything works

```bash
rustc --version    # rustc 1.x.x (stable)
cargo --version    # cargo 1.x.x
node --version     # v22.x.x
bun --version      # 1.x.x
git --version      # git 2.x.x
```

---

## Configuring Rust Rover

Rust Rover needs to know where the Rust toolchain and stdlib live. Since everything is in `/nix/store`, you have to point it there manually.

### Finding the correct paths

Run these inside the active dev shell (after `direnv allow` or `nix develop`):

```bash
# find the toolchain bin path
which rustc
# example output: /nix/store/5wrimps5b834byfw1qx15754hy849hxm-rust-default-1.93.1/bin/rustc

# find the sysroot (used for stdlib)
rustc --print sysroot
# example output: /nix/store/5wrimps5b834byfw1qx15754hy849hxm-rust-default-1.93.1

# find the exact stdlib path
find $(rustc --print sysroot) -name "library" -type d
# example output: /nix/store/5wrimps5b834byfw1qx15754hy849hxm-rust-default-1.93.1/lib/rustlib/src/rust/library
```

### Setting the paths in Rust Rover

Go to **Settings → Rust**:

| Field | Value |
|---|---|
| Toolchain location | output of `which rustc`, minus the `/rustc` at the end - so just the `/bin` folder |
| Standard library | output of the `find` command above - the full path ending in `/library` |

Click **Apply** then **OK**.

> **Note:** These paths will change every time the Nix store hash changes (i.e. when you update nixpkgs). The direnv approach below avoids having to redo this manually.

### Better approach - launch Rust Rover from the shell

If you launch Rust Rover from inside the active dev shell, it inherits all paths automatically and finds the toolchain without any manual configuration:

```bash
# from inside the project with direnv active
rust-rover .
```

---

## How direnv works with this project

`direnv` watches the `.envrc` file. When it contains `use flake`, direnv evaluates the `flake.nix` and exports all the env vars (`PATH`, `OPENSSL_LIB_DIR`, `PKG_CONFIG_PATH`, etc.) into your shell session automatically on `cd`.

This means:
- No need to run `nix develop` manually every time
- Rust Rover and other GUI tools launched from the terminal inherit the correct environment
- Every team member gets the exact same environment on every machine

The first activation is slow (Nix downloads packages). Every activation after that is instant because Nix caches everything in `/nix/store`.

---

## Common errors and fixes

### `error: opening file '...rust-toolchain.toml': No such file or directory`

The file exists on disk but git hasn't tracked it yet.

```bash
git add rust-toolchain.toml
nix develop
```

### `error: 'indexer/' does not have a commit checked out`

`cargo new` created a `.git` inside `indexer/` before the parent repo existed.

```bash
rm -rf indexer/.git
rm -rf webhook/.git
git add .
```

### `error: while parsing TOML: unknown value appeared`

The `rust-toolchain.toml` has unquoted values or inline comments that Nix's TOML parser rejects.

Replace the file contents with exactly:

```toml
[toolchain]
channel = "stable"
components = ["rustc", "cargo", "rust-src", "rust-analyzer", "clippy", "rustfmt"]
```

### `Invalid standard library` in Rust Rover

Rust Rover is pointing to the sysroot root instead of the `library` subdirectory. Run:

```bash
find $(rustc --print sysroot) -name "library" -type d
```

Paste the full output path into **Settings → Rust → Standard library**.

### Cargo build fails with OpenSSL errors

The dev shell env vars aren't active. Either run `nix develop` first, or make sure `direnv allow` has been run and direnv is enabled in your shell.

```bash
# check if direnv is hooked into your shell
direnv status
```

If direnv isn't hooked, add this to your shell config (`~/.zshrc` or `~/.bashrc`):

```bash
eval "$(direnv hook zsh)"   # for zsh
eval "$(direnv hook bash)"  # for bash
```

---

## flake.nix reference

Full annotated `flake.nix` for this project. Every section is explained inline.

```nix
{
  description = "Obsidian Publish - self-hosted Obsidian publishing platform";

  inputs = {
    # the main package registry - using unstable for latest versions
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # cross-platform helper - handles x86_64, aarch64, darwin automatically
    flake-utils.url = "github:numtide/flake-utils";

    # gives us control over exact Rust toolchain version
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        # reads rust-toolchain.toml - single source of truth for Rust version
        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

      in {
        devShells.default = pkgs.mkShell {
          name = "obsidian-publish";

          buildInputs = [
            rustToolchain        # rustc, cargo, rust-analyzer, clippy, rustfmt
            pkgs.nodejs_22       # Node 22 + npm
            pkgs.bun             # fast JS runtime for Hono API
            pkgs.git             # needed by indexer/webhook as subprocess
            pkgs.pkg-config      # lets Rust find C libraries on NixOS
            pkgs.openssl         # for HTTPS in webhook HMAC verification
            pkgs.sqlite          # native sqlite lib for rusqlite
            pkgs.gcc             # C compiler for rusqlite bundled sqlite
            pkgs.cargo-watch     # auto-recompile on file changes
            pkgs.just            # command runner for dev scripts
            pkgs.bacon           # better error display than cargo-watch
            pkgs.curl            # test webhook endpoints manually
            pkgs.jq              # pretty-print JSON API responses
          ];

          # NixOS doesn't use standard /usr/lib paths.
          # These env vars tell Rust build scripts where to find C libraries.
          env = {
            OPENSSL_NO_VENDOR    = "1";
            OPENSSL_LIB_DIR      = "${pkgs.openssl.out}/lib";
            OPENSSL_INCLUDE_DIR  = "${pkgs.openssl.dev}/include";
            PKG_CONFIG_PATH      = "${pkgs.openssl.dev}/lib/pkgconfig";
            SQLITE3_LIB_DIR      = "${pkgs.sqlite.out}/lib";
          };

          shellHook = ''
            echo ""
            echo "obsidian-publish dev shell"
            echo "--------------------------"
            echo "rust:  $(rustc --version)"
            echo "cargo: $(cargo --version)"
            echo "node:  $(node --version)"
            echo "bun:   $(bun --version)"
            echo ""
          '';
        };
      }
    );
}
```

---

## Flake vs Cargo - what each manages

Understanding this prevents a lot of confusion:

| Tool | Manages | Where things live |
|---|---|---|
| Nix / flake.nix | System tools - rustc, cargo, Node, OpenSSL, SQLite | `/nix/store/...` |
| Cargo / Cargo.toml | Rust crates - serde, rayon, rusqlite, clap | `project/target/` |

Cargo uses the `rustc` that Nix provides. It does not install its own compiler. When a Rust crate needs a C library (like `rusqlite` needing SQLite), Cargo finds it via the env vars that the flake sets. They don't conflict - they cooperate.

---

## Updating the environment

To update all Nix inputs to their latest versions:

```bash
nix flake update
git add flake.lock
git commit -m "chore: update nix flake inputs"
```

To update only nixpkgs:

```bash
nix flake lock --update-input nixpkgs
```

After updating, `direnv` will automatically reload the environment on the next `cd` into the project.
