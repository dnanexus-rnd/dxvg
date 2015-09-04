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
    argparser.add_argument("--whole-genome", help="Add --whole-genome to run_tests command if any", action='store_true')
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
        if args.whole_genome is True:
            cmd = cmd + " --whole-genome"
        print(cmd)
        sys.exit(os.system(cmd))

def get_vg_exe(project, applets_folder, existing_dxid=None):
    if existing_dxid is not None:
        return dxpy.DXFile(existing_dxid)
    
    # determine desired git revision of vg
    vg_git_revision = subprocess.check_output(["git", "describe", "--long", "--always", "--tags"],
                                              cwd=os.path.join(here,"vg")).strip()
    # is the exe available already?
    existing = dxpy.find_data_objects(classname="file", typename="vg_exe",
                                      project=project.get_id(), folder="/vg-exe",
                                      properties={"git_revision": vg_git_revision},
                                      return_handler=True)
    existing = list(existing)
    if len(existing) > 0:
        if len(existing) > 1:
            print("Warning: found multiple vg executables with git_revision={}, picking one".format(vg_git_revision))
        existing = existing[0]
        print("Using vg executable {} ({})".format(vg_git_revision,existing.get_id()))
        return existing
    
    # no - build one for this git revision
    project.new_folder("/vg-exe", parents=True)
    print("Building new vg executable for {}".format(vg_git_revision))
    build_cmd = ["dx","build","-f","--destination",project.get_id()+":/vg-exe/",os.path.join(here,"vg_exe_builder")]
    print(" ".join(build_cmd))
    build_applet = dxpy.DXApplet(json.loads(subprocess.check_output(build_cmd))["id"])
    build_job = build_applet.run({"git_commit": vg_git_revision},
                                 project=project.get_id(), folder="/vg-exe",
                                 name="vg_exe_builder " + vg_git_revision)
    print("Launched {} to build vg executable, waiting...".format(build_job.get_id()))
    noise = subprocess.Popen(["/bin/bash", "-c", "while true; do sleep 60; date; done"])
    try:
        build_job.wait_on_done()
    finally:
        noise.kill()
    vg_exe = dxpy.DXFile(build_job.describe()["output"]["vg_exe"])
    print("Using vg executable {} ({})".format(vg_git_revision,vg_exe.get_id()))
    return vg_exe

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
    def build(incl_map):
        nm = "vg_construct_index_map" if incl_map else "vg_construct_index"
        wf = dxpy.new_dxworkflow(title=nm,
                                 name=nm,
                                 description=nm,
                                 project=project.get_id(),
                                 folder=folder,
                                 properties={"git_revision": git_revision})

        construct_applet = find_applet("vg_construct")
        construct_input = {
        }
        construct_stage_id = wf.add_stage(construct_applet, stage_input=construct_input, name="construct")
        hide_stage_input(wf, construct_stage_id, "vg_exe")

        index_input = {
            "vg_tar": dxpy.dxlink({"stage": construct_stage_id, "outputField": "vg_tar"})
        }
        index_stage_id = wf.add_stage(find_applet("vg_index"), stage_input=index_input, name="index")
        hide_stage_input(wf, index_stage_id, "vg_exe")

        if incl_map:
            map_input = {
                "vg_indexed_tar": dxpy.dxlink({"stage": index_stage_id, "outputField": "vg_indexed_tar"})
            }
            map_stage_id = wf.add_stage(find_applet("vg_map"), stage_input=map_input, name="map")
            hide_stage_input(wf, map_stage_id, "vg_exe")

        return wf

    build(False)
    return build(True)

def hide_stage_input(workflow, stage_id, input_name):
    workflow.update(stages={stage_id: {"inputSpecMods": {input_name: {"hidden": True}}}})

if __name__ == '__main__':
    main()

