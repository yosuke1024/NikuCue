#!/usr/bin/env python3
"""Generates NikuCue.xcodeproj (Xcode 16+ format with file-system-synchronized groups).

Why generated: this repository was authored on Linux without Xcode. The project file uses
synchronized root groups, so adding Swift files under NikuCue/ or NikuCueTests/ needs no
project edit. Re-run after changing targets or build settings:

    python3 tools/xcodeproj/generate_pbxproj.py

Verify on macOS with: xcodebuild -list -project NikuCue.xcodeproj
Standard library only.
"""
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJ = ROOT / "NikuCue.xcodeproj"

# Stable 24-hex identifiers (Xcode only requires uniqueness within the file).
ID = {
    "project": "4E1C0E0000000000000000A1",
    "mainGroup": "4E1C0E0000000000000000A2",
    "productsGroup": "4E1C0E0000000000000000A3",
    "packagesGroup": "4E1C0E0000000000000000A4",
    "appSync": "4E1C0E0000000000000000B1",
    "testsSync": "4E1C0E0000000000000000B2",
    "appProduct": "4E1C0E0000000000000000C1",
    "testsProduct": "4E1C0E0000000000000000C2",
    "packageFileRef": "4E1C0E0000000000000000C3",
    "appTarget": "4E1C0E0000000000000000D1",
    "testsTarget": "4E1C0E0000000000000000D2",
    "appSources": "4E1C0E0000000000000000E1",
    "appFrameworks": "4E1C0E0000000000000000E2",
    "appResources": "4E1C0E0000000000000000E3",
    "appScript": "4E1C0E0000000000000000E4",
    "testsSources": "4E1C0E0000000000000000E5",
    "testsFrameworks": "4E1C0E0000000000000000E6",
    "testsResources": "4E1C0E0000000000000000E7",
    "projectConfigList": "4E1C0E0000000000000000F1",
    "projectDebug": "4E1C0E0000000000000000F2",
    "projectRelease": "4E1C0E0000000000000000F3",
    "appConfigList": "4E1C0E0000000000000000F4",
    "appDebug": "4E1C0E0000000000000000F5",
    "appRelease": "4E1C0E0000000000000000F6",
    "testsConfigList": "4E1C0E0000000000000000F7",
    "testsDebug": "4E1C0E0000000000000000F8",
    "testsRelease": "4E1C0E0000000000000000F9",
    "containerProxy": "4E1C0E0000000000000001A1",
    "targetDependency": "4E1C0E0000000000000001A2",
    "localPackage": "4E1C0E0000000000000001B1",
    "packageProduct": "4E1C0E0000000000000001B2",
    "packageBuildFile": "4E1C0E0000000000000001B3",
}

APP_NAME = "NikuCue"
TESTS_NAME = "NikuCueTests"
BUNDLE_ID = "placeholder.nikucue.app"          # R05: owner replaces; Release build fails while "placeholder" remains
TESTS_BUNDLE_ID = "placeholder.nikucue.tests"
DEPLOYMENT_TARGET = "17.0"
MARKETING_VERSION = "0.1.0"
SWIFT_VERSION = "5.0"   # Swift 5 language mode on a Swift 6 compiler (docs/IMPLEMENTATION_LOG.md, decision D-P00-3)

PROJECT_DEBUG = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_TESTABILITY": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "MTL_FAST_MATH": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    "SWIFT_STRICT_CONCURRENCY": "targeted",
}
PROJECT_RELEASE = dict(PROJECT_DEBUG)
for k in ("DEBUG_INFORMATION_FORMAT", "ENABLE_TESTABILITY", "GCC_DYNAMIC_NO_PIC", "GCC_OPTIMIZATION_LEVEL",
          "GCC_PREPROCESSOR_DEFINITIONS", "MTL_ENABLE_DEBUG_INFO", "ONLY_ACTIVE_ARCH", "SWIFT_ACTIVE_COMPILATION_CONDITIONS",
          "SWIFT_OPTIMIZATION_LEVEL"):
    PROJECT_RELEASE.pop(k)
