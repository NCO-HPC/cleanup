#!/usr/bin/env python3
# This script prints a list of packages under the package root (as provided as
# an argument) that are older than the oldest version of that package in use in
# ecFlow, based on '_ver' variables. It also prints warnings for packages not
# corresponding with any ecFlow '_ver' variables.

import collections, glob, os, re, sys
from distutils.version import LooseVersion
import ecflow

envir = os.getenv("envir")
assert envir in ["prod","para","test"], f"ERROR: $envir ({envir}) is not defined to an acceptable value. Quitting..."

HOMEcleanup = os.getenv("HOMEcleanup")
assert HOMEcleanup, "$HOMEcleanup not defined! Quitting..."
package_whitelist_file = f"{HOMEcleanup}/parm/package_whitelist_file"
package_whitelist = collections.defaultdict(list)
if os.path.exists(package_whitelist_file):
  for line in open(package_whitelist_file,"r").readlines():
    if re.match("^\s*#",line): continue
    parts = line.split()
    assert len(parts)==2, f"Wrong format for whitelist file {package_whitelist_file}! Quitting..."
#    package_whitelist[parts[0]] = parts[1]
    package_whitelist[parts[0]].append(parts[1])
else:
  print(f"WARNING: No package whitelist file found at path {package_whitelist_file}",file=sys.stderr)

PACKAGEROOT = sys.argv[1]
assert os.path.exists(PACKAGEROOT), f"$PACKAGEROOT {PACKAGEROOT} does not exist! Quitting..."
assert f"/{envir}/" in PACKAGEROOT, f"$PACKAGEROOT {PACKAGEROOT} does not contain $envir {envir}! Quitting..."

# Get all _ver variables from ecflow for this envir

if envir in ["prod"]: expectedecfport="31415"
elif envir in ["para","test"]: expectedecfport="14142"

ECF_PORT = os.getenv("ECF_PORT")
assert ECF_PORT == expectedecfport, f"ECF_PORT {ECF_PORT} is not consistent with this environment ({envir})! Quitting..."

ci = ecflow.Client()
ci.sync_local()
defs = ci.get_defs()
suite = defs.find_suite(envir)

ALL_VER_VARS = collections.defaultdict(set)

# WW 20220310 - exclude model_ver from transfer jobs
for node in suite.get_all_nodes():
  for variable in node.variables:
    if variable.name().endswith("_ver") and not variable.name().startswith("model"): 
      ALL_VER_VARS[variable.name()].add(variable.value())

oldpackagepaths = []
for ver_var in ALL_VER_VARS.keys():
  packagename = re.sub("_ver$","",ver_var)
  oldestecfversion = sorted([LooseVersion(vv) for vv in ALL_VER_VARS[ver_var]])[0]
  if not oldestecfversion.vstring.startswith("v"):
    print(f"WARNING: Found an ecFlow variable named '{packagename}_ver' that has invalid value '{oldestecfversion.vstring}' or not defind at suite level. Wrong value means package {packagename} will not be cleaned up!",file=sys.stderr)
    continue
  existingpackagepaths = glob.glob(f"{PACKAGEROOT}/{packagename}.*/")
  if not existingpackagepaths: print(f"WARNING: variable {ver_var} does not correspond with any existing package in {PACKAGEROOT}",file=sys.stderr)
  for path in existingpackagepaths:
    thispackageversion = re.sub(f"{PACKAGEROOT}/?{packagename}.([^/]+)/",r"\1",path)
    if not re.match("v\d+\.(\d+\.)*\d+[a-z]*",thispackageversion):
      print(f"WARNING: the package name of path {path} is incorrectly formatted, and will never be cleaned up!")
      continue
    if (str(LooseVersion(thispackageversion))<str(oldestecfversion)) and (thispackageversion not in package_whitelist[packagename]):
      oldpackagepaths += [path]

for package in os.listdir(PACKAGEROOT):
  packagename = re.split(".v[\d\.]+[a-z]?",package)[0]
  if packagename+"_ver" not in ALL_VER_VARS.keys():
    print(f"WARNING: Package {PACKAGEROOT}/{package} not found in ecFlow. Ignoring.",file=sys.stderr)

for oldpackagepath in oldpackagepaths: print(oldpackagepath)
