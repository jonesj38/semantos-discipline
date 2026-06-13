---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/linux/runner/main.cc
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.736966+00:00
---

# archive/apps-navigation_app/linux/runner/main.cc

```cc
#include "my_application.h"

int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}

```
