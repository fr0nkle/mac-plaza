# Mii Plaza Windows port — local development

This branch provides an **untested Windows preview** and starts parity with **Mac Plaza 0.23.0** using the existing local
Windows 0.4 foundation. It remains unfinished and has not completed hands-on Windows validation. See
[testing notes](TESTING.md). Historical Windows downloads were retired in the Mac repository;
do not treat their release notes or prior CI claims as current proof.

The Electron UI uses the same Swift PlazaCore crowd, Mii codec, portable models,
FFL resources and artwork as Mac. Both clients use the same Discord identities
and authenticated Plaza `/v1` service. Public, Friends Only and Private posts
retain their audiences; older Windows shared posts and drafts remain friends-only
when upgraded. No separate Windows community is introduced.

The local implementation includes the current four-page Miiverse UI, ranked
communities, primary birthday controls and annual overlay, alternate theme import,
independent resizable Miiverse, Mii library/profile flows, portable shared/private
journals, accessible app/friend/journal list, notification routing, and source-derived crowd/post/game-history logic.
Compatibility and desktop fixtures run on macOS; Windows native compilation,
OS integration and authorized real two-device validation remain pending.

- [Feature inventory, architecture and staged checklist](PORT-PLAN.md)
- [Build, isolated run and test instructions](BUILDING.md)
- Task workspace `HANDOFF.md` records the local branch, evidence and blockers.

User-imported console resources and recordings are optional and excluded from
Git. Existing Mac recordings can be staged locally for matching music/effects;
this private dependency staging is not a distribution approval. No soundtrack download is required for the fallback renderer.
Original code is MIT; the combined FFL renderer includes AGPL-3.0-only components.
Preserve notices and corresponding source; see [LICENSING.md](../LICENSING.md).
Discord, Swift and Electron dependencies retain their separate notices.
