{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.yggdrasil-ng;
  format = pkgs.formats.toml { };
  configFile = format.generate "yggdrasil-ng.toml" cfg.settings;
  control = pkgs.writeShellApplication {
    name = "yggdrasilctl";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      args=()
      legacy_json=false
      for arg in "$@"; do
        case "$arg" in
          -json) legacy_json=true ;;
          *) args+=("$arg") ;;
        esac
      done
      if "$legacy_json"; then
        ${cfg.package}/bin/yggdrasil -e ${escapeShellArg cfg.settings.admin_listen} -j "''${args[@]}" | jq -e '.response'
        exit
      fi
      exec ${cfg.package}/bin/yggdrasil -e ${escapeShellArg cfg.settings.admin_listen} "''${args[@]}"
    '';
  };
in
{
  options.services.yggdrasil-ng = {
    enable = mkEnableOption "Yggdrasil NG mesh networking";
    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../packages/yggdrasil-ng { };
      defaultText = literalExpression "pkgs.callPackage ../packages/yggdrasil-ng { }";
      description = "Yggdrasil NG package, including the local compatibility patches.";
    };
    settings = mkOption {
      type = format.type;
      default = { };
      description = "Public TOML configuration. Private keys are loaded separately.";
    };
    privateKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing the 128-character Ed25519 keypair hex string.";
    };
  };

  config = mkIf cfg.enable {
    services.yggdrasil-ng.settings.admin_listen = mkDefault "tcp://127.0.0.1:9001";
    assertions = [
      {
        assertion = config.networking.enableIPv6;
        message = "Yggdrasil NG requires IPv6.";
      }
      {
        assertion = !config.services.yggdrasil.enable;
        message = "Enable only one Yggdrasil implementation.";
      }
      {
        assertion = !(cfg.settings ? private_key);
        message = "Use services.yggdrasil-ng.privateKeyFile; private keys must not enter the Nix store.";
      }
    ];

    users.users.yggdrasil = {
      isSystemUser = true;
      group = "yggdrasil";
      uid = 862;
    };
    users.groups.yggdrasil.gid = 862;
    boot.kernelModules = [ "tun" ];

    systemd.services.yggdrasil-ng = {
      description = "Yggdrasil NG mesh network";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      script = ''
        ${optionalString (cfg.privateKeyFile != null) ''
          key=$(cat "$CREDENTIALS_DIRECTORY/private-key")
          if [[ ! "$key" =~ ^[[:xdigit:]]{128}$ ]]; then
            echo "Invalid Yggdrasil NG private key format" >&2
            exit 1
          fi
          export YGGDRASIL_PRIVATE_KEY="$key"
          unset key
        ''}
        exec ${cfg.package}/bin/yggdrasil --config ${configFile}
      '';
      serviceConfig = {
        Type = "notify";
        User = "yggdrasil";
        Group = "yggdrasil";
        LoadCredential = optional (cfg.privateKeyFile != null) "private-key:${cfg.privateKeyFile}";
        Restart = "always";
        RestartSec = "5s";
        TimeoutStopSec = "30s";
        RuntimeDirectory = "yggdrasil-ng";
        StateDirectory = "yggdrasil-ng";
        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
        ];
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
        ];
        NoNewPrivileges = true;
        MemoryDenyWriteExecute = true;
        MemoryMax = "1G";
        LimitNOFILE = 65536;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged @keyring"
        ];
      };
    };

    environment.systemPackages = [
      cfg.package
      control
    ];
  };
}
