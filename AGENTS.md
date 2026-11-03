# AGENTS.md

Single source of truth for agents working on **lock-manager**.

An event-driven lock manager for stateless ABAP web apps: it decouples lock ownership from the HTTP session.

## What this repository is

A **source** repository in the abap2UI5 ecosystem: humans and agents edit here,
and CI gates every change. It is installed with abapGit and depends on the
[abap2UI5](https://github.com/abap2UI5/abap2UI5) core at runtime.

## Layout

| Path | Contents |
| --- | --- |
| `src/` | The lock manager (`z2ui5_cl_lock_manager`), the SM12-style browser app, a sample, and the two registry tables (`z2ui5_t_05`, `z2ui5_t_06`) |
| `src/z2ui5_cl_lock_context`, `src/z2ui5_cx_lock_error` | Utility context and its exception — **vendored copies from abap-util, see below** |

The kernel `ENQUEUE_*` is bound to the calling session and dies with the HTTP
roundtrip. This addon funnels every lock request through a background user that
holds the kernel enqueue, and keeps a persistent registry of who locked what —
so a lock can outlive the request that took it.

## The utility copy principle

`z2ui5_cl_lock_context` is a **renamed copy** of `zabaputil_cl_util_context`
from the [abap-util](https://github.com/abap-util/abap-util) master catalog,
**trimmed to the members this repository uses** (the lock reads and the lock
types) plus the private helpers, types and constants those need.
`z2ui5_cx_lock_error` is `zabaputil_cx_util_error`, renamed and copied as-is.
abapGit has no dependency management, so utilities are vendored, not referenced.

1. **Nothing from the core's frozen `src/99/01`.** `z2ui5_cl_util*` and
   `z2ui5_cx_util_error` are kept in abap2UI5 for compatibility only; every
   utility call goes through `z2ui5_cl_lock_context`, every utility exception
   is `z2ui5_cx_lock_error`.
2. **New methods are added locally** to `z2ui5_cl_lock_context`; if abap-util
   already has the method, copy it from there with its private helpers.
3. **Periodic AI sync-back** merges what was added or fixed here into abap-util.
4. **Keep the copies close to the master.** `abaplint.jsonc` excludes both files
   from the style rules the master does not follow
   (`prefer_raise_exception_new`, `cyclomatic_complexity`, `catch_and_raise`);
   do not reformat them.

## Dependencies

- [abap2UI5](https://github.com/abap2UI5/abap2UI5) — the framework

There is no version pin on any of them — abaplint resolves each from its `main`
branch. That is why the check workflows also run on a weekly schedule: a rename
upstream breaks this repository silently, and with no pull request open nothing
else would notice.

## Build and verify

```sh
npm ci
npm run check
```

`npm run check` runs exactly what CI runs. See [CONTRIBUTING.md](CONTRIBUTING.md)
for what each gate proves and how the abap2UI5-linter baseline works.

## Views

Views are built with **`z2ui5_cl_ui5_view_builder`**, the core's generic builder
in `src/02`: `ele` (add a child and descend), `tag` (add a child and stay), `a`
(set an attribute on the element the chain points at), `end` (ascend),
`stringify` (render from the root).

Three rules that are easy to get wrong:

1. **`a( )` targets the last child** once a node has children, so a control's
   attributes belong immediately after the `ele( )`/`tag( )` that opened it.
2. **An ABAP boolean goes into `b =`.** Through `v =` an `abap_false` renders as
   an empty string, and UI5 reads an empty string as true.
3. **The root declares its own namespaces.** The frozen builder collected them
   and wrote the `xmlns` attributes itself; this one does not, and a prefix that
   is used but not declared makes the whole view fail to parse — a blank screen,
   not a bad layout. An aggregation tag takes the namespace of *its own control*:
   under `<form:SimpleForm>` it is `<form:content>`, never `<content>`.

The frozen `z2ui5_cl_xml_view` is gone from here and must not come back. It sits
in the core's `src/99`, outside the released API, and the view gate can read
nothing built with it.

## Conventions

- Classes are named `z2ui5_cl_lock_*`. No check enforces the prefix
  (`object_naming` only requires `^Z2UI5_C(L|X)`) - keep to it in review.
- English for code, comments, commit messages, pull requests and issues.
- All text files are LF-only (`.gitattributes`).
- The ecosystem-wide rules — workflow and npm-script naming, toolchain versions,
  which documentation files exist, commit style — live in
  [CONVENTIONS.md](https://github.com/abap2UI5/abap2UI5/blob/main/.github/shared/CONVENTIONS.md)
  and bind this repository too.

## Namespace rename

`npm run rename` (CI: `check-rename`) and the manual `build-rename` workflow
are abap2UI5's namespace rename for this addon - `.github/scripts/rename.mjs`,
the same file in every addon that has one. Every `z2ui5_` object becomes
`<name>_...`, for a customer name such as `ZMYUI5` or a registered namespace
such as `/CA2UI5/` (at most 10 characters), and so does every reference to
abap2UI5 and to the addons this one builds on: the branch `rename_<name>` runs
on an abap2UI5 renamed with the same name by its own `build-rename`. What
follows from it:

- Every object name has at most 25 characters (a transparent table
  11, an ICF node 10) - 30 minus what the longest new name adds.
- No literal names a `z2ui5_` object: the rename rewrites references, never a
  literal. Derive the name - from a typed reference, or behind the prefix of
  the class's own name.
- A change that spans several repositories: `RENAME_DEPS_FROM=<dir> npm run
  rename` takes the dependencies from the clones in `<dir>`.
