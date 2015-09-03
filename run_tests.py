#!/usr/bin/env python
from __future__ import print_function
import dxpy
import argparse
import sys
import os
import subprocess

def main():
    argparser = argparse.ArgumentParser(description="Initialize a git repository for DNAnexus workflow development & continuous integration.")
    argparser.add_argument("--project", help="DNAnexus project ID", required=True)
    argparser.add_argument("--workflow", help="Workflow ID (must reside in the project)", required=True)
    argparser.add_argument("--folder", help="Folder in which to place outputs (default: test/ subfolder of workflow's folder)")
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

    test_analysis = run_test_analysis(project, args.folder, workflow, find_test_data)
    print("test analysis: " + test_analysis.get_id())

    if args.no_wait != True:
        # wait for analysis to finish while working around Travis 10m console inactivity timeout
        noise = subprocess.Popen(["/bin/bash", "-c", "while true; do sleep 60; date; done"])
        try:
            test_analysis.wait_on_done()
            print("Success")
        finally:
            noise.kill()

        # TODO: schedule validator job, also wait for it

def run_test_analysis(project, folder, workflow, find_test_data):
    git_revision = workflow.describe(incl_properties=True)["properties"]["git_revision"]
    project.new_folder(folder, parents=True)

    test_stage_instance_types = {}

    test_input = {
        "construct.reference_genome": dxpy.dxlink(find_test_data("hs37d5.fa.gz").get_id()),
        "construct.reference_variants": dxpy.dxlink(find_test_data("ALL.wgs.phase3_shapeit2_mvncall_integrated_v5a.20130502.sites.vcf.gz").get_id()),
        "construct.reference_contigs": ["21", "Y"]
    }
    test_stage_instance_types["construct"] = "mem3_ssd1_x2"

    return workflow.run(test_input, project=project.get_id(), folder=folder,
                        name="dxvg test {}".format(git_revision), stage_instance_types=test_stage_instance_types)

if __name__ == '__main__':
    main()

