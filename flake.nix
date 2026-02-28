{
  # flake.nix — the entry point for everything Nix in this project.
  # This file defines WHO provides our tools (inputs) and WHAT our
  # dev environment looks like (outputs).

  description = "Obsidian Publish — self-hosted Obsidian publishing platform.";

  # ---------------------------------------------------------------------------
  # INPUTS
  # Think of these as your package sources / registries.
  # nixpkgs        → the giant repo of all packages (Rust, Node, sqlite, etc.)
  # flake-utils    → helper library so we don't repeat ourselves per platform
  # rust-overlay   → gives us the exact Rust toolchain we want (stable/nightly)
  #                  without being stuck with whatever nixpkgs ships
  # ---------------------------------------------------------------------------
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";  # unstable-branch

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs"; # use OUR nixpkgs, not rust-overlay's own copy
    };
  };

  # ---------------------------------------------------------------------------
  # OUTPUTS
  # This is what the flake actually produces.
  # We only care about devShells here — the environment you drop into
  # when you run `nix develop`.
  # ---------------------------------------------------------------------------
  outputs = { self, nixpkgs, flake-utils, rust-overlay }: 

    # eachDefaultSystem automatically handles x86_64-linux, aarch64-linux,
    # aarch64-darwin, etc. so you don't hardcode your architecture.
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Apply the rust-overlay on top of nixpkgs so we get access to
        # rust-bin.stable.latest.default and friends.
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        # ---------------------------------------------------------------------------
        # RUST TOOLCHAIN
        # We read rust-toolchain.toml from the repo root so the toolchain
        # definition lives in ONE place — here and cargo both respect it.
        # The file pins the channel (stable), version, and components we need.
        # ---------------------------------------------------------------------------
        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        # ---------------------------------------------------------------------------
        # NATIVE BUILD INPUTS
        # These are C-level libraries and tools that Rust crates need at
        # compile time. Without these, crates like rusqlite (bundled) and
        # openssl will fail to build with cryptic linker errors.
        #
        # pkg-config  → lets the Rust build system find C libraries on NixOS
        #               (NixOS doesn't use standard /usr/lib paths, so this is critical)
        # openssl     → needed by any crate doing HTTPS (webhook signature verification)
        # sqlite      → even though rusqlite bundles sqlite, having it here doesn't hurt
        # gcc         → C compiler needed for rusqlite's bundled sqlite compilation
        # ---------------------------------------------------------------------------
        nativeBuildInputs = with pkgs; [
          pkg-config
          gcc
        ];

        # ---------------------------------------------------------------------------
        # BUILD INPUTS
        # Runtime libraries that the compiled binaries link against.
        # ---------------------------------------------------------------------------
        buildInputs = with pkgs; [
          openssl
          sqlite
        ];

      in
      {
        devShells.default = pkgs.mkShell {
          name = "obsidian-publish";

          # Merge all the inputs together into the shell environment
          nativeBuildInputs = nativeBuildInputs;
          buildInputs = buildInputs ++ [
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

          # -----------------------------------------------------------------------
          # ENVIRONMENT VARIABLES
          # NixOS doesn't put openssl in standard paths, so we have to tell
          # Rust's build scripts exactly where to find it.
          # Without these, `cargo build` on any crate using openssl will fail.
          # -----------------------------------------------------------------------
          env = {
            OPENSSL_NO_VENDOR = "1";   # use system openssl, don't vendor it
            OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
            OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";

            # Tells pkg-config where to look for .pc files on NixOS
            PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";

            # SQLite path — useful if anything needs to find libsqlite3
            SQLITE3_LIB_DIR = "${pkgs.sqlite.out}/lib";
          };

          # -----------------------------------------------------------------------
          # SHELL HOOK
          # Runs every time you enter `nix develop`.
          # Just a welcome message so you know the environment is working.
          # -----------------------------------------------------------------------
          shellHook = ''
            echo ""
            echo "obsidian-publish dev shell"
            echo "--------------------------"
            echo "rust:  $(rustc --version)"
            echo "cargo: $(cargo --version)"
            echo "node:  $(node --version)"
            echo "bun:   $(bun --version)"
            echo "git:   $(git --version)"
            echo ""
            echo "run 'cargo build' inside indexer/ or webhook/"
            echo "run 'npm install' inside api/ or web/"
            echo ""
          '';
        };
      }
    );
}
