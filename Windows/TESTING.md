# Plaza for Windows 0.4.4 — UNTESTED testing preview

This is an early Windows x64 preview for friends to test. It has not completed
hands-on Windows testing or been certified to match Mac Plaza 0.23.0. Expect bugs.
The installer is unsigned. This prerelease does not replace the Mac download. Its signed preview update feed
is separate from Mac and future Windows stable updates.

Requirements: Windows 10/11 on an Intel or AMD 64-bit PC. Windows ARM64 is not
supported by this preview. The installer includes the Swift runtime and integrated
Discord dependency; testers do not need developer tools.

Use the Setup .exe for a normal per-user installation, or extract the portable ZIP
and open Plaza.exe. Checksums and corresponding source are included beside the
app downloads. Nintendo recordings and console resource packs are excluded;
generated ambience and the fallback Mii renderer work without them. You can import
your existing Mac .plazapack unchanged in System Settings → Mii Appearance.
Alternate Miiverse music is imported separately under Music & Sound. Saved Miis
transfer separately through Mii Maker or Import Plaza.

If you used an older Windows preview, export your plaza before testing this one.
Start by checking Mii creation/editing, imports, private posts/drawings, settings,
Miiverse resize/reopen, music, and the accessible List view. Then test Discord and
shared Miiverse with your friends: both platforms use the same existing service
and community. Choose Friends Only for test posts unless you intend them to be
Public. Private posts stay on the current computer.

Test notifications, visibility of each other's primary Miis, replies/likes,
wallpaper/tray, multiple monitors, sleep/resume and birthday effects. Please report
what you did, what you expected, and the Windows version. Settings → System &
Recovery can export a scrubbed diagnostic ZIP for you to review before sharing.
Do not include passwords, Discord tokens or private conversations in a report.

Known validation limits: automated cross-language/backend and Mac-hosted UI tests
passed before this release; Windows build/package checks run in GitHub Actions.
That build result does not establish hands-on Windows compatibility or complete
feature/behavior parity. Source and build/run notes are on the windows branch.

Updates: Setup installations check the signed Windows preview feed after startup
and periodically. System Settings → System Update shows availability and verified
download/install controls. Automatic download/installation is opt-in. A ready
update installs on the next launch, or through Restart and Install. Portable ZIP
users download the new version manually. Source pushes run tests; delivery
requires an explicit Windows release tag and local signed-feed publication.
See RELEASE-PROCESS.md for that final signing and Sites publishing step.