PROJECT_RELEASE.update({
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})

APP_SETTINGS = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": '""',
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": APP_NAME,
    "INFOPLIST_KEY_LSApplicationCategoryType": '"public.app-category.lifestyle"',
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": SWIFT_VERSION,
    "TARGETED_DEVICE_FAMILY": "1",
}

TESTS_SETTINGS = {
    "BUNDLE_LOADER": '"$(TEST_HOST)"',
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": '""',
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": TESTS_BUNDLE_ID,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
    "SUPPORTS_MACCATALYST": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": SWIFT_VERSION,
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_HOST": f'"$(BUILT_PRODUCTS_DIR)/{APP_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP_NAME}"',
}


def settings_block(d: dict, indent: str = "\t\t\t\t") -> str:
    return "\n".join(f"{indent}{k} = {v};" for k, v in sorted(d.items()))


def build_config(ident: str, name: str, settings: dict) -> str:
    return (
        f"\t\t{ident} /* {name} */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n{settings_block(settings)}\n\t\t\t}};\n"
        f"\t\t\tname = {name};\n"
        f"\t\t}};\n"
    )


def config_list(ident: str, comment: str, debug: str, release: str) -> str:
    return (
        f"\t\t{ident} /* Build configuration list for {comment} */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{debug} /* Debug */,\n"
        f"\t\t\t\t{release} /* Release */,\n"
        f"\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};\n"
    )


