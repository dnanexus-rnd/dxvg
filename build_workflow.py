#!/usr/bin/env python
from __future__ import print_function
import dxpy
import argparse
import sys
import os
import subprocess
import json
import time

here = os.path.dirname(sys.argv[0])
git_revision = subprocess.check_output(["git", "describe", "--always", "--dirty", "--tags"]).strip()

def main():
    argparser = argparse.ArgumentParser(description="Build dxvg workflow on DNAnexus.")
    argparser.add_argument("--project", help="DNAnexus project ID", default="project-BgYjfJQ0QpJ5qyBvfbzXY890")
    argparser.add_argument("--folder", help="Folder within project (default: timestamp/git-based)", default=None)
    argparser.add_argument("--vg-exe", help="ID of vg executable built by vg_exe_builder (default: build a new one)")
    argparser.add_argument("--run-tests", help="Execute run_tests.py on the new workflow", action='store_true')
    argparser.add_argument("--run-tests-no-wait", help="Execute run_tests.py --no-wait", action='store_true')
    args = argparser.parse_args()

    if args.folder is None:
        args.folder = time.strftime("/builds/%Y-%m-%d/%H%M%S-") + git_revision

    project = dxpy.DXProject(args.project)
    applets_folder = args.folder + "/applets"
    print("project: {} ({})".format(project.name, args.project))
    print("folder: {}".format(args.folder))

    vg_exe = get_vg_exe(project, applets_folder, args.vg_exe)

    build_applets(project, applets_folder, vg_exe)

    def find_applet(applet_name):
        return dxpy.find_one_data_object(classname='applet', name=applet_name,
                                         project=project.get_id(), folder=applets_folder,
                                         zero_ok=False, more_ok=False, return_handler=True)
    def find_asset(asset_name,classname="file"):
        return dxpy.find_one_data_object(classname=classname, name=asset_name,
                                         project=project.get_id(), folder="/assets",
                                         zero_ok=False, more_ok=False, return_handler=True)
    wf = build_workflow(project, args.folder, find_applet, find_asset)

    print("workflow: {} ({})".format(wf.name, wf.get_id()))

    if args.run_tests_no_wait is True or args.run_tests is True:
        cmd = "python {} --project {} --workflow {}".format(os.path.join(here, "run_tests.py"),
                                                            project.get_id(), wf.get_id())
        if args.run_tests_no_wait is True:
            cmd = cmd + " --no-wait"
        print(cmd)
        sys.exit(os.system(cmd))

def get_vg_exe(project, applets_folder, existing_dxid=None):
    if existing_dxid is not None:
        return dxpy.DXFile(existing_dxid)
    # TODO: build a new exe
    return dxpy.DXFile("file-BgXZB8006k64v3YBf18bQF4z")

def build_applets(project, applets_folder, vg_exe):
    here_applets = os.path.join(here, "applets")
    applet_dirs = [os.path.join(here_applets,dir) for dir in os.listdir(here_applets)]
    applet_dirs = [dir for dir in applet_dirs if os.path.isdir(dir)]

    project.new_folder(applets_folder, parents=True)
    for applet_dir in applet_dirs:
        if os.path.isfile(os.path.join(applet_dir, "dxapp.json.template")):
            sed_cmd = "sed s/VG_EXE_DXID/{}/g {} > {}"
            sed_cmd = sed_cmd.format(vg_exe.get_id(),
                                     os.path.join(applet_dir, "dxapp.json.template"),
                                     os.path.join(applet_dir, "dxapp.json"))
            print(sed_cmd)
            subprocess.check_call(sed_cmd, shell=True)
        build_cmd = ["dx","build","--destination",project.get_id()+":"+applets_folder+"/",applet_dir]
        print(" ".join(build_cmd))
        applet_dxid = json.loads(subprocess.check_output(build_cmd))["id"]
        applet = dxpy.DXApplet(applet_dxid, project=project.get_id())
        applet.set_properties({"git_revision": git_revision})

def build_workflow(project, folder, find_applet, find_asset):
    wf = dxpy.new_dxworkflow(title="dxvg",
                             name="dxvg",
                             description="dxvg",
                             project=project.get_id(),
                             folder=folder,
                             properties={"git_revision": git_revision})

    construct_applet = find_applet("vg_construct")

    construct_input = {
    }
    construct_stage_id = wf.add_stage(construct_applet, stage_input=construct_input, name="construct")
    hide_stage_input(wf, construct_stage_id, "vg_exe")

    #hello_world2_input = {
    #    "infile": dxpy.dxlink({"stage": hello_world1_stage_id, "outputField": "outfile"})
    #}
    #hello_world2_stage_id = wf.add_stage(hello_world_applet, stage_input=hello_world2_input, name="hello-world2")

    return wf

def hide_stage_input(workflow, stage_id, input_name):
    # FIXME: this does not work
    # https://wiki.dnanexus.com/API-Specification-v1.0.0/Workflows-and-Analyses#API-method:-/workflow-xxxx/update
    # http://autodoc.dnanexus.com/bindings/python/current/_modules/dxpy/bindings/dxworkflow.html#DXWorkflow.update_stage
    inputSpecMods = {"stages": {stage_id: {"inputSpecMods": {input_name: {"hidden": True}}}}}
    workflow.update_stage(stage_id, inputSpecMods=inputSpecMods)

if __name__ == '__main__':
    main()

