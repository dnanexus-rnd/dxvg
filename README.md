# dxvg
[vg](https://github.com/ekg/vg) integration on DNAnexus

Builds go into the [dxvg-integration](https://platform.dnanexus.com/projects/BgYjfJQ0QpJ5qyBvfbzXY890/data/) project. `vg` is compiled from the submodule git revision if necessary.

* `build_workflow.py --run-tests` builds a workflow to construct a graph, index it, and map some reads to it. It then executes this on chromosomes 21 and Y, and HS1011 fermikit unitigs from chromosome Y. This takes about 1 hour.
* `build_workflow.py --run-tests --whole-genome` does the same, and also schedules a whole-genome analysis (hs37d5, 1kGp3 variants, and HS1011 unitigs) upon the successful completion of the 21+Y case. The whole genome analysis takes 1-2 days.
