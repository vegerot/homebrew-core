class Dotnet < Formula
  desc ".NET Core"
  homepage "https://dotnet.microsoft.com/"
  url "https://github.com/dotnet/installer.git",
      tag:      "v6.0.100",
      revision: "9e8b04bbff820c93c142f99a507a46b976f5c14c"
  license "MIT"

  bottle do
    sha256 cellar: :any,                 arm64_monterey: "5da394797cc4591cab024e9e0fe2f3fba24ec4905fecd4fbddefcc0050469d70"
    sha256 cellar: :any,                 arm64_big_sur:  "ca1798917487fd700ca0058e3a311b4dee678e8207ae36505697c05f96723a57"
    sha256 cellar: :any,                 monterey:       "fde61d787ee05b2796ecf63f25d04d5a5567b9a24759ef5b17d345a7ad5bb09e"
    sha256 cellar: :any,                 big_sur:        "da8e83fc8191baeebef6875ff70894ffc7366244f373a1255968fc6b6a268e5f"
    sha256 cellar: :any,                 catalina:       "5dae07f638d20f0e53149c83dd440d67b278d2c31fd7d55e313b4105870f4ad8"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "cabfbed0228d338416f7057fd7123986b0c483ab86e8280e160ff81510eef6c1"
  end

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "python@3.10" => :build
  depends_on xcode: :build
  depends_on "icu4c"
  depends_on "openssl@1.1"

  # HACK: this should not be a test dependency but is due to a limitation with fails_with
  uses_from_macos "llvm" => [:build, :test]
  uses_from_macos "krb5"
  uses_from_macos "zlib"

  on_macos do
    # arcade fails to build with BSD `sed` due to `-i` usage in SourceBuild.props
    depends_on "gnu-sed" => :build
  end

  on_linux do
    depends_on "libunwind"
    depends_on "lttng-ust"
  end

  # Upstream only directly supports and tests llvm/clang builds.
  # GCC builds have limited support via community.
  fails_with :gcc

  # Fix build with Clang 13.
  # PR ref: https://github.com/dotnet/runtime/pull/63314
  # TODO: Remove this in future release with .NET runtime v6.0.2+
  resource "runtime-clang13-patch" do
    url "https://github.com/dotnet/runtime/commit/f86caa54678535ead8e1977da37025a96e2afe8a.patch?full_index=1"
    sha256 "bc264ce2a1f9f7f3d27db10276bb2d1b979f66da06727aaa04be15c36086a9a3"
  end

  # Fix previously-source-built bootstrap.
  # PR ref: https://github.com/dotnet/installer/pull/12642
  # TODO: Remove this in the next release
  patch do
    url "https://github.com/dotnet/installer/commit/7f02ccd30f55e7ac3436bd32af4b207869541ebf.patch?full_index=1"
    sha256 "ff51630f9bfc4bbb502f57c6b1348d2e530a006234150606f9327fedcbb6591c"
  end

  # Fix build failure on macOS due to missing ILAsm/ILDAsm
  # Fix build failure on macOS ARM due to `osx-x64` override
  patch :DATA

  def install
    if OS.linux?
      ENV.append_path "LD_LIBRARY_PATH", Formula["icu4c"].opt_lib
    else
      ENV.prepend_path "PATH", Formula["gnu-sed"].opt_libexec/"gnubin"
    end

    # TODO: Remove this in future release with .NET runtime v6.0.2+
    (buildpath/"src/SourceBuild/tarball/patches/runtime").install resource("runtime-clang13-patch")

    sourcedir = buildpath.parent/"dotnet-sources"
    system "./build.sh", "/p:ArcadeBuildTarball=true",
                         "/p:TarballDir=#{sourcedir}"
    cd sourcedir
    # Disable package validation in source-build for reliability
    # PR ref: https://github.com/dotnet/runtime/pull/60881
    # TODO: Remove this in the next release
    inreplace Dir["src/runtime.*/eng/packaging.targets"].first,
              "<EnablePackageValidation>true</EnablePackageValidation>",
              "<EnablePackageValidation>false</EnablePackageValidation>"
    # Rename patch fails on case-insensitive systems like macOS
    # TODO: Remove whenever patch is no longer used
    rm Dir["src/nuget-client.*/eng/source-build-patches/0001-Rename-NuGet.Config*.patch"].first if OS.mac?
    system "./prep.sh", "--bootstrap"
    system "./build.sh"

    libexec.mkpath
    tarball = Dir["artifacts/*/Release/dotnet-sdk-#{version}-*.tar.gz"].first
    system "tar", "-xzf", tarball, "--directory", libexec
    doc.install Dir[libexec/"*.txt"]
    (bin/"dotnet").write_env_script libexec/"dotnet", DOTNET_ROOT: libexec
  end

  def caveats
    <<~EOS
      For other software to find dotnet you may need to set:
        export DOTNET_ROOT="#{opt_libexec}"
    EOS
  end

  test do
    target_framework = "net#{version.major_minor}"
    (testpath/"test.cs").write <<~EOS
      using System;

      namespace Homebrew
      {
        public class Dotnet
        {
          public static void Main(string[] args)
          {
            var joined = String.Join(",", args);
            Console.WriteLine(joined);
          }
        }
      }
    EOS
    (testpath/"test.csproj").write <<~EOS
      <Project Sdk="Microsoft.NET.Sdk">
        <PropertyGroup>
          <OutputType>Exe</OutputType>
          <TargetFrameworks>#{target_framework}</TargetFrameworks>
          <PlatformTarget>AnyCPU</PlatformTarget>
          <RootNamespace>Homebrew</RootNamespace>
          <PackageId>Homebrew.Dotnet</PackageId>
          <Title>Homebrew.Dotnet</Title>
          <Product>$(AssemblyName)</Product>
          <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
        </PropertyGroup>
        <ItemGroup>
          <Compile Include="test.cs" />
        </ItemGroup>
      </Project>
    EOS
    system bin/"dotnet", "build", "--framework", target_framework, "--output", testpath, testpath/"test.csproj"
    assert_equal "#{testpath}/test.dll,a,b,c\n",
                 shell_output("#{bin}/dotnet run --framework #{target_framework} #{testpath}/test.dll a b c")
  end
