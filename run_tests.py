#!/usr/bin/env python
from __future__ import print_function
import dxpy
import argparse
import sys
import os
import subprocess
import time

def main():
    argparser = argparse.ArgumentParser(description="Initialize a git repository for DNAnexus workflow development & continuous integration.")
    argparser.add_argument("--project", help="DNAnexus project ID", required=True)
    argparser.add_argument("--workflow", help="Workflow ID (must reside in the project)", required=True)
    argparser.add_argument("--folder", help="Folder in which to place outputs (default: test/ subfolder of workflow's folder)")
    argparser.add_argument("--whole-genome", help="Schedule whole-genome index build on completion of all tests", action="store_true")
    argparser.add_argument("--no-wait", help="Exit immediately after launching tests", action="store_true", default=False)
    args = argparser.parse_args()

    project = dxpy.DXProject(args.project)
    workflow = dxpy.DXWorkflow(project=project.get_id(), dxid=args.workflow)

    if args.folder is None:
        args.folder = os.path.join(workflow.describe()["folder"], "test")

    print("test folder: " + args.folder)

    def find_test_data(name, classname="file"):
        return dxpy.find_one_data_object(classname=classname, name=name,
                                         project=project.get_id(), folder="/test-data",
                                         zero_ok=False, more_ok=False, return_handler=True)

    test_analyses = run_test_analyses(project, args.folder, workflow, find_test_data)
    print("test analyses: " + ", ".join([a.get_id() for a in test_analyses]))

    if args.whole_genome is True:
        wg_analysis = run_wg_build(project, args.folder, workflow, find_test_data,
                                   [analysis_last_job_id(a) for a in test_analyses])
        print("scheduled whole-genome " + wg_analysis.get_id())

    if args.no_wait != True:
        print("awaiting completion...")
        # wait for analysis to finish while working around Travis 10m console inactivity timeout
        noise = subprocess.Popen(["/bin/bash", "-c", "while true; do sleep 60; date; done"])
        try:
            for test_analysis in test_analyses:
                test_analysis.wait_on_done()
            print("Success!")
        finally:
            noise.kill()

        # TODO: validate the test analysis results in some way

def run_test_analyses(project, folder, workflow, find_test_data):
    # test cases: one or more named input hashes to run the workflow with
    test_inputs = {
        "21+Y": {
            "construct.reference_genome": dxpy.dxlink(find_test_data("hs37d5.fa.gz").get_id()),
            "construct.reference_variants": dxpy.dxlink(find_test_data("ALL.wgs.phase3_shapeit2_mvncall_integrated_v5a.20130502.sites.vcf.gz").get_id()),
            "construct.reference_contigs": ["21", "Y", "MT", "GL000207.1", "NC_007605", "hs37d5"],
            "map.reads": dxpy.dxlink(find_test_data("HS1011_unitigs_Y.fastq.gz").get_id())
        }
    }

    # The tests might only need smaller instance types than the applet
    # defaults (reduces cost of running tests).
    stage_instance_types = {
        "construct": "mem3_ssd1_x8",
        "index": "mem3_ssd1_x8",
        "index_ref": "mem3_ssd1_x8",
        "map": "mem3_ssd1_x8"
    }

    git_revision = workflow.describe(incl_properties=True)["properties"]["git_revision"]
    analyses = []
    for test_name, test_input in test_inputs.iteritems():
        test_folder = os.path.join(folder, test_name)
        project.new_folder(test_folder, parents=True)
        analyses.append(workflow.run(test_input, project=project.get_id(), folder=test_folder,
                                     stage_instance_types=stage_instance_types,
                                     delay_workspace_destruction=True,
                                     name="dxvg {} {}".format(test_name, git_revision)))
    return analyses

def run_wg_build(project, folder, workflow, find_test_data, depends_on):
    wg_input = {
        "construct.reference_genome": dxpy.dxlink(find_test_data("hs37d5.fa.gz").get_id()),
        "construct.reference_variants": dxpy.dxlink(find_test_data("ALL.wgs.phase3_shapeit2_mvncall_integrated_v5a.20130502.sites.vcf.gz").get_id()),
        "map.reads": dxpy.dxlink(find_test_data("HS1011.mag.gz").get_id())
    }

    git_revision = workflow.describe(incl_properties=True)["properties"]["git_revision"]
    test_folder = os.path.join(folder, "whole-genome")
    project.new_folder(test_folder, parents=True)
    return workflow.run(wg_input, project=project.get_id(), folder=test_folder,
                        depends_on=depends_on, priority="normal",
                        name="dxvg whole-genome {}".format(git_revision))

def analysis_last_job_id(analysis):
    # working around PTFM-16418
    time.sleep(10)
    stages = analysis.describe()["stages"]
    if len(stages) == 0:
        return None
    return str(stages[len(stages)-1]["execution"]["id"])

if __name__ == '__main__':
    main()

