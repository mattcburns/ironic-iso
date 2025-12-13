ironic-root-password
====================

This element sets the root password for the Ironic Python Agent ISO image.

The root password is hardcoded to "ironic" to facilitate testing and development.

Environment Variables
---------------------

- **IRONIC_ROOT_PASSWORD**

  - Required: No
  - Default: "ironic"
  - Description: The root password to set for the image. Defaults to "ironic".

Security Warning
----------------

This element is intended for development and testing environments only.
Setting a hardcoded password in production images is a security risk.
