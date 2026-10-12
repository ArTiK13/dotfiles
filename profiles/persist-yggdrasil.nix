{
  config,
  secrets,
  ...
}:
{
  age.secrets.yggdrasil-ng-keys = {
    file = "${secrets}/yggdrasil/${config.networking.hostName}-ng.age";
  };
  services.yggdrasil-ng.privateKeyFile = config.age.secrets.yggdrasil-ng-keys.path;
}
