#!/usr/bin/env python3
"""Regenerate the native Xcode project. Sources use synchronized groups (Xcode 16+)."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def ref(name):
    return uid(name)
objects = {}
def obj(name, body):
    objects[ref(name)] = body

def config(name, settings):
    contents = "\n".join(f"\t\t\t\t{k} = {v};" for k,v in settings.items())
    obj(name, f"isa = XCBuildConfiguration; buildSettings = {{\n{contents}\n\t\t\t}}; name = {name.rsplit('-', 1)[-1]};")
def configlist(name, prefix):
    obj(name, f"isa = XCConfigurationList; buildConfigurations = ({ref(prefix+'-Debug')}, {ref(prefix+'-Release')}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

obj('main-group', f'''isa = PBXGroup; children = ({ref('sources')}, {ref('resources-group')}, {ref('products')}); sourceTree = "<group>";''')
obj('sources', 'isa = PBXFileSystemSynchronizedRootGroup; path = Sources/XinLi; sourceTree = "<group>";')
obj('resources-group', f'''isa = PBXGroup; name = Resources; children = ({ref('info')}, {ref('entitlements')}, {ref('icon')}, {ref('calendar-resources')}, {ref('holidays')}, {ref('project-license')}); sourceTree = "<group>";''')
obj('products', f'isa = PBXGroup; name = Products; children = ({ref("app-product")}); sourceTree = "<group>";')
obj('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = "心历.app"; sourceTree = BUILT_PRODUCTS_DIR;')
for name,path,typ in [('info','Resources/Info.plist','text.plist.xml'),('entitlements','Resources/ChronoCal.entitlements','text.plist.entitlements'),('icon','Resources/ChronoCalIcon.icns','image.icns'),('calendar-resources','Resources/Calendar','folder'),('holidays','../docs/data/holidays.json','text.json'),('project-license','../LICENSE','text')]:
    obj(name,f'isa = PBXFileReference; lastKnownFileType = {typ}; path = "{path}"; sourceTree = "<group>";')
for name in ['icon','calendar-resources','holidays','project-license']:
    obj(name+'-build', f'isa = PBXBuildFile; fileRef = {ref(name)};')
obj('app-lunar', f'isa = XCSwiftPackageProductDependency; package = {ref("local-package")}; productName = LunarCore;')
obj('app-lunar-build', f'isa = PBXBuildFile; productRef = {ref("app-lunar")};')
obj('app-sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('app-frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({ref("app-lunar-build")}); runOnlyForDeploymentPostprocessing = 0;')
obj('app-resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ref("icon-build")}, {ref("calendar-resources-build")}, {ref("project-license-build")}); runOnlyForDeploymentPostprocessing = 0;')
obj('app-holiday-copy', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = "calendar-data"; dstSubfolderSpec = 7; files = ({ref("holidays-build")}); name = "Copy official holiday data"; runOnlyForDeploymentPostprocessing = 0;')
obj('local-package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
obj('app-target', f'''isa = PBXNativeTarget; buildConfigurationList = {ref('app-configs')}; buildPhases = ({ref('app-sources')}, {ref('app-frameworks')}, {ref('app-resources')}, {ref('app-holiday-copy')}); buildRules = (); dependencies = (); fileSystemSynchronizedGroups = ({ref('sources')}); name = XinLi; packageProductDependencies = ({ref('app-lunar')}); productName = "心历"; productReference = {ref('app-product')}; productType = "com.apple.product-type.application";''')
obj('project', f'''isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{ {ref('app-target')} = {{CreatedOnToolsVersion = 26.1; }}; }}; }}; buildConfigurationList = {ref('project-configs')}; compatibilityVersion = "Xcode 16.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN, en, Base); mainGroup = {ref('main-group')}; minimizedProjectReferenceProxies = 1; packageReferences = ({ref('local-package')}); preferredProjectObjectVersion = 77; productRefGroup = {ref('products')}; projectDirPath = ""; projectRoot = ""; targets = ({ref('app-target')});''')
common = {'CLANG_ENABLE_MODULES':'YES','MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx','SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','ENABLE_USER_SCRIPT_SANDBOXING':'YES','CODE_SIGN_IDENTITY':'"-"','CODE_SIGN_STYLE':'Manual','DEVELOPMENT_TEAM':'""'}
for mode in ['Debug','Release']:
    project = dict(common)
    project.update({'ONLY_ACTIVE_ARCH':'YES' if mode == 'Debug' else 'NO','SWIFT_OPTIMIZATION_LEVEL':'"-Onone"' if mode == 'Debug' else '"-O"','DEBUG_INFORMATION_FORMAT':'dwarf' if mode == 'Debug' else '"dwarf-with-dsym"','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'"DEBUG $(inherited)"' if mode == 'Debug' else '"$(inherited)"'})
    config('project-'+mode,project)
    config('app-'+mode, {'PRODUCT_NAME':'"心历"','PRODUCT_MODULE_NAME':'XinLi','EXECUTABLE_NAME':'XinLi','PRODUCT_BUNDLE_IDENTIFIER':'com.zfdang.WanNianLiSwift','INFOPLIST_FILE':'Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CODE_SIGN_ENTITLEMENTS':'Resources/ChronoCal.entitlements','ENABLE_APP_SANDBOX':'YES','ENABLE_HARDENED_RUNTIME':'YES','LD_RUNPATH_SEARCH_PATHS':'"$(inherited) @executable_path/../Frameworks"','COMBINE_HIDPI_IMAGES':'YES'})
for kind in ['project','app']:
    configlist(kind+'-configs',kind)
projectdir = ROOT/'XinLi.xcodeproj'
projectdir.mkdir(exist_ok=True)
text = '// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 77;\n objects = {\n'
text += '\n'.join(f'\t{key} = {{ {value} }};' for key,value in objects.items())
text += f'\n }};\n rootObject = {ref("project")};\n}}\n'
(projectdir/'project.pbxproj').write_text(text)
schemedir=projectdir/'xcshareddata/xcschemes'
schemedir.mkdir(parents=True, exist_ok=True)
def buildref(name,product,blueprint=None):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(name)}" BuildableName="{product}" BlueprintName="{blueprint or product.split(".")[0]}" ReferencedContainer="container:XinLi.xcodeproj"/>'
appref=buildref('app-target','心历.app','XinLi')
(schemedir/'XinLi.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(projectdir)
