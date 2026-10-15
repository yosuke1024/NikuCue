#!/usr/bin/env python3
"""Generates MotionLab/MotionLab.xcodeproj (Xcode 16+ format, file-system-synchronized folder).

The evaluation app has one target, `MotionLab`, linking two Swift packages:
  - CatBehavior (local, ../CatBehavior): the behaviour / locomotion / navigation engine;
  - spine-runtimes (remote, pinned to one revision): product SpineiOS, the official spine-ios runtime.
Files under MotionLab/MotionLab/ (sources and the git-ignored SpineSamples/ resources) need no project edit.

    python3 -I tools/generate_motionlab_project.py      # from Experiments/CharacterMotionPoC
Standard library only. Verified by `xcodebuild` in .github/workflows/character-motion-poc.yml.
"""
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJ = ROOT / "MotionLab" / "MotionLab.xcodeproj"

APP = "MotionLab"
BUNDLE_ID = "placeholder.nikucue.motionlab"      # evaluation app: never signed for distribution
SPINE_URL = "https://github.com/EsotericSoftware/spine-runtimes"
SPINE_REVISION = "b7beb2ccbbce667a12c02f44d070644f59b04968"   # tag spine-ts-4.3.13 (2026-07-24), see README
DEPLOYMENT_TARGET = "17.0"

ID = {k: f"5A1E0C{n:018X}" for n, k in enumerate([
    "project", "mainGroup", "productsGroup", "appSync", "appProduct", "appTarget", "appSources", "appFrameworks",
    "appResources", "projectConfigList", "projectDebug", "projectRelease", "appConfigList", "appDebug", "appRelease",
    "localPackage", "remotePackage", "catProduct", "spineProduct", "catBuildFile", "spineBuildFile",
], start=1)}

PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "SDKROOT": "iphoneos",
    "SWIFT_STRICT_CONCURRENCY": "targeted",
}
PROJECT_DEBUG = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
})
PROJECT_RELEASE = dict(PROJECT_COMMON, **{
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})
APP_SETTINGS = {
    "CODE_SIGN_STYLE": "Automatic",
    "COMPRESS_PNG_FILES": "NO",          # the Spine atlas is premultiplied-alpha; keep its PNG bytes as exported
    "STRIP_PNG_TEXT": "NO",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": '""',
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": '"Motion Lab"',
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
    "MARKETING_VERSION": "0.1",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
    "SUPPORTS_MACCATALYST": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}


def settings(d: dict) -> str:
    return "\n".join(f"\t\t\t\t{k} = {v};" for k, v in sorted(d.items()))


def config(ident: str, name: str, d: dict) -> str:
    return (f"\t\t{ident} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(d)}\n"
            f"\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")


