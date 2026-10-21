## Node (npm, pnpm, yarn)
Only applies when the variant includes the node toolchain (`DEVCONTAINER_TOOLCHAINS` contains `node`).

- **Node version:** fnm switches to the version of the nearest `.nvmrc` / `.node-version` when you
  `cd` into a directory; elsewhere the default (latest LTS) is used. A version pinned in a new
  version file: run `fnm install` in that directory.
- **Package managers:** npm comes with Node. pnpm and yarn come via corepack, at the version in
  `package.json`'s `packageManager`; don't install them with `npm -g`.
- **node_modules** of every package directory is a separate volume, not part of the workspace
  files. In a package directory created after the container was built, `node_modules` is a plain
  directory in the workspace until the user rebuilds the container. Tell the user when you add
  a package directory.
- A project `.npmrc` appears empty (masked like other secret files). Don't put registry tokens in
  files; ask the user.
