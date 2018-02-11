{ ipfs = { pkgs, ... }:

    let
      pin = { name, path }:
          { name = "pin-${name}";

            value = {
              path = [ pkgs.bash ];

              script = ''
                IPFS_PATH="/var/lib/ipfs/" ${pkgs.ipfs}/bin/ipfs add --quiet -w --recursive ${path}
              '';

              serviceConfig = {
                Type = "oneshot";
              };

              wantedBy = [ "multi-user.target" ];
            };
          };

      pinPrelude = { date }:
        let
          path = ./. + "/dhall/${date}.json";

          json = builtins.fromJSON (builtins.readFile path);

          src = pkgs.fetchgit { inherit (json) url rev sha256; };
        in
          pin { name = date; path = "${src}/Prelude"; };

      services = [
        (pinPrelude { date = "2016-12-03"; })
        (pinPrelude { date = "2017-05-16"; })
        (pinPrelude { date = "2017-06-17"; })
        (pinPrelude { date = "2017-08-28"; })
      ];

    in
      { networking.firewall.allowedTCPPorts = [ 22 4001 ];

        services = {
          fail2ban.enable = true;

          ipfs = {
            enable = true;

            enableGC = true;
          };
        };

        systemd.services = builtins.listToAttrs services // {
          ipfs.environment.IPFS_LOW_MEM = "1";
        };
      };

  hydra = { pkgs, ... }: {
    environment = {
      etc = {
        "hydra/dhall-haskell.json".text = builtins.readFile ./dhall-haskell.json;
        "hydra/machines".text = ''
          hydra-queue-runner@hydra x86_64-linux /etc/keys/hydra-queue-runner/hydra-queue-runner_rsa 1 1 local
        '';
      };

      systemPackages = [ pkgs.hydra ];
    };

    networking.firewall.allowedTCPPorts = [ 22 80 ];

    nix.gc.automatic = true;

    nixpkgs.overlays =
      let
        secureHydra = packagesNew: packagesOld: {
          hydra = packagesOld.hydra.overrideAttrs (oldAttributes: {
              patches = (oldAttributes.patches or []) ++ [ ./hydra.patch ];
            }
          );
        };

      in
        [ secureHydra ];

    services = {
      fail2ban.enable = true;

      hydra = {
        buildMachinesFiles = [ "/etc/hydra/machines" ];
        enable = true;

        extraConfig = ''
          <githubstatus>
            jobs = dhall-haskell:.*:*
            inputs = src
            authorization = gabriel
          </githubstatus>
        '';

        hydraURL = "https://hydra.dhall-lang.org";

        listenHost = "127.0.0.1";

        notificationSender = "noreply@dhall-lang.org";
      };

      nginx = {
        enable = true;

        recommendedProxySettings = true;

        virtualHosts."hydra.dhall-lang.org" = {
          default = true;

          listen = [ { addr = "0.0.0.0"; port = 80; } ];

          locations."/".proxyPass = "http://127.0.0.1:3000";
        };
      };
    };

    systemd.services.generate-hydra-queue-runner-key-pair = {
      script =
        let
          keyDirectory = "/etc/keys/hydra-queue-runner";

          user = "hydra-queue-runner";

          group = "hydra";

          privateKey = "${keyDirectory}/${user}_rsa";

          publicKey = "${privateKey}.pub";

          authorizedKeysDirectory = "/etc/ssh/authorized_keys.d";

          authorizedKeysFile = "${authorizedKeysDirectory}/${user}";
        in
          ''
            if ! [ -e ${privateKey} ] || ! [ -e ${publicKey} ]; then
              mkdir -p ${keyDirectory}

              ${pkgs.openssh}/bin/ssh-keygen -t rsa -N "" -f ${privateKey} -C "${user}@hydra" >/dev/null

              chown -R ${user}:${group} ${keyDirectory}
            fi

            if ! [ -e ${authorizedKeysFile} ]; then
              mkdir -p "${authorizedKeysDirectory}"

              cp ${publicKey} ${authorizedKeysFile}
            fi
          '';

      serviceConfig.Type = "oneshot";

      wantedBy = [ "multi-user.target" ];
    };
  };
}
