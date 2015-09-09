# dxvg
[vg](https://github.com/ekg/vg) integration on DNAnexus

Builds go into the [dxvg-integration](https://platform.dnanexus.com/projects/BgYjfJQ0QpJ5qyBvfbzXY890/data/) project. `vg` is compiled from the submodule git revision if necessary.

* `build_workflow.py --run-tests` builds a workflow to construct a graph, index it, and map some reads to it. It then executes this on chromosomes 21 and Y, and HS1011 fermikit unitigs from chromosome Y. This takes about 1 hour.
* `build_workflow.py --run-tests --whole-genome` does the same, and also schedules a whole-genome analysis (hs37d5, 1kGp3 variants, and HS1011 unitigs) upon the successful completion of the 21+Y case. The whole-genome analysis takes 1-2 days; the resulting index file, deposited in the build folder, is suitable for use in other analyses.

[Travis CI launches](https://travis-ci.org/dnanexus-rnd/dxvg) the 21+Y analysis automatically on push to this repo, and the whole-genome analysis on push to the `whole-genome-integration` branch. Due to their duration, Travis CI launches the analysis but doesn't wait to observe the results, so the "build passing" status isn't meaningful. You have to look in the dxvg-integration project to see how it went.