end

__END__
diff --git a/src/SourceBuild/tarball/content/repos/installer.proj b/src/SourceBuild/tarball/content/repos/installer.proj
index 712d7cd14..31d54866c 100644
--- a/src/SourceBuild/tarball/content/repos/installer.proj
+++ b/src/SourceBuild/tarball/content/repos/installer.proj
@@ -7,7 +7,7 @@

   <PropertyGroup>
     <OverrideTargetRid>$(TargetRid)</OverrideTargetRid>
-    <OverrideTargetRid Condition="'$(TargetOS)' == 'OSX'">osx-x64</OverrideTargetRid>
+    <OverrideTargetRid Condition="'$(TargetOS)' == 'OSX'">osx-$(Platform)</OverrideTargetRid>
     <OSNameOverride>$(OverrideTargetRid.Substring(0, $(OverrideTargetRid.IndexOf("-"))))</OSNameOverride>

     <RuntimeArg>--runtime-id $(OverrideTargetRid)</RuntimeArg>
@@ -28,7 +28,7 @@
     <BuildCommandArgs Condition="'$(TargetOS)' == 'Linux'">$(BuildCommandArgs) /p:AspNetCoreSharedFxInstallerRid=linux-$(Platform)</BuildCommandArgs>
     <!-- core-sdk always wants to build portable on OSX and FreeBSD -->
     <BuildCommandArgs Condition="'$(TargetOS)' == 'FreeBSD'">$(BuildCommandArgs) /p:CoreSetupRid=freebsd-x64 /p:PortableBuild=true</BuildCommandArgs>
-    <BuildCommandArgs Condition="'$(TargetOS)' == 'OSX'">$(BuildCommandArgs) /p:CoreSetupRid=osx-x64</BuildCommandArgs>
+    <BuildCommandArgs Condition="'$(TargetOS)' == 'OSX'">$(BuildCommandArgs) /p:CoreSetupRid=osx-$(Platform)</BuildCommandArgs>
     <BuildCommandArgs Condition="'$(TargetOS)' == 'Linux'">$(BuildCommandArgs) /p:CoreSetupRid=$(TargetRid)</BuildCommandArgs>

     <!-- Consume the source-built Core-Setup and toolset. This line must be removed to source-build CLI without source-building Core-Setup first. -->
