{
  lib,
  pkgs,
  ...
}: let
  create_users = host: {
    users.users."${host.username}" = {
      createHome = false;
      home = "/home/chroot/" + host.username;
      isNormalUser = false;
      isSystemUser = true;
      group = "sftp_users";
      openssh.authorizedKeys.keys = [host.key];
      shell = null;
    };
  };

  users = [
    {
      username = "root";
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDJw0fcEfsKF1m12KWuO0HRwsq36XQ5PGlKQCvU/zWPw root@192.168.1.69";
    }
  ];
in {
  imports = builtins.map create_users users;

  users.groups = {sftp_users = {};};

  services.openssh.extraConfig = ''
    Match Group sftp_users
      X11Forwarding no
      AllowTcpForwarding no
      ChrootDirectory %h
      ForceCommand internal-sftp
  '';
}
