// Builds assets/yumi.js: the living Yumi of the page, drawn by the same engine and renderer as
// the film (../motion/src/yumi), with Preact standing in for React. The output is a plain
// static file, committed, so the site is served as it is: nothing to install to host it.
//
//   npm install && npm run build

import { build } from "esbuild";
import { fileURLToPath } from "node:url";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));

await build({
  entryPoints: [here("./src/main.tsx")],
  outfile: here("./assets/yumi.js"),
  bundle: true,
  minify: true,
  format: "esm",
  target: "es2020",
  jsx: "automatic",
  jsxImportSource: "react",
  legalComments: "none",
  alias: {
    react: "preact/compat",
    "react-dom": "preact/compat",
    "react/jsx-runtime": "preact/jsx-runtime",
    // The renderer file also holds the film's wrapper, which reads the film's clock; the page
    // never uses it, so Remotion is replaced by two empty functions
    remotion: here("./src/remotion-vide.ts"),
  },
  nodePaths: [here("./node_modules")],
  logLevel: "info",
});
