# Utility module for bento deployment
{ config, pkgs, ... }:

{
  # Enable bento service for deployment
  services.bento = {
    enable = true;
  };
}
