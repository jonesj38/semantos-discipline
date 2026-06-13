---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/main.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.067878+00:00
---

# apps/loom-svelte/src/main.ts

```ts
import { mount } from "svelte";
import App from "./App.svelte";
import "./app.css";

const target = document.getElementById("app");
if (!target) throw new Error("#app element not found");

const app = mount(App, { target });

export default app;

```
