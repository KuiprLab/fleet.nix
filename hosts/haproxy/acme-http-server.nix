{
  config,
  pkgs,
  ...
}:

{
  # Create a simple service to serve ACME challenges
  systemd.services.acme-http-server = {
    description = "HTTP server for ACME challenges";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${pkgs.python3}/bin/python3 -m http.server 54321 \
          --directory /var/lib/acme/acme-challenge \
          --bind 127.0.0.1
      '';
      User = "acme";
      Group = "haproxy";
      Restart = "always";
      RestartSec = "5";
    };
  };
}
