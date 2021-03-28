{ config, lib, pkgs, inputs, username, ... }:
# TODO: Highlight the region last command operated on
with lib;
let
  hm = config.home-manager.users.${username};
  cfg = config.rde.emacs;

  ### Types
  # Source: https://gitlab.com/rycee/nur-expressions/-/blob/master/hm-modules/emacs-init.nix#L9
  packageFunctionType = mkOptionType {
    name = "packageFunction";
    description =
      "Function returning list of packages, like epkgs: [ epkgs.org ]";
    check = isFunction;
    merge = mergeOneOption;
  };

  varType = types.submodule ({ name, config, ... }: {
    options = {
      value = mkOption {
        type = types.either types.str (types.either types.int types.bool);
      };
      docstring = mkOption {
        type = types.str;
        default = "";
      };
    };
  });

  emacsConfigType = types.submodule ({ name, config, ... }: {
    options = {
      enable = mkEnableOption "Enable emacs.configs.${name}.";
      vars = mkOption {
        type = types.attrsOf varType;
        description = "Variable declaration for emacs.configs.${name}.";
      };
      emacsPackages = mkOption {
        type =
          # types.either
          # ((types.listOf types.str) // { description = "List of packages."; })
          packageFunctionType;
        default = epkgs: [ ];
        description = ''
          Emacs package list for this config.
        '';
        example = "epkgs: [ epkgs.org ]";
      };
      systemPackages = mkOption {
        type = types.listOf types.package;
        description = "System dependencies for ${name}.";
        default = [ ];
      };
      config = mkOption {
        type = types.lines;
        description = ''
          Use-package configuration for ${name}.
        '';
      };
    };
    config = mkIf config.enable {
      vars = {
        "rde/config-${name}-enabled".value = true;
        # TODO: add enabled configs variable
      };
    };
  });

  ### Auxiliary functions
  mkROFileOption = path:
    (mkOption {
      type = types.path;
      description = "Files autogenerated by rde";
      default = path;
      readOnly = true;
    });


  varSetToConfig = v:
    let
      dispatcher = {
        bool = v: if v then "t" else "nil";
        string = v: ''"${v}"'';
      };
      valueToStr = v:
        ((attrByPath [ (builtins.typeOf v) ] toString dispatcher) v);
      ifDocString = v:
        if (stringLength v.docstring > 0) then " \"${v.docstring}\"" else "";
      tmp = mapAttrsToList (name: value: ''
        (defvar ${name} ${valueToStr value.value}${ifDocString value})
      '') v;
    in concatStrings tmp;

  configSetToConfig = v:
    let
      tmp = mapAttrsToList (name: value: ''
        ;;; configs.${name}
        ${value.config}
      '') v;
    in concatStrings tmp;

  enableConfigs = configList:
    foldl (res: name: res // { "${name}".enable = true; }) { } configList;

  emacsConfigs = filterAttrs (n: v: v.enable) cfg.configs;
  systemPackageList = concatLists
    (mapAttrsToList (key: value: value.systemPackages) emacsConfigs);

  emacs-pkg = (pkgs.unstable.emacs.override {
    withXwidgets = true;
  }).overrideAttrs (oa: { name = "rde-${oa.pname}-${oa.version}"; });
  emacs-pkgs = (pkgs.unstable.emacsPackagesFor emacs-pkg);
  emacs-with-pkgs = emacs-pkgs.emacsWithPackages;

  #emacsPackage = pkgs.unstable.emacsGit;
  emacsPackage = (emacs-with-pkgs (epkgs:
    let
      build-emacs-package = pname: text:
        (epkgs.trivialBuild {
          pname = pname;
          version = "1.0";
          src = pkgs.writeText "${pname}.el" text;
          packageRequires = [ epkgs.use-package ];
          preferLocalBuild = true;
          allowSubstitutes = false;
        });

      concatVarSets = configs:
        let
          tmp = mapAttrsToList (key: value:
            ''
              ;;; Variables by configs.${key}
            '' + (varSetToConfig value.vars)) configs;
        in concatStrings tmp;
      rde-variables-text = (varSetToConfig cfg.vars)
        + (concatVarSets emacsConfigs) + ''

          (provide 'rde-variables)
        '';
      rde-variables-package =
        build-emacs-package "rde-variables" rde-variables-text;

      rde-configs-text = (readFile ./use-package-init.el)
        + configSetToConfig emacsConfigs + "(provide 'rde-configs)";
      rde-configs-package = build-emacs-package "rde-configs" rde-configs-text;

      packageList = concatLists
        (mapAttrsToList (key: value: (value.emacsPackages epkgs)) emacsConfigs);

    in with epkgs;
    packageList ++ [
      rde-variables-package
      rde-configs-package
      restart-emacs
    ]));

  socketName = "main";
  socketPath = "%t/emacs/${socketName}";
  clientCmd = "${emacsPackage}/bin/emacsclient --socket-name=${socketName}";
  emacsClientScriptName = "ec";
  emacsClientPackage = pkgs.writeScriptBin emacsClientScriptName ''
    #!${pkgs.runtimeShell}
    if [ -z "$1" ]; then
      exec ${clientCmd} --alternate-editor ${emacsPackage}/bin/emacs --create-frame
    else
      exec ${clientCmd} --alternate-editor ${emacsPackage}/bin/emacs "$@"
    fi
  '';
  emacsClientDesktopItem = pkgs.makeDesktopItem rec {
    name = "emacsclient";
    desktopName = "Emacs Client";
    genericName = "Text Editor";
    comment = "Edit text";
    mimeType =
      "text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;";
    exec = "${emacsClientScriptName} %F";
    icon = "emacs";
    type = "Application";
    terminal = "false";
    categories = "Utility;TextEditor;";
    extraEntries = ''
      StartupWMClass=Emacs
    '';
  };
in {

  imports = [ ./configs ];
  options = {
    rde.emacs = {
      enable = mkEnableOption "Enable rde emacs";
      dirs = {
        config = mkOption {
          type = types.path;
          description =
            "Directory, where emacs configuration files will be placed.";
          default = "${hm.xdg.configHome}/emacs";
        };
        data = mkOption {
          type = types.path;
          description =
            "Directory, where emacs configuration files will be placed.";
          default = "${hm.xdg.dataHome}/emacs";
        };
      };
      files = {
        init = mkROFileOption "${cfg.dirs.config}/init.el";
        early-init = mkROFileOption "${cfg.dirs.config}/early-init.el";
        custom = mkOption {
          type = types.path;
          description = "Path to custom.el.";
          default = "${cfg.dirs.data}/custom.el";
        };
      };

      configs = mkOption {
        type = types.attrsOf emacsConfigType;
        description = "Configurations for various packages or package sets";
      };

      vars = mkOption {
        type = types.attrsOf varType;
        description = "Every config adds variable declaration(s) here.";
      };

      font = mkOption {
        type = types.str;
        default = config.rde.font;
      };

      fontSize = mkOption {
        type = types.int;
        default = config.rde.fontSize;
      };

      emacsPackageList = mkOption {
        type = types.attrsOf types.package;
        default = emacs-pkgs;
      };
      # package = mkOption {
      #   type = types.package;
      #   default = emacs-with-pkgs;
      # };

      preset.tropin.enable = mkEnableOption "Enable tropin's configuration.";
      preset.tropin.configList = mkOption {
        type = types.listOf types.str;
        readOnly = true;
        default = [
          "rde-core"
          "rde-defaults"
          "faces"
          "ligatures"
          "icomplete"
          "ibuffer"
          "org-roam"
          "rg"
          "dired"
          "keycast"
          "monocle"
          "mode-line"
          "eshell"
          "org"
          "company"
          "modus-themes"
          "nix"
          "magit"
          "olivetti"
          # "project"
          "elpher"
          "geiser"
          "guix"
          "smartparens"
        ];
      };
    };
  };

  config = mkIf config.rde.emacs.enable {
    rde.emacs.vars = {
      "rde/username" = {
        value = username;
        docstring = "System username provided by rde.";
      };
      "rde/data-dir" = { value = cfg.dirs.data; };
      "rde/config-dir" = { value = cfg.dirs.config; };
      "rde/rde-dir" = { value = config.rde.rdeDir; };
      "rde/custom-file" = {
        value = cfg.files.custom;
        docstring = "Path to custom.el.";
      };
      "rde/font-family".value = cfg.font;
      "rde/font-size".value = cfg.fontSize;
    };

    rde.emacs.configs = mkIf cfg.preset.tropin.enable
      (enableConfigs cfg.preset.tropin.configList);

    home-manager.users."${username}" = {
      home.activation = {
        enusreEmacsDataDir =
          #inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ]
          ''
            $DRY_RUN_CMD mkdir $VERBOSE_ARG -p ${cfg.dirs.data}
          '';
      };
      home.file."${cfg.files.init}".text = ''
        (require 'rde-variables)
        (require 'rde-configs)
        (provide 'init)
      '';
      home.file."${cfg.files.early-init}".source = ./early-init.el;

      home.packages = with pkgs;

        systemPackageList ++ [
          emacs-all-the-icons-fonts
          emacsPackage
          emacsClientPackage
          # emacsClientDesktopItem
        ];

      systemd.user.services.emacs = {
        Unit = {
          Description = "Emacs: the extensible, self-documenting text editor";
          Documentation =
            "info:emacs man:emacs(1) https://gnu.org/software/emacs/";

          # Avoid killing the Emacs session, which may be full of
          # unsaved buffers.
          X-RestartIfChanged = false;
        };

        Service = {
          # We wrap ExecStart in a login shell so Emacs starts with the user's
          # environment, most importantly $PATH and $NIX_PROFILES. It may be
          # worth investigating a more targeted approach for user services to
          # import the user environment.
          ExecStart = ''
            ${pkgs.runtimeShell} -l -c "${emacsPackage}/bin/emacs --fg-daemon=${socketName}"'';
          # We use '(kill-emacs 0)' to avoid exiting with a failure code, which
          # would restart the service immediately.
          ExecStop = "${clientCmd} --eval '(kill-emacs 0)'";
          Restart = "on-failure";
        };
      };

      # systemd.user.sockets.emacs = {
      #   Unit = {
      #     Description = "Emacs: the extensible, self-documenting text editor";
      #     Documentation =
      #       "info:emacs man:emacs(1) https://gnu.org/software/emacs/";
      #     PartOf = "emacs.service";
      #   };

      #   Socket = {
      #     ListenStream = socketPath;
      #     # FileDescriptorName = "server";
      #     # SocketMode = "0600";
      #     # DirectoryMode = "0700";
      #   };

      #   Install = { WantedBy = [ "sockets.target" ]; };
      # };
    };
  };
}