def config_list(ident: str, comment: str, debug: str, release: str) -> str:
    return (f"\t\t{ident} /* Build configuration list for {comment} */ = {{\n\t\t\tisa = XCConfigurationList;\n"
            f"\t\t\tbuildConfigurations = (\n\t\t\t\t{debug} /* Debug */,\n\t\t\t\t{release} /* Release */,\n\t\t\t);\n"
            f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")


def pbxproj() -> str:
    I = ID
    return f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I['catBuildFile']} /* CatBehavior in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['catProduct']} /* CatBehavior */; }};
		{I['spineBuildFile']} /* SpineiOS in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['spineProduct']} /* SpineiOS */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{I['appProduct']} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I['appSync']} /* {APP} */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = {APP};
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{I['appFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['catBuildFile']} /* CatBehavior in Frameworks */,
				{I['spineBuildFile']} /* SpineiOS in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{I['appSync']} /* {APP} */,
				{I['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['appProduct']} /* {APP}.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['appTarget']} /* {APP} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['appConfigList']} /* Build configuration list for PBXNativeTarget "{APP}" */;
			buildPhases = (
				{I['appSources']} /* Sources */,
				{I['appFrameworks']} /* Frameworks */,
				{I['appResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['appSync']} /* {APP} */,
			);
			name = {APP};
			packageProductDependencies = (
				{I['catProduct']} /* CatBehavior */,
				{I['spineProduct']} /* SpineiOS */,
			);
			productName = {APP};
			productReference = {I['appProduct']} /* {APP}.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{I['appTarget']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {I['projectConfigList']} /* Build configuration list for PBXProject "{APP}" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {I['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{I['localPackage']} /* XCLocalSwiftPackageReference "../CatBehavior" */,
				{I['remotePackage']} /* XCRemoteSwiftPackageReference "spine-runtimes" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['appTarget']} /* {APP} */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{I['appResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I['appSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{config(I['projectDebug'], 'Debug', PROJECT_DEBUG)}{config(I['projectRelease'], 'Release', PROJECT_RELEASE)}{config(I['appDebug'], 'Debug', APP_SETTINGS)}{config(I['appRelease'], 'Release', APP_SETTINGS)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{config_list(I['projectConfigList'], f'PBXProject "{APP}"', I['projectDebug'], I['projectRelease'])}{config_list(I['appConfigList'], f'PBXNativeTarget "{APP}"', I['appDebug'], I['appRelease'])}/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{I['localPackage']} /* XCLocalSwiftPackageReference "../CatBehavior" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = ../CatBehavior;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCRemoteSwiftPackageReference section */
		{I['remotePackage']} /* XCRemoteSwiftPackageReference "spine-runtimes" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "{SPINE_URL}";
			requirement = {{
				kind = revision;
				revision = {SPINE_REVISION};
			}};
		}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{I['catProduct']} /* CatBehavior */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = CatBehavior;
		}};
		{I['spineProduct']} /* SpineiOS */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['remotePackage']} /* XCRemoteSwiftPackageReference "spine-runtimes" */;
			productName = SpineiOS;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""


def scheme() -> str:
    ref = (f'BuildableIdentifier = "primary"\n               BlueprintIdentifier = "{ID["appTarget"]}"\n'
           f'               BuildableName = "{APP}.app"\n               BlueprintName = "{APP}"\n'
           f'               ReferencedContainer = "container:{APP}.xcodeproj"')
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               {ref}>
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "NO">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            {ref.replace(chr(10) + '               ', chr(10) + '            ')}>
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            {ref.replace(chr(10) + '               ', chr(10) + '            ')}>
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main() -> None:
    (PROJ / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
    (PROJ / "project.pbxproj").write_text(pbxproj())
    (PROJ / "xcshareddata" / "xcschemes" / f"{APP}.xcscheme").write_text(scheme())
    (PROJ / "project.xcworkspace").mkdir(exist_ok=True)
    (PROJ / "project.xcworkspace" / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n'
        '   </FileRef>\n</Workspace>\n')
    validate((PROJ / "project.pbxproj").read_text())
    print(f"wrote {PROJ.relative_to(ROOT)} ({len(ID)} objects, references checked)")


def validate(text: str) -> None:
    """Parses the file with the repository's pbxproj parser and checks referential integrity (not a substitute for
    opening it in Xcode; CI does that)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("validate_pbxproj", ROOT.parents[1] / "tools/xcodeproj/validate_pbxproj.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # the repository parser treats "//" as a comment start, so mask URL schemes before parsing
    root = module.Parser(text.replace("://", ":__")).parse()
    objects = root["objects"]
    ids = set(objects)
    assert ids == set(ID.values()), f"object ids differ: {sorted(ids ^ set(ID.values()))}"
    import re
    id_re = re.compile(r"^[0-9A-F]{24}$")

    def walk(v):
        if isinstance(v, dict):
            for x in v.values():
                walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)
        elif isinstance(v, str) and id_re.match(v):
            assert v in ids, f"dangling id {v}"

    walk(objects)
    project = objects[root["rootObject"]]
    assert project["isa"] == "PBXProject"
    for ref in project["packageReferences"]:
        pkg = objects[ref]
        if pkg["isa"] == "XCLocalSwiftPackageReference":
            assert (PROJ.parent / pkg["relativePath"] / "Package.swift").is_file(), pkg["relativePath"]
    for t in project["targets"]:
        for g in objects[t]["fileSystemSynchronizedGroups"]:
            assert (PROJ.parent / objects[g]["path"]).is_dir(), objects[g]["path"]


if __name__ == "__main__":
    main()
