{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  folders = config.myFolders;
  folderUnits =
    mapAttrsToList (name: folder: {
      name = "create-folder-${name}";
      value = {
        description = "Ensure folder ${folder.path} exists";
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/mkdir -p ${folder.path} && ${pkgs.coreutils}/bin/chown ${folder.owner}:${folder.group} ${folder.path} && ${pkgs.coreutils}/bin/chmod ${folder.mode} ${folder.path}'";
          ExecStop = "${pkgs.bash}/bin/bash -c '[ ! -d ${folder.path} ] || ( [ \"$(ls -A ${folder.path})\" ] && echo \"Not deleting non-empty folder: ${folder.path}\" || rm -r ${folder.path})'";
        };
      };
    })
    folders;
in {
  options.myFolders = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        path = mkOption {type = types.str;};
        owner = mkOption {type = types.str;};
        group = mkOption {type = types.str;};
        mode = mkOption {type = types.str;};
      };
    });
    default = {};
    description = "Folders to create at runtime.";
  };

  config.systemd.services = listToAttrs folderUnits;
}
