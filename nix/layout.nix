{ config, lib, pkgs, ... }:

{
  console.useXkbConfig = true;
  services.xserver = {
    layout = "us";
    xkbVariant = "qwerty,";
    xkbOptions =
      "ctrl:nocaps, grp:win_space_toggle, grp:rctrl_switch";
  };
}
