{
  config,
  lib,
  ...
}: {
  options = {
    i4.tpm2.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };
  config = lib.mkIf config.i4.tpm2.enable {
    security.tpm2.enable = true;
    security.tpm2.pkcs11.enable = true; # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
    security.tpm2.tctiEnvironment.enable = true; # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables
    users.users.ilma4.extraGroups = ["tss"]; # tss group has access to TPM devices
  };
}
