# Mii Plaza Windows port — local development

This branch starts parity with **Mac Plaza 0.23.0** using the existing local
Windows 0.4 foundation. It is unfinished and has not been released or certified
on Windows. Historical Windows downloads were retired in the Mac repository;
do not treat their release notes or prior CI claims as current proof.

The Electron UI uses the same Swift PlazaCore crowd, Mii codec, portable models,
FFL resources and artwork as Mac. Both clients use the same Discord identities
and authenticated Plaza `/v1` service. Public, Friends Only and Private posts
retain their audiences; older Windows shared posts and drafts remain friends-only
when upgraded. No separate Windows community is introduced.

The first slice adds explicit audiences, a legacy migration, shared HTTP transport
and contract tests, latest published primary-Mii identity matching, and an
independent resizable Miiverse window. The main plaza continues behind it.
Birthday effects, the current Mac Miiverse navigation/theme controls, and remaining
visual and OS parity are tracked in the checklist.

- [Feature inventory, architecture and staged checklist](PORT-PLAN.md)
- [Build, isolated run and test instructions](BUILDING.md)
- Task workspace `HANDOFF.md` records the local branch, evidence and blockers.

User-imported console resources and recordings are optional and excluded from
source/builds. No soundtrack download is required for the fallback renderer.
Original code is MIT; the combined FFL renderer includes AGPL-3.0-only components.
Preserve notices and corresponding source; see [LICENSING.md](../LICENSING.md).
Discord, Swift and Electron dependencies retain their separate notices.
