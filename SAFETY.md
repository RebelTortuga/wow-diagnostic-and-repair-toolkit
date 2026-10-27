# Privacy & Software Safety

Last updated: October 27, 2026

## Scope and requirements

This repository supplies Windows diagnostic, backup, or repair scripts. Review the requirements and action descriptions in README.md, RUN-README.md, and OPTIONS-README.md before use.

This guidance is not a certification or guarantee of safety. Website hosting and embedded-service disclosures are on the [website privacy page](https://rebeltortuga.github.io/privacy-software-safety.html); they do not describe this project's software behavior.

## Downloads and verification

Use [this repository’s releases](https://github.com/RebelTortuga/wow-diagnostic-and-repair-toolkit/releases) and source code. Other copies may be outdated or modified. Consult the release notes for your version. When published checksums are available, compare them before use; a matching checksum identifies the expected file but does not establish that it is harmless. Do not assume releases are signed or independently audited.

## Permissions and consequential actions

Start with read-only diagnostics where available. Some repair actions change or delete files, reset preferences, close applications, or require elevated permissions. Review confirmations and choose only the action needed. Do not grant administrator access unless the selected operation requires it.

## Backups and recovery

Back up important data before repairs. A toolkit backup covers only its selected and documented files/settings; it is not a full computer backup. Check the backup contents, exclusions, destination, completion result, and restoration instructions. An older backup can overwrite newer data. Deleting this toolkit does not undo repairs or restore removed files.

## Data handling

Consult the source and project documentation for file access, network activity, and stored data. Backups and diagnostic reports may contain usernames, paths, settings, browser data, or saved account information. Keep them private and review any report before sharing. Do not submit passwords, tokens, private backups, or complete browser profiles in public issues.

## Removal

Close the toolkit and any separate action windows, preserve wanted backups/reports, then remove only the toolkit folder you extracted. Application settings changed by repair actions, backups, logs, or other files outside that folder may remain. Follow the version's documented paths and recovery instructions; do not delete unfamiliar folders.

If the documentation does not explain a relevant storage path or removal step, ask in Issues without sharing sensitive files.

## Security warnings and reporting

Keep security software current. If a file produces an unexpected warning, pause. Record the filename, version, source URL, exact detection, and security-product version. Do not assume every detection is a false positive, and do not disable protection merely to run a tool.

Report ordinary bugs through [Issues](https://github.com/RebelTortuga/wow-diagnostic-and-repair-toolkit/issues). Follow [SECURITY.md](SECURITY.md) for sensitive vulnerabilities.

## License and third-party terms

Read [LICENSE](LICENSE) and relevant upstream terms. Optional donations do not alter those terms. Compatibility and results vary by system.

