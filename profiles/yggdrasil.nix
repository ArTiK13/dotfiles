{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.self.nixosModules.modules.yggdrasil-ng ];

  # Yggdrasil's 0200::/7 subnet must never be proxied — traffic to mesh
  # peers is overlay-internal and sending it through mihomo would either
  # fail or add pointless latency.
  networking.tproxy.extraBypassCIDRs.ipv6 = [ "0200::/7" ];

  # Yggdrasil peers on arbitrary ports (including 80/443) must bypass tproxy.
  # Pin yggdrasil to a static UID so `meta skuid` works reliably in nftables
  # (DynamicUser UIDs aren't resolvable at rule-load time and cgroup matching
  # is chicken-and-egg at boot). The skip fires in the output chain before
  # the mark-set step.
  networking.tproxy.defaults.skipUsers = [ "yggdrasil" ];

  services.yggdrasil-ng = {
    enable = true;
    settings = {
      listen = [
        "tls://[::]:8362"
        "tcp://[::]:8363"
        "quic://[::]:8364"
      ];
      peers = lib.mkIf (config.networking.hostName != "whale") [
        "quic://ygg-msk-1.averyan.ru:8364"
        "tls://ygg-msk-1.averyan.ru:8362"
      ];
      if_name = "ygg0";
      if_mtu = 65535;
      admin_listen = "tcp://127.0.0.1:9001";
      max_inbound_links_per_peer = 0;
      multicast_interfaces = [
        {
          port = 9217;
        }
      ];
      node_info = {
        name = "${config.networking.hostName}.averyanalex";
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    8362
    8363
    8364
    9217
  ];
  networking.firewall.allowedUDPPorts = [
    8364
    9001 # Multicast discovery uses UDP 9001; the admin API is loopback TCP.
  ];
}
