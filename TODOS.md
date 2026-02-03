# Improve secret management

1. Write a script to call sops with sudo and passing the env var SOPS_AGE_KEY_FILE

2. Write a script which generates a new private key and prints the old and new public keys to stdout
Note, that old private key must be backed up (i.e. rename keys.txt to keys.txt.old)

3. Write a script which takes remote host as argument. It connects to it using ssh and executes script 2.

4. Write a script which updates the .sops.yaml file. It takes the old public key and new public key as arguments and replaces the old public key with the new one.

5. Write a script which rotates the keys in all secrets

6. Write a script which takes remote host as argument and executes scripts 3, 4 and 5

Names of all those scripts should start with `i4-sops-`

Keep in mind `modules/sops.nix`
