# RDP-LICENSING-NOTE.md

## What this DevBox does

- Built-in Windows Server Remote Desktop, network access restriction comes from
  the tailnet Grant, one administrative/debugging interactive session.
- NLA stays enabled (`UserAuthentication = 2`).
- `runneradmin` is set a password from the `devbox` Environment secret.

## What this DevBox does NOT do

- NO Remote Desktop Session Host is installed anywhere, ever. The scripts fail
  loudly when an RDS role is detected on the image.
- NO connection broker. NO licensing role. NO multi-user app session.
- NO bypass of RDS licensing. Changing interpretation to allow "cheap RDS on a
  single server" is not a DevBox feature.

## The honest license boundary

Microsoft documentation: Windows Server supports two concurrent remote-desktop
connections without RDS CALs for *administrative purposes*. General user and
application sessions are a different licensing model and NOT what this repo does
(without buying them or changing the deployment). Before commercial or multi-user
use, re-read the current Microsoft licensing guidance - pricing and wording change
over the years and this document does not update itself.
