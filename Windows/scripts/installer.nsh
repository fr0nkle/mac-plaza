!macro customInstall
  FileOpen $0 "$INSTDIR\resources\plaza-installed" w
  FileWrite $0 "NSIS per-user installation"
  FileClose $0
!macroend