def generate() -> str:
    I = ID
    script = '"\\"${SRCROOT}/scripts/check_release_config.sh\\"\\n"'
    return f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I['packageBuildFile']} /* NikuCueDomain in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['packageProduct']} /* NikuCueDomain */; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{I['containerProxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['appTarget']};
			remoteInfo = {APP_NAME};
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		{I['appProduct']} /* {APP_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['testsProduct']} /* {TESTS_NAME}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TESTS_NAME}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['packageFileRef']} /* NikuCueDomain */ = {{isa = PBXFileReference; lastKnownFileType = wrapper; name = NikuCueDomain; path = Packages/NikuCueDomain; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I['appSync']} /* {APP_NAME} */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = {APP_NAME};
			sourceTree = "<group>";
		}};
		{I['testsSync']} /* {TESTS_NAME} */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = {TESTS_NAME};
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{I['appFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['packageBuildFile']} /* NikuCueDomain in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['testsFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{I['appSync']} /* {APP_NAME} */,
				{I['testsSync']} /* {TESTS_NAME} */,
				{I['packagesGroup']} /* Packages */,
				{I['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['packagesGroup']} /* Packages */ = {{
			isa = PBXGroup;
			children = (
				{I['packageFileRef']} /* NikuCueDomain */,
			);
			name = Packages;
			sourceTree = "<group>";
		}};
		{I['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['appProduct']} /* {APP_NAME}.app */,
				{I['testsProduct']} /* {TESTS_NAME}.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['appTarget']} /* {APP_NAME} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['appConfigList']} /* Build configuration list for PBXNativeTarget "{APP_NAME}" */;
			buildPhases = (
				{I['appSources']} /* Sources */,
				{I['appFrameworks']} /* Frameworks */,
				{I['appResources']} /* Resources */,
				{I['appScript']} /* Check release configuration */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['appSync']} /* {APP_NAME} */,
			);
			name = {APP_NAME};
			packageProductDependencies = (
				{I['packageProduct']} /* NikuCueDomain */,
			);
			productName = {APP_NAME};
			productReference = {I['appProduct']} /* {APP_NAME}.app */;
			productType = "com.apple.product-type.application";
		}};
		{I['testsTarget']} /* {TESTS_NAME} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['testsConfigList']} /* Build configuration list for PBXNativeTarget "{TESTS_NAME}" */;
			buildPhases = (
				{I['testsSources']} /* Sources */,
				{I['testsFrameworks']} /* Frameworks */,
				{I['testsResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{I['targetDependency']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['testsSync']} /* {TESTS_NAME} */,
			);
			name = {TESTS_NAME};
			packageProductDependencies = (
			);
			productName = {TESTS_NAME};
			productReference = {I['testsProduct']} /* {TESTS_NAME}.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
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
					{I['testsTarget']} = {{
						CreatedOnToolsVersion = 16.0;
						TestTargetID = {I['appTarget']};
					}};
				}};
			}};
			buildConfigurationList = {I['projectConfigList']} /* Build configuration list for PBXProject "{APP_NAME}" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {I['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{I['localPackage']} /* XCLocalSwiftPackageReference "Packages/NikuCueDomain" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['appTarget']} /* {APP_NAME} */,
				{I['testsTarget']} /* {TESTS_NAME} */,
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
		{I['testsResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXShellScriptBuildPhase section */
		{I['appScript']} /* Check release configuration */ = {{
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
				"$(SRCROOT)/NikuCue/App/AppConfiguration.swift",
			);
			name = "Check release configuration";
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = {script};
		}};
/* End PBXShellScriptBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I['appSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['testsSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{I['targetDependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['appTarget']} /* {APP_NAME} */;
			targetProxy = {I['containerProxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{build_config(I['projectDebug'], 'Debug', PROJECT_DEBUG)}{build_config(I['projectRelease'], 'Release', PROJECT_RELEASE)}{build_config(I['appDebug'], 'Debug', APP_SETTINGS)}{build_config(I['appRelease'], 'Release', APP_SETTINGS)}{build_config(I['testsDebug'], 'Debug', TESTS_SETTINGS)}{build_config(I['testsRelease'], 'Release', TESTS_SETTINGS)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{config_list(I['projectConfigList'], f'PBXProject "{APP_NAME}"', I['projectDebug'], I['projectRelease'])}{config_list(I['appConfigList'], f'PBXNativeTarget "{APP_NAME}"', I['appDebug'], I['appRelease'])}{config_list(I['testsConfigList'], f'PBXNativeTarget "{TESTS_NAME}"', I['testsDebug'], I['testsRelease'])}/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{I['localPackage']} /* XCLocalSwiftPackageReference "Packages/NikuCueDomain" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/NikuCueDomain;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{I['packageProduct']} /* NikuCueDomain */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = NikuCueDomain;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""


SCHEME = f"""<?xml version="1.0" encoding="UTF-8"?>
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
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ID['appTarget']}"
               BuildableName = "{APP_NAME}.app"
               BlueprintName = "{APP_NAME}"
               ReferencedContainer = "container:{APP_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ID['testsTarget']}"
               BuildableName = "{TESTS_NAME}.xctest"
               BlueprintName = "{TESTS_NAME}"
               ReferencedContainer = "container:{APP_NAME}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ID['appTarget']}"
            BuildableName = "{APP_NAME}.app"
            BlueprintName = "{APP_NAME}"
            ReferencedContainer = "container:{APP_NAME}.xcodeproj">
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
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ID['appTarget']}"
            BuildableName = "{APP_NAME}.app"
            BlueprintName = "{APP_NAME}"
            ReferencedContainer = "container:{APP_NAME}.xcodeproj">
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

WORKSPACE = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""


def main() -> None:
    (PROJ / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
    (PROJ / "project.xcworkspace").mkdir(parents=True, exist_ok=True)
    (PROJ / "project.pbxproj").write_text(generate(), encoding="utf-8")
    (PROJ / "xcshareddata" / "xcschemes" / f"{APP_NAME}.xcscheme").write_text(SCHEME, encoding="utf-8")
    (PROJ / "project.xcworkspace" / "contents.xcworkspacedata").write_text(WORKSPACE, encoding="utf-8")
    print("wrote", PROJ.relative_to(ROOT))


if __name__ == "__main__":
    main()
