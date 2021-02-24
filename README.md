# XReSign

XReSign allows you to sign or resign unencrypted ipa-files with certificate for which you hold the corresponding private key. Checked for developer, ad-hoc and enterprise distribution.

## How to use

### GUI application

![Screenshot](https://github.com/xndrs/XreSign/blob/master/screenshot/screenshot.png)

### Shell command

In addition to GUI app, you can find, inside Scripts folder, xresign.sh script to run resign task from the command line.

### Usage:

```
$ ./xresign.sh -s APP_PATH -c CERT_NAME [-e ENTITLEMENTS_PATH_PATH] [-p PROV_PATH] [-b ID]

-s  path to input app to sign
-c  Common Name of signing certificate in Keychain
-e  new entitlements to use for app (Optional)
-p  path to mobile provisioning file (Optional)
-b  new bundle identifier (Optional)
-a  allow app installation on all devices (Optional)
```

## Acknowledgments

Inspired by such great tool as iReSign and other command line scripts to resign the ipa files. Unfortunately a lot of them not supported today. So this is an attempt to support resign the app bundle components both through the GUI application and through the command line script.
