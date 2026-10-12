{
  yggdrasil-ng,
  fetchFromGitHub,
  rustPlatform,
}:
yggdrasil-ng.overrideAttrs (
  final: old: {
    version = "0.3.1";
    src = fetchFromGitHub {
      owner = "Revertron";
      repo = "Yggdrasil-ng";
      tag = "v0.3.1";
      hash = "sha256-sbohqm2TXFnh03JVCzgy53lsTs1Pg/Elov3qr4mMmAI=";
    };
    cargoHash = "sha256-QdvbVSTGhV+9PF6txwiMCTNx8U20X/Fj9U1YYBvIcX8=";
    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit (final) src;
      name = "yggdrasil-ng-${final.version}-vendor";
      hash = final.cargoHash;
    };
    patches = (old.patches or [ ]) ++ [
      # Upstream PRs #28 and #39, pending inclusion in a release.
      ./patches/sigterm.patch
      ./patches/multiple-links.patch
      # Keep the shared handshake budget, without capping established peers.
      ./patches/handshake-only-limit.patch
    ];
    meta = old.meta // {
      mainProgram = "yggdrasil";
    };
  }
)
