{
  /*
  Those fixes are required to have adb access when I connect over ssh without graphical session running.
  In this case default udev rules are not working, so I need my own.
  */
  users.users.ilma4.extraGroups = ["adbusers"];
  users.groups.adbusers = {};

  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ENV{ID_DEBUG_APPLIANCE}=="android", MODE="0660", GROUP="adbusers"
  '';
}