diff --git a/src/SourceBuild/tarball/content/repos/runtime.proj b/src/SourceBuild/tarball/content/repos/runtime.proj
index f3ed143f8..2c62d6854 100644
--- a/src/SourceBuild/tarball/content/repos/runtime.proj
+++ b/src/SourceBuild/tarball/content/repos/runtime.proj
@@ -3,7 +3,7 @@

   <PropertyGroup>
     <OverrideTargetRid>$(TargetRid)</OverrideTargetRid>
-    <OverrideTargetRid Condition="'$(TargetOS)' == 'OSX'">osx-x64</OverrideTargetRid>
+    <OverrideTargetRid Condition="'$(TargetOS)' == 'OSX'">osx-$(Platform)</OverrideTargetRid>
     <OverrideTargetRid Condition="'$(TargetOS)' == 'FreeBSD'">freebsd-x64</OverrideTargetRid>
     <OverrideTargetRid Condition="'$(TargetOS)' == 'Windows_NT'">win-x64</OverrideTargetRid>

diff --git a/src/SourceBuild/tarball/content/scripts/bootstrap/buildBootstrapPreviouslySB.csproj b/src/SourceBuild/tarball/content/scripts/bootstrap/buildBootstrapPreviouslySB.csproj
index 0a2fcff17..9033ff11a 100644
--- a/src/SourceBuild/tarball/content/scripts/bootstrap/buildBootstrapPreviouslySB.csproj
+++ b/src/SourceBuild/tarball/content/scripts/bootstrap/buildBootstrapPreviouslySB.csproj
@@ -23,6 +23,14 @@
     <PackageReference Include="runtime.linux-x64.Microsoft.NETCore.ILDAsm" Version="$(RuntimeLinuxX64MicrosoftNETCoreILDAsmVersion)" />
     <PackageReference Include="runtime.linux-x64.Microsoft.NETCore.TestHost" Version="$(RuntimeLinuxX64MicrosoftNETCoreTestHostVersion)" />
     <PackageReference Include="runtime.linux-x64.runtime.native.System.IO.Ports" Version="$(RuntimeLinuxX64RuntimeNativeSystemIOPortsVersion)" />
+    <PackageReference Include="runtime.osx-arm64.Microsoft.NETCore.ILAsm" Version="$(RuntimeOsxArm64MicrosoftNETCoreILAsmVersion)" />
+    <PackageReference Include="runtime.osx-arm64.Microsoft.NETCore.ILDAsm" Version="$(RuntimeOsxArm64MicrosoftNETCoreILDAsmVersion)" />
+    <PackageReference Include="runtime.osx-arm64.Microsoft.NETCore.TestHost" Version="$(RuntimeOsxArm64MicrosoftNETCoreTestHostVersion)" />
+    <PackageReference Include="runtime.osx-arm64.runtime.native.System.IO.Ports" Version="$(RuntimeOsxArm64RuntimeNativeSystemIOPortsVersion)" />
+    <PackageReference Include="runtime.osx-x64.Microsoft.NETCore.ILAsm" Version="$(RuntimeLinuxX64MicrosoftNETCoreILAsmVersion)" />
+    <PackageReference Include="runtime.osx-x64.Microsoft.NETCore.ILDAsm" Version="$(RuntimeLinuxX64MicrosoftNETCoreILDAsmVersion)" />
+    <PackageReference Include="runtime.osx-x64.Microsoft.NETCore.TestHost" Version="$(RuntimeLinuxX64MicrosoftNETCoreTestHostVersion)" />
+    <PackageReference Include="runtime.osx-x64.runtime.native.System.IO.Ports" Version="$(RuntimeLinuxX64RuntimeNativeSystemIOPortsVersion)" />
   </ItemGroup>

   <Target Name="BuildBoostrapPreviouslySourceBuilt" AfterTargets="Restore">

